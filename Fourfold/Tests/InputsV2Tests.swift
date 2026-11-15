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
}
