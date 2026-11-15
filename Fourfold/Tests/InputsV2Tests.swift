//  InputsV2Tests.swift — INPUTS v2 (2026-11-15) §6: the pure functions (§5.1 rankNoteName — POOL and the STACK grid agree).

import XCTest

final class InputsV2Tests: XCTestCase {
    private func pool(_ notes: [UInt8]) -> EuclideousLanePoolNotes { var p = EuclideousLanePoolNotes(); p.notes = notes; p.count = notes.count; return p }

    // §6.2 — rankNoteName is exactly the STACK grid's note path (euclideousStackCellNote + euclideousDisplayNoteName) for every
    // rank × octave × source; POOL (which now calls rankNoteName) therefore reads the same note as the grid — never disagreeing.
    func testRankNoteNameEqualsTheGridPath() {
        let pools: [[UInt8]] = [[], [60], [60, 64, 67], [55, 57, 59, 60, 62], [36, 48, 60]]
        for notes in pools {
            let p = pool(notes)
            for source in EuclideousLaneSource.allCases {
                for keyRoot in [0, 3, 7] {
                    for octave in -2...2 {
                        for rank in 1...8 {
                            let shared = rankNoteName(rank: rank, pool: p, octave: octave, source: source, keyRoot: keyRoot, keyType: .major)
                            let grid = euclideousStackCellNote(row: .rank(rank), pool: p, notesOct: octave)
                                .map { euclideousDisplayNoteName(UInt8($0), source: source, pool: p.notes, keyRoot: keyRoot, keyType: .major) } ?? "\u{2013}"
                            XCTAssertEqual(shared, grid, "rank \(rank) oct \(octave) src \(source) root \(keyRoot) pool \(notes)")
                        }
                    }
                }
            }
        }
    }

    // §9.2 / §7 — the octave now shows: a rank named at octave +1 differs from octave 0 (the shift NOW used to miss). The letter is unchanged (an octave is 12 semitones); only the digit moves.
    func testOctaveMovesTheName() {
        let p = pool([55, 57, 59, 60, 62])   // G A B C D
        let at0 = rankNoteName(rank: 1, pool: p, octave: 0, source: .chords, keyRoot: 0, keyType: .major)
        let up1 = rankNoteName(rank: 1, pool: p, octave: 1, source: .chords, keyRoot: 0, keyType: .major)
        let up2 = rankNoteName(rank: 1, pool: p, octave: 2, source: .chords, keyRoot: 0, keyType: .major)
        XCTAssertNotEqual(at0, up1, "octave +1 shifts the name")
        XCTAssertNotEqual(up1, up2, "octave +2 shifts it again")
        XCTAssertTrue(at0.first == up1.first, "the letter is unchanged by an octave")   // both start on the same pitch class
    }

    // §5.1 — out-of-range ⇒ "–" / "no note" (matching the grid's drop).
    func testOutOfRangeIsDash() {
        let p = pool([2])   // a very low pool
        XCTAssertEqual(rankNoteName(rank: 1, pool: p, octave: -2, source: .chords, keyRoot: 0, keyType: .major), "\u{2013}")
        XCTAssertEqual(rankNoteNameSpoken(rank: 1, pool: p, octave: -2, source: .chords, keyRoot: 0, keyType: .major), "no note")
        XCTAssertEqual(rankNoteName(rank: 1, pool: pool([]), octave: 0, source: .chords, keyRoot: 0, keyType: .major), "\u{2013}", "empty pool")
    }

    // §6.3 — APPLY TO ALL copies SOURCES (poolSrcMask) + MIDI mode onto the other three lanes and leaves their DELAY CHORD (chordDelay) untouched; the source lane is unchanged. (The "one undo restores all three" is guaranteed by the one onEdit call.)
    func testApplyToAllCopiesSourcesAndMidiModeNotCanon() {
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[1].poolSrcMask = 0b10101; lines[1].midiMode = .root; lines[1].chordDelay = 3
        for i in [0, 2, 3] { lines[i].chordDelay = i + 1; lines[i].poolSrcMask = 0; lines[i].midiMode = .add }   // distinct, to prove the copy + the untouched canon
        euclideousApplyInputsToAll(&lines, from: 1)
        for i in [0, 2, 3] {
            XCTAssertEqual(lines[i].poolSrcMask, 0b10101, "lane \(i) copies SOURCES")
            XCTAssertEqual(lines[i].midiMode, .root, "lane \(i) copies MIDI mode")
            XCTAssertEqual(lines[i].chordDelay, i + 1, "lane \(i) DELAY CHORD untouched")
        }
        XCTAssertEqual(lines[1].chordDelay, 3, "the source lane is unchanged")
        // out-of-range idx is a no-op
        var a = lines; euclideousApplyInputsToAll(&a, from: 9); XCTAssertEqual(a, lines)
    }

    // §6.5 — the card's row heights + fit/scroll. At a comfortable height the four rows are at their ideals (44/30/30/44) and it fits; a very short height scrolls with no row under 30.
    func testInputsLayoutRowsAndFit() {
        let big = euclideousInputsTabLayout(contentAreaH: 400)
        XCTAssertTrue(big.fits)
        XCTAssertEqual(big.nowH, 44, accuracy: 0.5); XCTAssertEqual(big.canonH, 44, accuracy: 0.5)
        XCTAssertEqual(big.sourcesH, 30, accuracy: 0.5); XCTAssertEqual(big.midiH, 30, accuracy: 0.5)
        let tiny = euclideousInputsTabLayout(contentAreaH: 80)
        XCTAssertFalse(tiny.fits, "the floors do not fit ⇒ the body scrolls")
        for h in tiny.heights { XCTAssertGreaterThanOrEqual(h, 30 - 0.01, "no row squeezed under 30") }
        // the DELAY CHORD label fits its 50 pt column: "DELAY"/"CHORD" are 5 heavy-mono chars at 10 pt ≈ 5·0.6·10 = 30 pt < 50.
        XCTAssertLessThan(5.0 * 0.6 * 10.0, EuclideousPoolTabMetrics.labelColumn)
    }
}
