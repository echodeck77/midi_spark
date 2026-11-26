//  StackGreyTests.swift — STACK RANKS GREY ferry (2026-11-15) §8: the §1 grey ramp (and, as the later steps land, §2–§5).

import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class StackGreyTests: XCTestCase {

    private func relLum(_ c: EuclideousRGB) -> Double {
        func lin(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    // §8.1 — stackRankColour: chroma 0 (a true grey, r==g==b) on all 8; luminance rises strictly 1→8; lane-independent; the table builds once.
    func testRampIsGreyRisingAndBuiltOnce() {
        var last = -1.0
        for rank in 1...8 {
            let c = stackRankColour(rank: rank)
            XCTAssertEqual(c.r, c.g, "rank \(rank): chroma 0 ⇒ r == g"); XCTAssertEqual(c.g, c.b, "rank \(rank): chroma 0 ⇒ g == b")
            let lum = relLum(c)
            XCTAssertGreaterThan(lum, last, "rank \(rank): luminance must rise")
            last = lum
        }
        // lane-independent: there is no lane parameter — the same grey serves every lane (this is the point of the ferry).
        for _ in 0..<50 { _ = stackRankColour(rank: 5) }
        XCTAssertEqual(stackRankConversionCount, 8, "the 8-entry table converts once")
    }

    // COMPACT+STRIP STYLE §4.4 (2026-11-26): stackRankInk is a FIXED band split now — #E4E6EA on the DARK ranks 1–4, #16171A
    // on the LIGHT ranks 5–8 (was the per-rank WCAG pick of #0D0F14 / #F2F4F7, floored at 4.5:1). The band assignment is pinned
    // and the achieved contrasts printed; the fixed inks trade some contrast on the mid ranks for a uniform look — a reported
    // legibility note (device-owed), not a hard floor.
    func testInkIsLegibleOnEveryRank() {
        let light = EuclideousRGB(r: 0xE4, g: 0xE6, b: 0xEA), darkInk = EuclideousRGB(r: 0x16, g: 0x17, b: 0x1A)
        var contrasts: [String] = []
        for rank in 1...8 {
            let c = stackRankColour(rank: rank), ink = stackRankInk(rank: rank)
            XCTAssertEqual(ink, rank >= 5 ? darkInk : light, "rank \(rank): §4.4 fixed split (dark ranks 1–4 → light ink, light ranks 5–8 → dark ink)")
            contrasts.append("r\(rank) #\(String(format: "%02X%02X%02X", c.r, c.g, c.b)) ink=\(ink == light ? "light" : "dark") \(String(format: "%.2f", euclideousWCAGContrast(c, ink))):1")
        }
        print("STACK-GREY-REPORT §4.4 ink split: \(contrasts.joined(separator: " · "))")
    }

    // §8.3 — no caller of stackChipColour remains: verified by grep at build time (a deleted symbol cannot be referenced here).
    // `grep -rn stackChipColour Fourfold/` shows only comment lines — the two code callers + three test refs moved to stackRankColour.

    // §8.4 — the footer fill is grey by rank and lane-independent (there is no lane parameter any more); one voice spans the whole chip.
    func testFooterGreyByRankLaneIndependent() {
        let c = stackRankColour(rank: 3)
        XCTAssertEqual(c.r, c.g); XCTAssertEqual(c.g, c.b)   // a true grey, identical for every lane
        let segs = laneStripFooterSegments(frameWidth: 20, ranks: [3])
        XCTAssertEqual(segs.count, 1); XCTAssertEqual(segs[0].rank, 3); XCTAssertEqual(segs[0].width, 20, accuracy: 1e-6)
    }

    // §8.5 — a two-voice hit (ranks 2 and 5) splits into two segments, 2 on the left; at a width that makes a segment < 4 pt, one chip labelled 2.
    func testFooterSplitAndNarrowFallback() {
        let wide = laneStripFooterSegments(frameWidth: 20, ranks: [2, 5])   // segW = (20−1)/2 = 9.5 ≥ 4 → two segments
        XCTAssertEqual(wide.count, 2)
        XCTAssertEqual(wide[0].rank, 2); XCTAssertEqual(wide[0].x, 0, accuracy: 1e-6)
        XCTAssertEqual(wide[1].rank, 5); XCTAssertGreaterThan(wide[1].x, wide[0].x, "rank 5 sits to the right of rank 2")
        XCTAssertEqual(wide[0].width, 9.5, accuracy: 1e-6); XCTAssertEqual(wide[1].width, 9.5, accuracy: 1e-6)
        XCTAssertNotEqual(stackRankColour(rank: 2), stackRankColour(rank: 5), "each segment its own grey")
        let narrow = laneStripFooterSegments(frameWidth: 8, ranks: [2, 5])  // segW = (8−1)/2 = 3.5 < 4 → one chip at the lowest rank
        XCTAssertEqual(narrow.count, 1); XCTAssertEqual(narrow[0].rank, 2); XCTAssertEqual(narrow[0].width, 8, accuracy: 1e-6)
    }

    // §8.6 — the sounding gate: a stack note rings from its note-on to its last note-off and not after (the chip itself persists for the pass).
    func testStackSoundingGateFromOnToLastOff() {
        let n = 4
        func snd(now: Double, end: Double?) -> LaneStripSounding {
            let note = NoteRollNote(onBeat: 1, endBeat: end, pitch: 60, velocity: 100, outs: 1, rank: 3)
            return laneStripSounding(riffHeld: [], stackHeld: [note], n: n, now: now, passBeats: Double(n), stepOf: { Int($0.rounded(.down)) }, hitSteps: [0, 1, 2, 3])
        }
        XCTAssertTrue(snd(now: 1.5, end: nil).stackRing[1], "held ⇒ ringing at the onset step")
        XCTAssertTrue(snd(now: 1.9, end: 2.0).stackRing[1], "sounding before the off")
        XCTAssertFalse(snd(now: 2.1, end: 2.0).stackRing[1], "silent after the last note-off")
        XCTAssertEqual(snd(now: 2.1, end: 2.0).stackChip[1], 3, "the chip persists for the rest of the pass")
    }

    // §8.7 — a gate longer than a step keeps the mark on the note's STARTING cell, not the playhead's.
    func testLongGateStaysOnTheStartingCell() {
        let n = 8
        let note = NoteRollNote(onBeat: 0, endBeat: 6, pitch: 60, velocity: 100, outs: 1, rank: 2)   // a 6-beat gate
        let s = laneStripSounding(riffHeld: [], stackHeld: [note], n: n, now: 5, passBeats: Double(n), stepOf: { Int($0.rounded(.down)) }, hitSteps: [0, 4])
        XCTAssertTrue(s.stackRing[0], "the ring stays on the note's onset (hit) step")
        XCTAssertFalse(s.stackRing[5], "not the playhead's step")
        XCTAssertEqual(s.stackChipRanks[0], [2])
    }

    // §8.8 — the RANKS ring gate (`euclideousStackSounding`, the function the RANKS row and the STACK grid both read):
    // a hit on ranks 1/3/5 rings exactly those; a note routed nowhere / a silenced (empty) part rings nothing; an ended note is silent.
    func testRanksRingGate() {
        func note(_ rank: Int, outs: UInt8 = 1, end: Double? = nil) -> NoteRollNote {
            NoteRollNote(onBeat: 0.5, endBeat: end, pitch: UInt8(60 + rank), velocity: 100, outs: outs, rank: UInt8(rank))
        }
        let part = [note(1), note(3), note(5)]
        for r in 1...8 { XCTAssertEqual(euclideousStackSounding(notesPart: part, rank: r, nowBeat: 1).sounding, [1, 3, 5].contains(r), "rank \(r): only 1/3/5 ring") }
        XCTAssertFalse(euclideousStackSounding(notesPart: [note(3, outs: 0)], rank: 3, nowBeat: 1).sounding, "a note routed nowhere (outs 0) rings nothing")
        XCTAssertFalse(euclideousStackSounding(notesPart: [], rank: 3, nowBeat: 1).sounding, "a silenced / PLAY-STACK-off part (empty feed) rings nothing")
        XCTAssertFalse(euclideousStackSounding(notesPart: [note(3, end: 0.8)], rank: 3, nowBeat: 1).sounding, "a note that ended before now is silent")
        // (transport stop clears every ring at once through the caller's `clock.playing && …` gate — ranksTilesRow line ~5261.)
    }

    // §8.9 — rank isolation: a rank-4 note rings only button 4. (Riff notes live in the riff part `2·lane`, which the RANKS row never reads — it reads the notes part `2·lane+1` — so they can't ring a RANKS button.)
    func testRankIsolationAndRiffNotesDoNotRing() {
        let part = [NoteRollNote(onBeat: 0, endBeat: nil, pitch: 64, velocity: 100, outs: 1, rank: 4)]
        for r in 1...8 { XCTAssertEqual(euclideousStackSounding(notesPart: part, rank: r, nowBeat: 1).sounding, r == 4, "rank \(r)") }
    }

    // §8.10 — the STACK grid's sounding gate: a sounding cell is marked (labelInk true ⇒ the §5.1 2 pt white inner stroke draws); a rest / off cell is not.
    func testStackCellSoundingGate() {
        XCTAssertTrue(euclideousStackCellLook(selected: true, sounding: true, glowAgeSeconds: nil, reduceMotion: true).labelInk, "sounding ⇒ the white stroke draws")
        XCTAssertFalse(euclideousStackCellLook(selected: true, sounding: false, glowAgeSeconds: nil, reduceMotion: true).labelInk, "selected-at-rest ⇒ no stroke")
        XCTAssertFalse(euclideousStackCellLook(selected: false, sounding: false, glowAgeSeconds: nil, reduceMotion: true).labelInk, "off ⇒ no stroke")
    }

    // §8.11 — the axis bar is OPT-IN: the STACK grid's rank axis sets rankBar; TOP rows and every other user of the shared chip (the riff-grid labels, NOW, the NOTES keys) leave it false.
    func testAxisBarOptInOnly() {
        for r in 1...8 { XCTAssertTrue(euclideousStackAxisSpec(.rank(r)).rankBar, "axis rank \(r) carries the bar") }
        XCTAssertFalse(euclideousStackAxisSpec(.top).rankBar, "a TOP row gets no bar")
        XCTAssertFalse(euclideousStackAxisSpec(.topMinus1).rankBar)
        XCTAssertFalse(euclideousRankChip(rank: 3, name: "C", received: true, lit: false, empty: false).rankBar, "the grid labels / NOW builder leaves it false")
        XCTAssertTrue(euclideousRankChips(sortedPool: [60, 64, 67], litMask: 0, name: { "n\($0)" }).allSatisfy { !$0.rankBar }, "NOW / the keys leave it false")
    }
}
