//  RiffStackDotsTests.swift — RIFF GRID STACK DOTS ferry (2026-11-16) §1/§4: the pure dot derivation.
//  The column is READ from the hit a note started on (EuclideousStripHit.column), mapped by the lane
//  strip's own onset→step snap (§1.6); the fade is a stateless ease-out of (now − endBeat). Display-only.

import XCTest
import CoreGraphics

final class RiffStackDotsTests: XCTestCase {

    // A tiny strip: steps 0…3, hits at step 1 (riff column 2) and step 3 (riff column 5).
    private let hits: [EuclideousStripHit] = [
        EuclideousStripHit(kind: .rhythmRest),
        EuclideousStripHit(kind: .hit, column: 2, tick: 0),
        EuclideousStripHit(kind: .rhythmRest),
        EuclideousStripHit(kind: .hit, column: 5, tick: 1),
    ]
    private let hitSteps = [1, 3]
    private func stepOf(_ b: Double) -> Int { Int(b.rounded()) }   // onBeat → step, 1:1 for the test
    private func held(onBeat: Double, end: Double? = nil, outs: UInt8 = 1, rank: UInt8 = 4) -> NoteRollNote {
        NoteRollNote(onBeat: onBeat, endBeat: end, pitch: 60, velocity: 100, outs: outs, rank: rank)
    }

    // §1.2/§1.3: a held note on a hit step → a dot at (that hit's riff column − 1, the stack rank), opacity 1.
    func testOnsetMapsToStartColumnZeroBased() {
        let dots = euclideousRiffStackDots(lane: 2, stackHeld: [held(onBeat: 1, rank: 4)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1, fadeSeconds: 0.16, secPerBeat: 0.5)
        XCTAssertEqual(dots, [EuclideousRiffStackDot(lane: 2, column: 1, rank: 4, opacity: 1)], "hit step 1 → riff column 2 → 0-based column 1")
    }

    // §4.6 / §B1.3: a LATE note (long gate / TIE, onset drifts past its hit) snaps back to the hit's own step → its column.
    func testLateNoteSnapsToItsHitStep() {
        let dots = euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 3.4, rank: 6)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 3.4, fadeSeconds: 0.16, secPerBeat: 0.5)
        // 3.4 rounds to step 3 (a hit, column 5) directly; snap confirms it stays there.
        XCTAssertEqual(dots, [EuclideousRiffStackDot(lane: 0, column: 4, rank: 6, opacity: 1)])
    }

    // §5: a note routed nowhere (outs == 0) lights nothing.
    func testOutsZeroNoDot() {
        XCTAssertTrue(euclideousRiffStackDots(lane: 1, stackHeld: [held(onBeat: 1, outs: 0)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
    }

    // §4: fadeSeconds 0 ⇒ an ended note is a hard cut (no dot the instant it stops).
    func testHardCutWhenFadeZero() {
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, end: 1)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1.0001, fadeSeconds: 0, secPerBeat: 0.5).isEmpty)
    }

    // §4: within the 160 ms window after note-off, the dot fades by the ease-out curve; past it, it is gone.
    func testFadeAfterNoteOff() {
        // secPerBeat 0.5 ⇒ 0.16 s = 0.32 beats of fade. End at beat 1; halfway (now = 1.16) ⇒ age 0.5 ⇒ opacity 0.25.
        let half = euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, end: 1)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1.16, fadeSeconds: 0.16, secPerBeat: 0.5)
        XCTAssertEqual(half.count, 1)
        XCTAssertEqual(half[0].opacity, 0.25, accuracy: 1e-9, "age 0.5 → (1−0.5)^2 = 0.25")
        // past the window ⇒ gone.
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, end: 1)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1.5, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
    }

    // A still-held note (endBeat nil) or one whose gate has not closed is full strength.
    func testHeldIsFullStrength() {
        let dots = euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, end: 10)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 2, fadeSeconds: 0.16, secPerBeat: 0.5)
        XCTAssertEqual(dots.first?.opacity, 1)
    }

    // A rank outside 1…8, or a note before its onset, draws nothing.
    func testRankOutOfRangeAndFutureOnsetDropped() {
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, rank: 0)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 1, rank: 9)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 5)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 1, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty, "onset after now")
    }

    // A note that snaps to a REST cell (no column) draws nothing; empty hits ⇒ no dots.
    func testNoColumnNoDot() {
        let restOnly: [EuclideousStripHit] = [EuclideousStripHit(kind: .rhythmRest), EuclideousStripHit(kind: .rhythmRest)]
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 0)], hits: restOnly, stepOf: stepOf, hitSteps: [], now: 0, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [held(onBeat: 0)], hits: [], stepOf: stepOf, hitSteps: [], now: 0, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty)
    }

    // §4: the ease-out curve — 1 at age 0, 0 at age 1, 0.25 at 0.5, monotone decreasing.
    func testFadeCurve() {
        XCTAssertEqual(euclideousRiffStackDotFade(0), 1, accuracy: 1e-9)
        XCTAssertEqual(euclideousRiffStackDotFade(1), 0, accuracy: 1e-9)
        XCTAssertEqual(euclideousRiffStackDotFade(0.5), 0.25, accuracy: 1e-9)
        XCTAssertEqual(euclideousRiffStackDotFade(-0.3), 1, accuracy: 1e-9, "clamps below 0")
        XCTAssertEqual(euclideousRiffStackDotFade(1.3), 0, accuracy: 1e-9, "clamps above 1")
        var prev = 2.0
        for i in 0...10 { let v = euclideousRiffStackDotFade(Double(i) / 10); XCTAssertLessThanOrEqual(v, prev); prev = v }
    }

    // POLY: a 16-column grid lets a hit sit past column 8 — it is kept when `columns` admits it, dropped under the MONO default.
    func testPolyColumnBeyondEight() {
        let polyHits: [EuclideousStripHit] = [EuclideousStripHit(kind: .hit, column: 13, tick: 0)]
        let note = held(onBeat: 0, rank: 3)
        XCTAssertEqual(euclideousRiffStackDots(lane: 0, stackHeld: [note], hits: polyHits, stepOf: { _ in 0 }, hitSteps: [0], now: 0, fadeSeconds: 0.16, secPerBeat: 0.5, columns: 16),
                       [EuclideousRiffStackDot(lane: 0, column: 12, rank: 3, opacity: 1)])
        XCTAssertTrue(euclideousRiffStackDots(lane: 0, stackHeld: [note], hits: polyHits, stepOf: { _ in 0 }, hitSteps: [0], now: 0, fadeSeconds: 0.16, secPerBeat: 0.5).isEmpty, "MONO default (columns 8) drops column 13")
    }

    // Two lanes striking the same (column, rank) each get their own dot (the view steps them right-to-left).
    func testMultipleNotesEachGetADot() {
        let dots = euclideousRiffStackDots(lane: 3, stackHeld: [held(onBeat: 1, rank: 4), held(onBeat: 3, rank: 7)], hits: hits, stepOf: stepOf, hitSteps: hitSteps, now: 3, fadeSeconds: 0.16, secPerBeat: 0.5)
        XCTAssertEqual(dots.count, 2)
        XCTAssertEqual(Set(dots.map { $0.column }), [1, 4])   // step 1 → col 1, step 3 → col 4
    }
}
