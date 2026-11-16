//  ReelScreenTests.swift — REEL redesign Phase 3 slice 3a: the pure layer (shape, layout, selection/snap/zoom, x↔beat, overview density, ×n brackets).
//  Geometry is device-owed; these pin the STRUCTURE (shapes, non-overlap, clamps, round-trips, derivations), not pixel values.

import XCTest
import CoreGraphics

final class ReelScreenTests: XCTestCase {
    private func note(_ cable: UInt8, _ pitch: UInt8, _ start: Double, _ end: Double, vel: UInt8 = 100) -> ReelDeck.Note {
        ReelDeck.Note(cable: cable, note: pitch, vel: vel, start: start, end: end, machine: 0)
    }

    // §shape — a short window is `small` whatever its width; a tall narrow window is `tall`; a roomy landscape is `wide`.
    func testShapeSelection() {
        XCTAssertEqual(reelScreenShape(size: CGSize(width: 1180, height: 300)), .small, "short ⇒ small (AUM strip)")
        XCTAssertEqual(reelScreenShape(size: CGSize(width: 390, height: 844)), .tall, "portrait phone-ish ⇒ tall")
        XCTAssertEqual(reelScreenShape(size: CGSize(width: 1194, height: 834)), .wide, "landscape iPad ⇒ wide")
        XCTAssertEqual(reelScreenShape(size: CGSize(width: 834, height: 1194)), .tall, "portrait iPad ⇒ tall")
    }

    // §layout — regions stack without overlap, the control bar is at the bottom, `small` has no tape strip, the pill is top-trailing.
    func testLayoutRegions() {
        for size in [CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194), CGSize(width: 1180, height: 300)] {
            let L = reelScreenLayout(size: size)
            XCTAssertGreaterThan(L.overview.height, 0)
            XCTAssertGreaterThan(L.closeUp.height, 0)
            XCTAssertEqual(L.hasTape, L.shape != .small, "only wide/tall have a tape strip")
            // vertical order: overview → (tape) → close-up → control bar
            XCTAssertLessThanOrEqual(L.overview.maxY, L.closeUp.minY + 0.5)
            if L.hasTape { XCTAssertLessThanOrEqual(L.overview.maxY, L.tape.minY + 0.5); XCTAssertLessThanOrEqual(L.tape.maxY, L.closeUp.minY + 0.5) }
            XCTAssertLessThanOrEqual(L.closeUp.maxY, L.controlBar.minY + 0.5)
            XCTAssertEqual(L.controlBar.maxY, size.height - ReelScreenMetrics.margin, accuracy: 0.5, "control bar sits at the bottom margin")
            XCTAssertEqual(L.pill.maxX, size.width - ReelScreenMetrics.margin, accuracy: 0.5, "pill top-trailing")
        }
    }
    // §layout floor — a very short wide/tall window flags `belowFloor` (still drawn, a retune signal).
    func testCloseUpFloorFlagged() {
        let L = reelScreenLayout(size: CGSize(width: 900, height: 360))   // tall-ish but squeezed
        if L.shape != .small { XCTAssertEqual(L.belowFloor, L.closeUp.height < ReelScreenMetrics.minCloseUpH) }
    }

    // §window — clamp keeps the window inside [0, sessionEnd] and within the bar limits.
    func testWindowClamp() {
        let bpb = 4.0, sessionEnd = 200.0   // 50 bars
        let c = reelClampWindow(ReelTapeWindow(startBeat: -50, bars: 1000), sessionEndBeat: sessionEnd, beatsPerBar: bpb)
        XCTAssertGreaterThanOrEqual(c.startBeat, 0)
        XCTAssertLessThanOrEqual(c.bars, 50, "can't show more bars than the session has")
        XCTAssertLessThanOrEqual(c.startBeat + c.bars * bpb, sessionEnd + 1e-6)
        let tiny = reelClampWindow(ReelTapeWindow(startBeat: 0, bars: 1), sessionEndBeat: sessionEnd, beatsPerBar: bpb)
        XCTAssertGreaterThanOrEqual(tiny.bars, ReelScreenMetrics.minWindowBars)
    }

    // §mapping — x↔beat round-trips within the tape rect.
    func testXBeatRoundTrip() {
        let tape = CGRect(x: 16, y: 100, width: 1000, height: 120)
        let win = ReelTapeWindow(startBeat: 40, bars: 48), bpb = 4.0
        for beat in stride(from: 40.0, through: 40 + 48 * bpb, by: 17.0) {
            let x = reelTapeXAtBeat(beat, tape: tape, window: win, beatsPerBar: bpb)
            let back = reelTapeBeatAtX(x, tape: tape, window: win, beatsPerBar: bpb)
            XCTAssertEqual(back, beat, accuracy: 1e-6)
        }
    }

    // §selection — snaps to bar lines, Keep N bars grabs back from a point, a handle keeps ≥ 1 bar and clamps.
    func testSelectionSnapAndGrab() {
        let bpb = 4.0
        XCTAssertEqual(reelSnapToBar(beat: 9.5, beatsPerBar: bpb), 8, accuracy: 1e-9)    // nearest bar line (bar 2 at beat 8)
        XCTAssertEqual(reelSnapToBar(beat: 10.1, beatsPerBar: bpb), 12, accuracy: 1e-9)
        let sel = reelSelectionBars(endingAt: 83, bars: 8, beatsPerBar: bpb, sessionEndBeat: 400)
        XCTAssertEqual(sel.endBeat, 84, accuracy: 1e-9, "83 snaps to bar 21 (84)")
        XCTAssertEqual(sel.spanBeats, 8 * bpb, accuracy: 1e-9)
        // a handle drag past the other handle is clamped to a 1-bar span.
        let s2 = reelMoveHandle(sel, .start, toBeat: 999, beatsPerBar: bpb, sessionEndBeat: 400)
        XCTAssertEqual(s2.startBeat, s2.endBeat - bpb, accuracy: 1e-9, "start can't cross end; ≥ 1 bar kept")
        let s3 = reelMoveHandle(sel, .start, toBeat: -50, beatsPerBar: bpb, sessionEndBeat: 400)
        XCTAssertGreaterThanOrEqual(s3.startBeat, 0)
    }

    // §overview — a note lights its own lane's bins and no other lane; each lane normalises to its own peak.
    func testOverviewDensity() {
        let notes = [note(1, 60, 0, 1), note(1, 62, 1, 2), note(3, 64, 50, 51)]   // lane A busy early, lane C one note late
        let d = reelOverviewDensity(notes: notes, sessionEndBeat: 100, bins: 10)
        XCTAssertEqual(d.count, FourfoldPorts.outputCount)
        XCTAssertGreaterThan(d[0][0], 0, "lane A lit in bin 0")
        XCTAssertEqual(d[1].reduce(0, +), 0, "lane B silent")
        XCTAssertGreaterThan(d[2][5], 0, "lane C lit in bin 5 (beat 50 of 100)")
        XCTAssertLessThanOrEqual(d[0].max() ?? 0, 1.0 + 1e-9, "normalised to ≤ 1")
    }

    // §×n — identical adjacent bars become ONE bracket; distinct bars and empty bars yield none.
    func testRepeatBrackets() {
        let bpb = 4.0
        // bars 0,1,2 identical (same note at the same spot), bar 3 different, bar 4 empty.
        let notes = [note(1, 60, 0, 1), note(1, 60, 4, 5), note(1, 60, 8, 9), note(1, 67, 12, 13)]
        let fp = reelBarFingerprints(notes: notes, beatsPerBar: bpb, bars: 5)
        let br = reelRepeatBrackets(fingerprints: fp)
        XCTAssertEqual(br, [ReelRepeatBracket(firstBar: 0, count: 3)], "bars 0–2 repeat ×3; bar 3 differs; bar 4 empty → no bracket")
    }
    func testEmptyBarsNoBracket() {
        let fp = reelBarFingerprints(notes: [], beatsPerBar: 4, bars: 8)   // all empty → all the FNV basis
        XCTAssertTrue(reelRepeatBrackets(fingerprints: fp).isEmpty, "empty bars never bracket")
    }
}
