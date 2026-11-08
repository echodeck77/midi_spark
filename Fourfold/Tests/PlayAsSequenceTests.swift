//  PlayAsSequenceTests.swift — PLAY AS SEQUENCE ferry (2026-11-08): the lit notes play through a SEQUENCE of (mode, hit-count) chips that advances by hits, loops after the last chip, and resets at the lane's melody restart.
//
//  The active chip is a PURE function of the hit ordinal since the melody origin (`euclideousPlaySeqActive`), which already resets at a melody restart (`euclideousNotesHitOrdinal`/`advOrd`, pinned by RestartScheduleTests).
//  So the pure test fixes the walk/loop/single-chip-identity, and the Router test proves the reset end to end: under MELODY [1] every pass is identical; under a FREE melody the passes diverge once the sequence outlasts one pass.

import XCTest

final class PlayAsSequenceTests: XCTestCase {
    // MARK: the pure sequence clock
    func testTheActiveChipWalksTheSequenceLoopsAndResetsAtTheOrigin() {
        let seq = [EuclideousPlayStep(mode: .cycle, hits: 2), EuclideousPlayStep(mode: .roll, hits: 3), EuclideousPlayStep(mode: .build, hits: 1)]   // total 6: 0,1 cycle · 2,3,4 roll · 5 build
        let expect: [(Int64, Int, EuclidNotesPlayAs)] = [
            (0, 0, .cycle), (1, 0, .cycle), (2, 1, .roll), (3, 1, .roll), (4, 1, .roll), (5, 2, .build),
            (6, 0, .cycle), (7, 0, .cycle), (8, 1, .roll),   // loops after the last chip
        ]
        for (h, idx, mode) in expect {
            let a = euclideousPlaySeqActive(seq: seq, hitOrdinal: h)
            XCTAssertEqual(a.index, idx, "chip index at h=\(h)"); XCTAssertEqual(a.mode, mode, "mode at h=\(h)")
        }
        // A melody restart makes the hit ordinal return to 0 (RestartScheduleTests pins advOrd == 0 at each restart), so the hit AT the restart is chip 0 again — the sequence and every count reset together.
        XCTAssertEqual(euclideousPlaySeqActive(seq: seq, hitOrdinal: 0).index, 0, "at the melody origin the sequence is back to its first chip")
        // A single chip is always active, whatever the hit (the migrated single value is byte-identical to the old engine).
        let single = [EuclideousPlayStep(mode: .bounce, hits: 7)]
        for h: Int64 in [0, 1, 6, 7, 100, -4] { XCTAssertEqual(euclideousPlaySeqActive(seq: single, hitOrdinal: h).mode, .bounce) }
    }

    // MARK: the six new modes on a four-note list (faithful to the pop-up subtitles)
    func testTheNewModesPickFaithfullyToTheirSubtitles() {
        var list = EuclideousNotesList()                       // four notes, lit order = pitch order here
        for p in [60, 64, 67, 72] { list.append(pitch: p, position: 0, rank: 0) }
        func picks(_ way: EuclidNotesPlayAs, _ k: Int) -> [Int] {
            let p = euclideousNotesWayPick(list: list, way: way, k: k); return (0..<p.count).map { list.pitch(p[$0]) }
        }
        XCTAssertEqual(picks(.drone, 0), [60]); XCTAssertEqual(picks(.drone, 5), [60], "DRONE is always the lowest, every hit")
        XCTAssertEqual(picks(.reverse, 0), [72]); XCTAssertEqual(picks(.reverse, 1), [67]); XCTAssertEqual(picks(.reverse, 3), [60], "REVERSE goes top down")
        XCTAssertEqual(picks(.alternate, 0), [72]); XCTAssertEqual(picks(.alternate, 1), [60]); XCTAssertEqual(picks(.alternate, 2), [67]); XCTAssertEqual(picks(.alternate, 3), [64], "ALTERNATE: high, low, inward")
        XCTAssertEqual(picks(.outline, 0), [60]); XCTAssertEqual(picks(.outline, 1), [72]); XCTAssertEqual(picks(.outline, 2), [64]); XCTAssertEqual(picks(.outline, 3), [67], "OUTLINE: edges first, inward")
        XCTAssertEqual(picks(.pairs, 0), [60, 64]); XCTAssertEqual(picks(.pairs, 1), [67, 72], "PAIRS: two at a time, stepping")
        for k in 0..<8 { XCTAssertEqual(picks(.random, k).count, 1); XCTAssertTrue([60, 64, 67, 72].contains(picks(.random, k)[0]), "RANDOM picks one held note") }
        XCTAssertEqual(picks(.random, 3), picks(.random, 3), "RANDOM is replay-exact (deterministic in k)")
        // Every new mode, like the old ones, resolves to the single note on a one-note list and to nothing on an empty list.
        var one = EuclideousNotesList(); one.append(pitch: 55, position: 0, rank: 0)
        let empty = EuclideousNotesList()
        for way in EuclidNotesPlayAs.allCases {
            XCTAssertEqual(euclideousNotesWayPick(list: one, way: way, k: 3).count, 1, "\(way) on one note")
            XCTAssertEqual(euclideousNotesWayPick(list: empty, way: way, k: 0).count, 0, "\(way) on no notes")
        }
    }
}
