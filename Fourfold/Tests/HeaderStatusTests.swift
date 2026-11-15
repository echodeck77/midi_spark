//  HeaderStatusTests.swift — HEADER STATUS BUTTON ferry (2026-11-15) §8: the §7 pure functions.

import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class HeaderStatusTests: XCTestCase {

    // §8.2 — gridStatus: inUse (any lane on the grid), live (running + a lane reading it), column passed through.
    func testGridStatus() {
        // no lane on the grid → hidden
        XCTAssertEqual(euclideousGridStatus(laneOnGrid: [false, false, false, false], laneReading: [false, false, false, false], running: true, column: 3),
                       EuclideousGridStatus(inUse: false, live: false, column: 3))
        // lane 2 on, running + reading → live
        var s = euclideousGridStatus(laneOnGrid: [false, true, false, false], laneReading: [false, true, false, false], running: true, column: 2)
        XCTAssertTrue(s.inUse); XCTAssertTrue(s.live); XCTAssertEqual(s.column, 2)
        // stopped → idle (in use, not live)
        s = euclideousGridStatus(laneOnGrid: [false, true, false, false], laneReading: [false, true, false, false], running: false, column: 2)
        XCTAssertTrue(s.inUse); XCTAssertFalse(s.live)
        // every lane on the grid is stepped aside (REPLACE + MIDI held ⇒ not reading) → idle while running
        s = euclideousGridStatus(laneOnGrid: [true, false, true, false], laneReading: [false, false, false, false], running: true, column: 0)
        XCTAssertTrue(s.inUse); XCTAssertFalse(s.live, "in use but no lane reading it ⇒ idle while running")
    }

    // §8.6 — midiLamp: lit while held; lit within lampHold of a note-on; unlit past it.
    func testMidiLamp() {
        XCTAssertTrue(euclideousMidiLamp(held: 1, lastNoteOnAt: nil, now: 100, lampHold: 0.15), "held ⇒ lit")
        XCTAssertTrue(euclideousMidiLamp(held: 0, lastNoteOnAt: 100.0, now: 100.10, lampHold: 0.15), "note-on 100 ms ago ⇒ lit")
        XCTAssertFalse(euclideousMidiLamp(held: 0, lastNoteOnAt: 100.0, now: 100.151, lampHold: 0.15), "151 ms ⇒ unlit")
        XCTAssertFalse(euclideousMidiLamp(held: 0, lastNoteOnAt: nil, now: 100, lampHold: 0.15), "no note, nothing held ⇒ unlit")
    }

    // §8.3 — the chord name wrapper: a chord column names its chord; a REST column → "–".
    func testChordHeaderName() {
        let degs = [0, 1, 2, 3, 4, 5, 6, 7]   // I ii iii IV V vi vii° REST, C major
        let cols = [Int](repeating: 0, count: 8)
        let (c0, r0) = euclideousChordHeaderName(column: 0, degrees: degs, colours: cols, steps: 8, keyRoot: 0, keyType: .major)
        XCTAssertEqual(c0, "C"); XCTAssertFalse(r0)
        let (c1, r1) = euclideousChordHeaderName(column: 1, degrees: degs, colours: cols, steps: 8, keyRoot: 0, keyType: .major)
        XCTAssertEqual(c1, "Dm"); XCTAssertFalse(r1)
        let (c7, r7) = euclideousChordHeaderName(column: 7, degrees: degs, colours: cols, steps: 8, keyRoot: 0, keyType: .major)
        XCTAssertEqual(c7, "\u{2013}"); XCTAssertTrue(r7, "REST column → en-dash")
    }

    // §8.4 — icon: a mark per non-rest column at its row; the lit column washes full height; nothing beyond STEPS; colour array ignored.
    func testChordIcon() {
        let degs = [0, 7, 8, 11, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]   // 16 long but STEPS 8
        let icon = euclideousChordIconMarks(degrees: degs, steps: 8, size: CGSize(width: 44, height: 14), litColumn: 3)
        XCTAssertNotNil(icon.wash); XCTAssertEqual(icon.wash?.height, 14, "the lit column washes the full height")
        XCTAssertEqual(icon.wash?.width ?? 0, 44.0 / 8, accuracy: 1e-6, "wash is one column pitch wide")
        // column 1 is REST (degree 7) → no mark; 8 marks of 16 columns are NOT drawn (steps 8), REST drops one more
        XCTAssertEqual(icon.marks.count, 7, "8 columns − 1 REST = 7 marks; columns 8…15 beyond STEPS not drawn")
        for m in icon.marks { XCTAssertGreaterThanOrEqual(m.rect.width, EuclideousHeaderStatusMetrics.markMinW) }
        // §3.3 formula at 16 steps (⚠ 1.75, not §8.4's 1.5 — a spec self-inconsistency, reported)
        let m16 = euclideousChordIconMarks(degrees: [Int](repeating: 0, count: 16), steps: 16, size: CGSize(width: 44, height: 14), litColumn: 0)
        XCTAssertEqual(m16.marks.first?.rect.width ?? 0, max(1.5, 44.0 / 16 - 1), accuracy: 1e-6)
        XCTAssertEqual(m16.marks.count, 16)
    }

    // §4.3 — the signed-t text with a true minus.
    func testSignedT() {
        XCTAssertEqual(euclideousHeaderSignedT(2), "+2")
        XCTAssertEqual(euclideousHeaderSignedT(0), "0")
        XCTAssertEqual(euclideousHeaderSignedT(-5), "\u{2212}5")   // true minus
    }

    // §7.3 — headerStatus assembles the parts; §4 lamp/readout presence.
    func testHeaderStatus() {
        let degs = [0, 1, 2, 3, 4, 5, 6, 7], cols = [Int](repeating: 0, count: 8)
        let g1 = EuclideousGridStatus(inUse: true, live: true, column: 1)
        let g2 = EuclideousGridStatus(inUse: false, live: false, column: 0)
        var p = euclideousHeaderStatus(keyRoot: 0, keyType: .major, grid1: g1, grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                                       grid2: g2, grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                                       midiInUse: false, midiLit: false, rootInUse: false, t: 0)
        XCTAssertEqual(p.keyLabel, "C MAJOR"); XCTAssertEqual(p.tokens.count, 1); XCTAssertEqual(p.tokens[0].name, "Dm"); XCTAssertTrue(p.tokens[0].live)
        XCTAssertEqual(p.lamp, .hidden); XCTAssertNil(p.readout)
        // MIDI on + ROOT → lamp + readout
        p = euclideousHeaderStatus(keyRoot: 0, keyType: .major, grid1: g1, grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                                   grid2: g2, grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                                   midiInUse: true, midiLit: true, rootInUse: true, t: 2)
        XCTAssertEqual(p.lamp, .lit); XCTAssertEqual(p.readout, "+2")
        // MIDI on, no ROOT → lamp unlit, no readout
        p = euclideousHeaderStatus(keyRoot: 0, keyType: .major, grid1: g1, grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                                   grid2: g2, grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                                   midiInUse: true, midiLit: false, rootInUse: false, t: 0)
        XCTAssertEqual(p.lamp, .unlit); XCTAssertNil(p.readout)
    }

    // §8.5 — the width changes only when inUse / midiInUse / rootInUse change, never with the column, lamp lit/unlit, or t.
    func testWidthStableWhilePlaying() {
        let degs = [0, 1, 2, 3, 4, 5, 6, 7], cols = [Int](repeating: 0, count: 8)
        func parts(column: Int, lit: Bool, t: Int) -> EuclideousHeaderParts {
            euclideousHeaderStatus(keyRoot: 0, keyType: .major, grid1: EuclideousGridStatus(inUse: true, live: true, column: column), grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                                   grid2: EuclideousGridStatus(inUse: true, live: true, column: column), grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                                   midiInUse: true, midiLit: lit, rootInUse: true, t: t)
        }
        let base = euclideousHeaderWidth(parts: parts(column: 0, lit: true, t: 0), fallbackStep: 0)
        for (c, l, t) in [(3, false, 2), (7, true, -5), (5, false, 0)] {
            XCTAssertEqual(euclideousHeaderWidth(parts: parts(column: c, lit: l, t: t), fallbackStep: 0), base, accuracy: 1e-6, "width unchanged across column/lamp/t")
        }
        // it DOES change when a grid stops being used
        let oneGrid = euclideousHeaderStatus(keyRoot: 0, keyType: .major, grid1: EuclideousGridStatus(inUse: true, live: true, column: 0), grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                                             grid2: EuclideousGridStatus(inUse: false, live: false, column: 0), grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                                             midiInUse: true, midiLit: true, rootInUse: true, t: 0)
        XCTAssertLessThan(euclideousHeaderWidth(parts: oneGrid, fallbackStep: 0), base, "one grid is narrower than two")
    }

    // §8.8 — the fallback steps narrow the tokens; §5.2 widths 104 / 58 / 56.
    func testFallbackTokenWidths() {
        XCTAssertEqual(EuclideousHeaderStatusMetrics.tokenWidth(step: 0), 104)
        XCTAssertEqual(EuclideousHeaderStatusMetrics.tokenWidth(step: 1), 58)
        XCTAssertEqual(EuclideousHeaderStatusMetrics.tokenWidth(step: 2), 56)
    }

    // §6.1 — the spoken chord name (basic).
    func testChordNameSpoken() {
        XCTAssertEqual(euclideousChordNameSpoken("Dm"), "D minor")
        XCTAssertEqual(euclideousChordNameSpoken("C"), "C")
        XCTAssertEqual(euclideousChordNameSpoken("\u{2013}"), "rest")
        XCTAssertEqual(euclideousChordNameSpoken("E\u{266D}maj7"), "E flat major seven")
        XCTAssertEqual(euclideousChordNameSpoken("G7"), "G seven")
    }
}
