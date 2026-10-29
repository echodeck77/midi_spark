//  PolyRiffTests.swift — POLY RIFF ferry (2026-10-29), slice 1: the POLY model, its render-thread copy, the load-time fold of the four riff boxes into one, the 16-column walk and the ring-length maths. Pure functions only
//  (PolyRiff.swift, Models.swift, Derivations.swift); the Router's POLY layer is in PolyRiffRouterTests.

import XCTest

final class PolyRiffTests: XCTestCase {
    private func note(_ c: Int, _ r: Int, _ l: Int = 1) -> EuclideousPolyNote { EuclideousPolyNote(col: c, rank: r, len: l) }

    // MARK: the model

    func testNormalisationClampsClipsAndSorts() {
        let raw = EuclideousPolyRiff(notes: [
            note(3, 2, 99),                     // a length past the grid: clipped at column 15
            note(-1, 2), note(16, 2), note(2, 0), note(2, 9),     // out of range: dropped
            note(5, 4, 4), note(7, 4, 3),       // the same rank: the first is clipped where the second starts
            note(0, 1, 0),                      // a length under 1 reads as 1
            note(9, 8, 2), note(9, 8, 5),       // the same (column, rank): the longest wins
            note(14, 3, 9),                     // runs off the end: clipped at 16
        ])
        let n = raw.normalized.notes
        XCTAssertEqual(n.map { [$0.col, $0.rank, $0.len] }, [[0, 1, 1], [3, 2, 13], [5, 4, 2], [7, 4, 3], [9, 8, 5], [14, 3, 2]],
                       "sorted by (column, rank); every length inside 1…16, inside the grid and clear of the next note at its rank")
        XCTAssertEqual(raw.normalized.normalized, raw.normalized, "normalising twice changes nothing")
    }
    func testNotesAtDifferentRanksMayOverlapAndStack() {
        let r = EuclideousPolyRiff(notes: [note(0, 1, 4), note(0, 3, 4), note(2, 5, 1)]).normalized
        XCTAssertEqual(r.notes.count, 3, "a chord (one column, several ranks) and an overlap across ranks are what POLY is for")
        XCTAssertEqual(r.note(covering: 3, rank: 1)?.col, 0, "a tail cell belongs to its note")
        XCTAssertNil(r.note(covering: 4, rank: 1)); XCTAssertNil(r.note(startingAt: 1, rank: 1))
    }
    func testDecodingIsLenientAndTheFieldsAreOptional() throws {
        let doc = Data(#"{"notes":[{"col":2,"rank":3,"len":4},{"col":"x"},7,{"rank":2}]}"#.utf8)
        let r = try JSONDecoder().decode(EuclideousPolyRiff.self, from: doc)
        XCTAssertEqual(r.normalized.notes.map { [$0.col, $0.rank, $0.len] }, [[2, 3, 4]], "a malformed note is dropped, the rest survive")
        XCTAssertEqual(try JSONDecoder().decode(EuclideousPolyRiff.self, from: Data("{}".utf8)).notes, [])
        // an older document has neither field
        var st = PluginState.makeInit()
        XCTAssertNil(st.riffPoly); XCTAssertNil(st.polyRiff); XCTAssertFalse(st.riffPolyResolved)
        let enc = JSONEncoder(); let dec = JSONDecoder()
        let old = try dec.decode(PluginState.self, from: enc.encode(st))
        XCTAssertNil(old.riffPoly); XCTAssertNil(old.polyRiff)
        st.riffPoly = true; st.polyRiff = EuclideousPolyRiff(notes: [note(1, 2, 3)])
        let back = try dec.decode(PluginState.self, from: enc.encode(st))
        XCTAssertEqual(back.riffPoly, true); XCTAssertEqual(back.polyRiff, st.polyRiff)
    }
    func testSeedingCopiesTheMonoRiffTwiceOver() {
        var mono = EuclideousRiff(steps: 8, ranks: [1, 0, 3, 5, 0, 2, 8, 4])
        let s = EuclideousPolyRiff.seeded(from: mono)
        XCTAssertEqual(s.notes.count, 12, "six notes in each half; rests stay empty")
        for rep in 0..<2 { for c in 0..<8 {
            let want = mono.ranksResolved[c]
            XCTAssertEqual(s.note(startingAt: rep * 8 + c, rank: want)?.len, want >= 1 ? 1 : nil, "column \(rep * 8 + c)")
        } }
        mono = .empty
        XCTAssertTrue(EuclideousPolyRiff.seeded(from: mono).isEmpty)
    }

    // MARK: the render thread's copy

    func testTheSnapshotCopyHoldsStartsAndLengths() {
        let r = EuclideousPolyRiff(notes: [note(0, 1, 3), note(0, 4, 1), note(5, 8, 2), note(15, 2, 9)])
        let s = PolyRiffSnap(r, on: true)
        XCTAssertTrue(s.on); XCTAssertEqual(s.starts.count, 16); XCTAssertEqual(s.lengths.count, 128)
        XCTAssertEqual(s.startMask(0), 0b0000_1001); XCTAssertEqual(s.startMask(5), 0b1000_0000); XCTAssertEqual(s.startMask(15), 0b10); XCTAssertEqual(s.startMask(3), 0)
        XCTAssertEqual(s.length(col: 0, rank: 1), 3); XCTAssertEqual(s.length(col: 0, rank: 4), 1); XCTAssertEqual(s.length(col: 5, rank: 8), 2)
        XCTAssertEqual(s.length(col: 15, rank: 2), 1, "clipped at the grid's end by normalisation"); XCTAssertEqual(s.length(col: 1, rank: 1), 0)
        XCTAssertEqual([0, 5, 15, 3].map { s.topRank($0) }, [4, 8, 2, 0], "the highest rank starting on a column stands for it")
        XCTAssertFalse(PolyRiffSnap().on, "the default snapshot is MONO")
        XCTAssertEqual(s.startMask(-1), 0); XCTAssertEqual(s.startMask(16), 0); XCTAssertEqual(s.length(col: 16, rank: 1), 0); XCTAssertEqual(s.length(col: 0, rank: 9), 0)
    }
    func testTheDocumentResolvesToThatSnapshot() {
        var st = PluginState.makeInit()
        XCTAssertFalse(st.polyRiffSnapResolved.on, "MONO by default")
        st.polyRiff = EuclideousPolyRiff(notes: [note(2, 3, 2)])
        XCTAssertFalse(st.polyRiffSnapResolved.on, "a stored POLY riff does nothing while the mode is MONO")
        st.riffPoly = true
        XCTAssertTrue(st.polyRiffSnapResolved.on); XCTAssertEqual(st.polyRiffSnapResolved.length(col: 2, rank: 3), 2)
    }

    // MARK: four riff boxes → one

    func testTheLoadFoldKeepsTheActiveRiffAsTheOnlyOne() {
        let a = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1]), b = EuclideousRiff(steps: 8, ranks: [2, 2, 2, 2, 2, 2, 2, 2])
        let c = EuclideousRiff(steps: 8, ranks: [3, 3, 3, 3, 3, 3, 3, 3]), d = EuclideousRiff(steps: 8, ranks: [4, 4, 4, 4, 4, 4, 4, 4])
        for active in 0..<4 {
            var st = PluginState.makeInit(); st.riffs = [a, b, c, d]; st.activeRiff = active
            let playedBefore = st.riffsResolved[st.activeRiffResolved]
            st.normalizeRiffsAtLoad()
            XCTAssertEqual(st.riffsResolved[st.activeRiffResolved], playedBefore, "the riff that played is the riff that plays (active \(active))")
            XCTAssertEqual(st.activeRiffResolved, 0); XCTAssertEqual(st.riffs?.count, 1)
            XCTAssertEqual(st.riffsResolved.dropFirst().map { $0 }, [.empty, .empty, .empty], "the others are gone")
            let once = st; st.normalizeRiffsAtLoad(); XCTAssertEqual(st, once, "idempotent")
        }
    }
    func testTheLoadFoldLeavesTheLegacyAndUntouchedDocumentsAlone() {
        var plain = PluginState.makeInit(); let before = plain
        plain.normalizeRiffsAtLoad(); XCTAssertEqual(plain, before, "riffs nil and no active riff: the singular riff already is slot 0")
        var legacy = PluginState.makeInit(); legacy.euclideousRiff = EuclideousRiff(steps: 8, ranks: [5, 5, 5, 5, 5, 5, 5, 5])
        let want = legacy.riffsResolved[0]
        legacy.normalizeRiffsAtLoad(); XCTAssertEqual(legacy.riffsResolved[0], want)
        var empty = PluginState.makeInit(); empty.activeRiff = 2          // the editor was parked on a still-empty box
        empty.normalizeRiffsAtLoad()
        XCTAssertEqual(empty.riffsResolved[0], .empty, "riff 3 was the active, empty one: it is what played")
        XCTAssertEqual(empty.activeRiffResolved, 0)
    }

    func testAUserPresetFoldsToOneRiffOnLoad() throws {
        var st = PluginState.makeInit()
        st.riffs = [EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1]), EuclideousRiff(steps: 8, ranks: [2, 2, 2, 2, 2, 2, 2, 2]),
                    EuclideousRiff(steps: 8, ranks: [3, 3, 3, 3, 3, 3, 3, 3]), EuclideousRiff(steps: 8, ranks: [4, 4, 4, 4, 4, 4, 4, 4])]
        st.activeRiff = 2
        let played = st.riffsResolved[2]
        let data = try XCTUnwrap(PresetStore.encode(st))
        let back = try XCTUnwrap(PresetStore.decode(data))
        XCTAssertEqual(back.riffsResolved[back.activeRiffResolved], played, "the riff that was active is the one riff")
        XCTAssertEqual(back.riffs?.count, 1); XCTAssertEqual(back.activeRiffResolved, 0)
    }

    // MARK: 16 columns, and MONO's 8 unchanged

    func testTheDefaultColumnCountIsTheOldEight() {
        var rng = PolyRiffRNG(0xF00D)
        for _ in 0..<2000 {
            let dir: RiffDir = [.forward, .reverse, .pendulum, .pingpong][Int(rng.next() % 4)]
            let ord = Int64(rng.next() % 500), every = Int(rng.next() % 4) + 1, len = Int(rng.next() % 8) + 1, stride = Int(rng.next() % 7) + 1, shift = Int(rng.next() % 8)
            XCTAssertEqual(euclideousRiffColumn(ordinal: ord, every: every, direction: dir, length: len, stride: stride, shift: shift),
                           euclideousRiffColumn(ordinal: ord, every: every, direction: dir, length: len, stride: stride, shift: shift, columns: 8))
        }
    }
    func testASixteenColumnWalkWrapsAtSixteen() {
        // LEN 16 FWD, SHIFT 5: columns 5…15, then 0…4
        let cols = (0..<16).map { euclideousRiffColumn(ordinal: Int64($0), every: 1, direction: .forward, length: 16, stride: 1, shift: 5, columns: 16) }
        XCTAssertEqual(cols, Array(5..<16) + Array(0..<5))
        // LEN 6 SHIFT 14 FWD: 14, 15, 0, 1, 2, 3
        XCTAssertEqual((0..<6).map { euclideousRiffColumn(ordinal: Int64($0), every: 1, direction: .forward, length: 6, stride: 1, shift: 14, columns: 16) }, [14, 15, 0, 1, 2, 3])
        // REV over 16
        XCTAssertEqual((0..<4).map { euclideousRiffColumn(ordinal: Int64($0), every: 1, direction: .reverse, length: 16, stride: 1, shift: 0, columns: 16) }, [15, 14, 13, 12])
    }
    func testTheLaneResolversTakeTheGridsWidth() {
        var l = EuclidLine(target: 0, pulses: 4, steps: 8)
        XCTAssertEqual(l.riffLengthResolved, 8); XCTAssertEqual(l.riffLengthResolved(columns: 8), 8); XCTAssertEqual(l.riffLengthResolved(columns: 16), 16, "nil walks the whole grid")
        l.riffLength = 12; XCTAssertEqual(l.riffLengthResolved, 8, "MONO still reads at most 8"); XCTAssertEqual(l.riffLengthResolved(columns: 16), 12)
        l.riffLength = 99; XCTAssertEqual(l.riffLengthResolved(columns: 16), 16); l.riffLength = 0; XCTAssertEqual(l.riffLengthResolved(columns: 16), 1)
        l.riffRotate = 11; XCTAssertEqual(l.riffRotateResolved, 3); XCTAssertEqual(l.riffRotateResolved(columns: 8), 3); XCTAssertEqual(l.riffRotateResolved(columns: 16), 11)
        l.riffRotate = -3; XCTAssertEqual(l.riffRotateResolved, 5); XCTAssertEqual(l.riffRotateResolved(columns: 16), 13)
    }

    // MARK: ring length

    func testHitsAheadIsLengthLessOneStepOfEveryHits() {
        XCTAssertEqual(euclideousPolyHitsAhead(len: 1, every: 1), 0); XCTAssertEqual(euclideousPolyHitsAhead(len: 1, every: 4), 0, "a length-1 note is MONO's whatever EVERY is")
        XCTAssertEqual(euclideousPolyHitsAhead(len: 3, every: 1), 2); XCTAssertEqual(euclideousPolyHitsAhead(len: 3, every: 2), 4); XCTAssertEqual(euclideousPolyHitsAhead(len: 16, every: 8), 120)
        XCTAssertEqual(euclideousPolyHitsAhead(len: 0, every: 0), 0)
    }
    private let allHits = [Bool](repeating: true, count: 4)
    private func ring(_ n: Int, gate: Double = 0.5, tick: Int64 = 0, buf: [Bool]? = nil, chains: EuclideousLaneRestartChains = .off, sub: Double = 1) -> Double {
        let b = buf ?? allHits
        return euclideousPolyRingBeats(hitsAhead: n, gate: gate, nextHitGapBeats: sub, minGateBeats: 0.01, buf: b, eN: b.count, dir: .fwd, cycleLen: b.count, sub: sub, tick: tick, chains: chains, legacySpanBeats: Double(b.count) * sub)
    }
    func testRingLengthIsTheGapsUpToTheLastHitPlusGateOfTheNext() {
        XCTAssertEqual(ring(0), 0.5, accuracy: 1e-9, "n 0 is MONO's gate × gap")
        XCTAssertEqual(ring(0, gate: 0.9), 0.9, accuracy: 1e-9)
        XCTAssertEqual(ring(1), 1.5, accuracy: 1e-9); XCTAssertEqual(ring(2), 2.5, accuracy: 1e-9); XCTAssertEqual(ring(5), 5.5, accuracy: 1e-9)
        XCTAssertEqual(ring(3, gate: 0.25), 3.25, accuracy: 1e-9)
        XCTAssertEqual(ring(2, tick: 7), 2.5, accuracy: 1e-9, "the same from any tick")
        XCTAssertEqual(ring(0, gate: 0.001), 0.01, accuracy: 1e-9, "the floor applies to the whole note")
    }
    func testRingLengthFollowsTheRealHitSpacing() {
        // hits at steps 0, 1, 3 of a 4-step cycle (a gap of 1, then 2, then 1 to the next lap's hit at 4)
        let buf = [true, true, false, true]
        XCTAssertEqual(ring(1, buf: buf), 1 + 0.5 * 2, accuracy: 1e-9, "from step 0: the next hit is 1 away, the one after is 3 away")
        XCTAssertEqual(ring(2, buf: buf), 3 + 0.5 * 1, accuracy: 1e-9)
        XCTAssertEqual(ring(3, buf: buf), 4 + 0.5 * 1, accuracy: 1e-9, "and across the lap")
    }
    func testAMelodyRestartEndsTheNoteAtThatHit() {
        // melody [1]: the walk restarts at every pass of 4 steps, so a note struck on pass-hit 2 may ring at most to the next pass's first hit, 2 hits on
        let chains = EuclideousLaneRestartChains(rhythm: .free, melody: .from([1]), barBeats: 4, lapBeats: 4)
        XCTAssertEqual(ring(5, tick: 2, chains: chains), 2.0, accuracy: 1e-9, "cut at the restart hit, not scaled by the gate")
        XCTAssertEqual(ring(1, tick: 2, chains: chains), 1.5, accuracy: 1e-9, "a span that ends before the restart is untouched")
        XCTAssertEqual(ring(2, tick: 2, chains: chains), 2.0, accuracy: 1e-9, "…and one that reaches it is cut there")
    }
    func testTheStepModeRingIsPlainTime() {
        XCTAssertEqual(euclideousPolyRingBeatsStep(len: 1, every: 1, gate: 0.5, nextHitGapBeats: 2, sub: 0.5, minGateBeats: 0.01), 1.0, accuracy: 1e-9, "length 1: MONO's gate × gap")
        XCTAssertEqual(euclideousPolyRingBeatsStep(len: 3, every: 2, gate: 0.5, nextHitGapBeats: 2, sub: 0.5, minGateBeats: 0.01), 2.0 + 1.0, accuracy: 1e-9, "(3 − 1) × 2 steps of 0.5, then gate × the gap")
    }

    // MARK: slice 3 — the restart tile's track at 16 columns

    func testTheCycleOrderHoldsSixteenColumns() {
        let o = euclideousRiffCycleOrder(dir: .forward, length: 16, stride: 1, shift: 0, columns: 16)
        XCTAssertEqual(o.length, 16); XCTAssertEqual(o.period, 16); XCTAssertEqual(o.visited, 16)
        XCTAssertEqual((0..<16).map { o.cell(ofColumn: $0) }, (0..<16).map { Optional($0) }, "FWD: column i is cell i")
        XCTAssertEqual((0..<16).map { o.column(ofCell: $0) }, Array(0..<16))
        XCTAssertEqual((0..<16).map { o.distinctThrough(step: $0) }, Array(1...16))
        let rev = euclideousRiffCycleOrder(dir: .reverse, length: 16, stride: 1, shift: 3, columns: 16)
        XCTAssertEqual(rev.column(ofCell: 0), 2, "REV from the last window column: (15 + 3) mod 16"); XCTAssertEqual(rev.cell(ofColumn: 2), 0)
        let ping = euclideousRiffCycleOrder(dir: .pingpong, length: 16, stride: 1, shift: 0, columns: 16)
        XCTAssertEqual(ping.period, 32); XCTAssertEqual(ping.visited, 16); XCTAssertEqual(ping.distinctThrough(step: 31), 16)
        XCTAssertEqual(ping.distinctThrough(step: 5), 6)
        // MONO is the 8-column track it always was
        let mono = euclideousRiffCycleOrder(dir: .pendulum, length: 8, stride: 1, shift: 0)
        XCTAssertEqual(mono.columnCells.count, 8); XCTAssertEqual(mono.period, 14)
    }
    func testTheMelodyTileOfAPolyLaneHasOneCellPerWalkedColumn() {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4); l.rate = .r1_4; l.useRiff = true; l.riffOn = true
        l.riffLength = 12; l.riffRotate = 10; l.restartMelodyPasses = [2]
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, riffColumns: 16)!
        XCTAssertEqual(cfg.columns, 16); XCTAssertEqual(cfg.length, 12); XCTAssertEqual(cfg.rotate, 10)
        let st = restartTileState(.melody, cfg: cfg, beat: 0.1, running: true)
        XCTAssertEqual(st.count, 12, "one cell per riff column of the window — 12, not the MONO grid's 8")
        XCTAssertEqual(st.cell(forColumn: 10), 0, "the window starts at column 10 (SHIFT)"); XCTAssertEqual(st.cell(forColumn: 15), 5); XCTAssertEqual(st.cell(forColumn: 0), 6); XCTAssertEqual(st.cell(forColumn: 5), 11)
        XCTAssertNil(st.cell(forColumn: 6), "columns outside the window have no cell")
        let mono = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        XCTAssertEqual(restartTileState(.melody, cfg: mono, beat: 0.1, running: true).count, 8, "the same lane in MONO: its 8-column window")
    }
}

/// A tiny deterministic generator for the table tests.
struct PolyRiffRNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed }
    mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
}
