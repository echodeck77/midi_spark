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

    // HEADER v2 §4.4: the chord icon / miniature grid is DELETED (euclideousChordIconMarks gone). testChordIcon retired.

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

    // HEADER v2 §4.4 / §3.6(a): the token is number(10) · sp6 · name(40) · sp6 · next(34); dropping the next-chord slot (step 1) leaves number · sp6 · name.
    func testFallbackTokenWidths() {
        XCTAssertEqual(EuclideousHeaderStatusMetrics.tokenWidth(showNext: true), 10 + 6 + 40 + 6 + 34)   // 96 full
        XCTAssertEqual(EuclideousHeaderStatusMetrics.tokenWidth(showNext: false), 10 + 6 + 40)            // 56 next hidden
        XCTAssertGreaterThan(EuclideousHeaderStatusMetrics.tokenWidth(showNext: true), EuclideousHeaderStatusMetrics.tokenWidth(showNext: false))

        // the reserved button width narrows when the next-chord slot drops (two tokens, lamp + readout — the widest case)
        let b0 = euclideousHeaderLayoutButtonWidth(tokenCount: 2, lampShown: true, readoutShown: true, step: 0)
        let b1 = euclideousHeaderLayoutButtonWidth(tokenCount: 2, lampShown: true, readoutShown: true, step: 1)
        XCTAssertGreaterThan(b0, b1)
        // the key + lamp + readout + chevron survive (the next-hidden button is never just the key)
        let keyOnly = euclideousHeaderLayoutButtonWidth(tokenCount: 0, lampShown: false, readoutShown: false, step: 0)
        XCTAssertGreaterThan(b1, keyOnly)

        // the chooser: A always 0; B/C drop the next slot (step 1) only when the full token won't fit
        let extra = EuclideousHeaderMetrics.sp8 + EuclideousHeaderMetrics.holdLatchWidth
        XCTAssertEqual(euclideousHeaderFallbackStep(tokenCount: 2, lampShown: true, readoutShown: true, kind: .a, containerW: 0), 0, "A sizes NOTES to the button → never a fallback")
        XCTAssertEqual(euclideousHeaderFallbackStep(tokenCount: 0, lampShown: true, readoutShown: false, kind: .b, containerW: 0), 0, "no tokens → nothing to narrow")
        XCTAssertEqual(euclideousHeaderFallbackStep(tokenCount: 2, lampShown: true, readoutShown: true, kind: .b, containerW: b0 + extra), 0, "fits full → step 0")
        XCTAssertEqual(euclideousHeaderFallbackStep(tokenCount: 2, lampShown: true, readoutShown: true, kind: .b, containerW: b0 + extra - 1), 1, "just under full → drop the next-chord slot")
        XCTAssertEqual(euclideousHeaderFallbackStep(tokenCount: 2, lampShown: true, readoutShown: true, kind: .c, containerW: 0), 1, "narrower than even the name-only token → still step 1 (name never hidden)")
    }

    // §8.9 — the VoiceOver value: key only; one live grid; two grids with one idle while running; stopped (no "waiting"); MIDI playing/quiet; root 0 and +2.
    func testVoiceOver() {
        let degs = [0, 1, 2, 3, 4, 5, 6, 7], cols = [Int](repeating: 0, count: 8)
        let key = euclideousKeySpokenName(root: 0, type: .major)                 // "C major"
        func status(g1 live: Bool, g2inUse: Bool, g2live: Bool, midi: Bool, lit: Bool, root: Bool, t: Int) -> EuclideousHeaderParts {
            euclideousHeaderStatus(keyRoot: 0, keyType: .major,
                grid1: EuclideousGridStatus(inUse: true, live: live, column: 0), grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
                grid2: EuclideousGridStatus(inUse: g2inUse, live: g2live, column: 1), grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
                midiInUse: midi, midiLit: lit, rootInUse: root, t: t)
        }
        // key only — no grid in use, no MIDI
        let bare = euclideousHeaderStatus(keyRoot: 0, keyType: .major,
            grid1: EuclideousGridStatus(inUse: false, live: false, column: 0), grid1Degrees: degs, grid1Colours: cols, grid1Steps: 8,
            grid2: EuclideousGridStatus(inUse: false, live: false, column: 0), grid2Degrees: degs, grid2Colours: cols, grid2Steps: 8,
            midiInUse: false, midiLit: false, rootInUse: false, t: 0)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: bare, keySpoken: key, running: true, t: 0), "C major")

        // one live grid (grid 1 = C, column 0)
        let one = status(g1: true, g2inUse: false, g2live: false, midi: false, lit: false, root: false, t: 0)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: one, keySpoken: key, running: true, t: 0), "C major, grid 1, C")

        // two grids, grid 2 idle while running → "waiting"; the name is SPOKEN (§6.1: "Dm" → "D minor")
        let twoRunning = status(g1: true, g2inUse: true, g2live: false, midi: false, lit: false, root: false, t: 0)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: twoRunning, keySpoken: key, running: true, t: 0), "C major, grid 1, C, grid 2 waiting, D minor")
        // stopped → no "waiting" on an idle grid
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: twoRunning, keySpoken: key, running: false, t: 0), "C major, grid 1, C, grid 2, D minor")

        // MIDI playing / quiet; root at +2 / at 0
        let midiRoot = status(g1: true, g2inUse: false, g2live: false, midi: true, lit: true, root: true, t: 2)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: midiRoot, keySpoken: key, running: true, t: 2), "C major, grid 1, C, MIDI in, playing, root, plus 2")
        let midiQuiet = status(g1: true, g2inUse: false, g2live: false, midi: true, lit: false, root: true, t: 0)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: midiQuiet, keySpoken: key, running: true, t: 0), "C major, grid 1, C, MIDI in, quiet, root, zero")
        // MIDI on with no ROOT → lamp but no readout clause
        let midiNoRoot = status(g1: true, g2inUse: false, g2live: false, midi: true, lit: false, root: false, t: 0)
        XCTAssertEqual(euclideousHeaderVoiceOver(parts: midiNoRoot, keySpoken: key, running: true, t: 0), "C major, grid 1, C, MIDI in, quiet")
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
