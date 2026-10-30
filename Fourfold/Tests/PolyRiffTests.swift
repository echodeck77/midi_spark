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

    // MARK: REVERSE (2026-10-30) — the snapshot's end tables and which end(s) of a note a hit meets

    func testTheSnapshotHoldsEndsAndTheirLengthsToo() {
        // rank 3: columns 2…5 and 6…7 (back to back, so neither is clipped); rank 1: column 5 only
        let riff = EuclideousPolyRiff(notes: [EuclideousPolyNote(col: 2, rank: 3, len: 4), EuclideousPolyNote(col: 6, rank: 3, len: 2), EuclideousPolyNote(col: 5, rank: 1, len: 1)])
        XCTAssertEqual(riff.normalized.notes.count, 3); XCTAssertEqual(riff.normalized.notes.map { $0.len }.sorted(), [1, 2, 4], "the fixture survives normalisation")
        let s = PolyRiffSnap(riff, on: true)
        XCTAssertEqual(s.triggerMask(2, .starts), 0b100); XCTAssertEqual(s.triggerMask(5, .starts), 0b001); XCTAssertEqual(s.triggerMask(6, .starts), 0b100)
        XCTAssertEqual(s.triggerMask(5, .ends), 0b101, "rank 3 (columns 2…5) and rank 1 (column 5) both END on column 5")
        XCTAssertEqual(s.triggerMask(7, .ends), 0b100, "rank 3 (columns 6…7) ends on 7")
        XCTAssertEqual(s.triggerMask(2, .ends), 0)
        XCTAssertEqual(s.triggerMask(5, .both), 0b101, "both = starts ∪ ends"); XCTAssertEqual(s.triggerMask(2, .both), 0b100); XCTAssertEqual(s.triggerMask(6, .both), 0b100)
        XCTAssertEqual(s.triggerLength(col: 5, rank: 3, .ends), 4, "a backward hit on column 5 strikes the long note at its length")
        XCTAssertEqual(s.triggerLength(col: 7, rank: 3, .ends), 2)
        XCTAssertEqual(s.triggerLength(col: 6, rank: 3, .starts), 2, "…and a forward hit on 6 the note STARTING there")
        XCTAssertEqual(s.triggerLength(col: 5, rank: 3, .both), 4, "an ending note keeps its own length under .both"); XCTAssertEqual(s.triggerLength(col: 2, rank: 3, .both), 4)
        XCTAssertEqual(s.triggerLength(col: 5, rank: 1, .both), 1)
        XCTAssertEqual(s.triggerLength(col: 3, rank: 3, .both), 0, "a held-through column strikes nothing")
        XCTAssertEqual(s.topTriggerRank(5, .ends), 3); XCTAssertEqual(s.topTriggerRank(2, .ends), 0); XCTAssertEqual(s.topTriggerRank(2, .starts), 3); XCTAssertEqual(s.topAnyRank(7), 3); XCTAssertEqual(s.topAnyRank(3), 0)
    }
    /// The snapshot's tables against a brute-force read of the notes themselves, over 200 random riffs.
    func testTheSnapshotsTriggerReadsMatchABruteForceOverTheNotes() {
        var rng = PolyRiffRNG(0x7E57)
        for _ in 0..<200 {
            var notes: [EuclideousPolyNote] = []
            for _ in 0..<(Int(rng.next() % 14) + 1) { notes.append(EuclideousPolyNote(col: Int(rng.next() % 16), rank: Int(rng.next() % 8) + 1, len: Int(rng.next() % 16) + 1)) }
            let riff = EuclideousPolyRiff(notes: notes)
            let snap = PolyRiffSnap(riff, on: true)
            for mode in [EuclideousPolyTrigger.starts, .ends, .both] {
                for col in 0..<16 {
                    let expected = riff.normalized.notes.filter { n in
                        let startsHere = n.col == col, endsHere = n.col + n.len - 1 == col
                        switch mode { case .starts: return startsHere; case .ends: return endsHere; case .both: return startsHere || endsHere }
                    }.sorted { $0.rank < $1.rank }
                    let got = snap.triggerNotes(col, mode)
                    XCTAssertEqual(got.map { $0.rank }, expected.map { $0.rank }, "col \(col) \(mode)")
                    XCTAssertEqual(got.map { $0.len }, expected.map { $0.len }, "col \(col) \(mode)")
                    XCTAssertEqual(snap.triggerRanks(col, mode), expected.map { $0.rank }.sorted(by: >))
                    XCTAssertEqual(snap.topTriggerRank(col, mode), expected.map { $0.rank }.max() ?? 0)
                }
            }
        }
    }
    /// The one decision of which end(s) a hit meets: FWD starts, REV ends, and PENDULUM / PING-PONG per hit from the positions either side of it.
    func testTheTriggerModeFollowsTheWalk() {
        func modes(_ d: RiffDir, len: Int = 4, stride: Int = 1, every: Int = 1, hits: Int) -> [EuclideousPolyTrigger] {
            (0..<hits).map { euclideousPolyTrigger(riffDir: d, length: len, stride: stride, every: every, ordinal: Int64($0)) }
        }
        XCTAssertEqual(modes(.forward, hits: 8), [EuclideousPolyTrigger](repeating: .starts, count: 8))
        XCTAssertEqual(modes(.reverse, hits: 8), [EuclideousPolyTrigger](repeating: .ends, count: 8))
        // PENDULUM 0 1 2 3 2 1 | 0 1 …: the interior of each leg meets one end, a turn (arrive one way, leave the other) both
        XCTAssertEqual(modes(.pendulum, hits: 7), [.both, .starts, .starts, .both, .ends, .ends, .both])
        // PING-PONG 0 1 2 3 3 2 1 0 | 0 1 …: each doubled end step is two visits — the first arrives (the leg it ends), the second leaves (the leg it starts)
        XCTAssertEqual(modes(.pingpong, hits: 9), [.starts, .starts, .starts, .starts, .ends, .ends, .ends, .ends, .starts])
        // ADV EVERY 2: the walk step is ordinal ÷ 2, so both hits of a step meet the same ends
        XCTAssertEqual(modes(.pendulum, every: 2, hits: 8), [.both, .both, .starts, .starts, .starts, .starts, .both, .both])
        // a walk that never moves (LEN 1) is a forward one; a stride that skips over the fold is still read from the positions
        XCTAssertEqual(modes(.pendulum, len: 1, hits: 3), [EuclideousPolyTrigger](repeating: .starts, count: 3))
        // LEN 8, STRIDE 3: the positions run 0 3 6 5 2 1 4 7 4 1 …, the fold is stepped over rather than landed on, and the modes still follow the positions
        XCTAssertEqual(modes(.pendulum, len: 8, stride: 3, hits: 8), [.both, .starts, .both, .ends, .ends, .both, .starts, .both])
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

    // MARK: adversarial review (2026-10-29) — fixes

    /// The lane lock compared LEN and SHIFT only through MONO's 8-column resolvers, so a lane locked with LEN 12 / SHIFT 11 in POLY never read as deviated when either changed (LEN 9…16 and SHIFT 8…15 resolve to 8 and mod 8).
    func testTheLaneLockSeesPolyLengthAndShift() {
        var l = EuclidLine(target: 0, pulses: 4, steps: 8); l.riffLength = 12; l.riffRotate = 11
        let locked = LaneLockFields(line: l)
        XCTAssertFalse(euclideousLockDeviated(line: l, from: locked))
        for (len, shift) in [(14, 11), (9, 11), (16, 11), (12, 3), (12, 12), (12, 0)] {
            var m = l; m.riffLength = len; m.riffRotate = shift
            XCTAssertTrue(euclideousLockDeviated(line: m, from: locked), "LEN \(len) SHIFT \(shift) differs from LEN 12 SHIFT 11 in POLY")
        }
        var unset = l; unset.riffLength = nil
        XCTAssertTrue(euclideousLockDeviated(line: unset, from: locked), "LEN unset (16 in POLY) is not 12")
        // the MONO fields still count exactly as before
        var m = l; m.riffStride = 3; XCTAssertTrue(euclideousLockDeviated(line: m, from: locked))
    }
    func testAWrongShapedPolyRiffReadsAsEmptyAndNeverFailsTheDocument() throws {
        for bad in ["[]", "5", "\"x\"", "null", "{\"notes\":3}", "{\"notes\":{}}"] {
            let r = try JSONDecoder().decode(EuclideousPolyRiff.self, from: Data(bad.utf8))
            XCTAssertTrue(r.isEmpty, bad)
        }
        var st = PluginState.makeInit(); st.polyRiff = EuclideousPolyRiff(notes: [note(1, 2, 3)])
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(st)) as? [String: Any])
        obj["polyRiff"] = [Any]()                      // an array where the object belongs
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(back.polyRiffResolved.isEmpty, "an empty POLY riff — the document survives")
    }

    /// The WALK strip's readout (never-play columns) walked only 8 columns, so in POLY it was withheld ("CYCLE TOO LONG TO COUNT"). With `columns: 16` a stride-2 walk over 16 columns never reads the odd ones.
    func testTheRiffReadoutWalksSixteenColumns() {
        let buf = [Bool](repeating: true, count: 4)
        func readout(stride: Int, length: Int, columns: Int) -> EuclideousRiffReadout? {
            euclideousRiffReadout(buf: buf, n: 4, dir: .fwd, cycleLen: 4, sub: 1, chains: EuclideousLaneRestartChains(rhythm: .free, melody: .free, barBeats: 4, lapBeats: 4), legacySpanBeats: 0, advanceStep: false, riffDir: .forward, stride: stride, length: length, shift: 0, every: 1, seed: 0, columns: columns)
        }
        let r = readout(stride: 2, length: 16, columns: 16)
        XCTAssertEqual(r?.neverPlay, Set([1, 3, 5, 7, 9, 11, 13, 15]))
        XCTAssertEqual(readout(stride: 1, length: 16, columns: 16)?.neverPlay, [], "stride 1 reaches every column")
        XCTAssertEqual(readout(stride: 2, length: 8, columns: 8)?.neverPlay, Set([1, 3, 5, 7]), "MONO is as it was")
        let cache = EuclideousRiffReadoutCache()
        var l = EuclidLine(target: 0, pulses: 4, steps: 4); l.rate = .r1_4; l.riffLength = 16; l.riffStride = 2; l.restartRhythmBars = []; l.restartMelodyPasses = []   // FREE chains, stored (so the walk config carries real chains)
        let poly = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, riffColumns: 16)!
        let mono = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        XCTAssertEqual(cache.readout(lane: 0, cfg: poly)?.neverPlay.count, 8, "a POLY lane's readout is over 16 columns")
        XCTAssertNotEqual(cache.readout(lane: 0, cfg: mono)?.neverPlay.count, 8, "…and the cache keys on the grid width, so the same lane in MONO is recomputed over 8")
    }

    // MARK: adversarial review (2026-10-29) — the mirrors that still read ONE riff pitch / EIGHT columns

    /// A POLY chord strikes several riff pitches on one hit; the pulse feed read only the first as the riff's and counted the rest as NOTES-layer strikes (lighting the key row, the notes glow and the hocket marks on a riff-only chord).
    func testThePulseFeedCountsEveryLeadingRiffPitchOfAChordAsTheRiffs() {
        func strike(riffCount: Int, hasRiff: Bool = true) -> EuclideousPulseStrike? {
            let ev = Router.EuclideousNoteViewEventSnapshot(onsetBeat: 0, durationBeat: 1, kind: 0, notes: [48, 52, 55, 60], column: 2, rank: 1, hasRiffNote: hasRiff, riffNoteCount: riffCount, vels: [80, 81, 82, 99], dests: [0, 0, 0, 0])
            let feed = EuclideousPulseFeed(); feed.ingest(lane: 0, events: [ev], anchorBeat: 0, anchorAt: Date(), tempo: 120)
            return feed.strikes(lane: 0).first
        }
        XCTAssertEqual(strike(riffCount: 3)?.notesVel, 99, "three riff pitches, then ONE notes-layer pitch (velocity 99)"); XCTAssertEqual(strike(riffCount: 3)?.riffVel, 80)
        XCTAssertEqual(strike(riffCount: 4)?.notesVel, 0, "a riff-only chord: the notes layer did not strike")
        XCTAssertEqual(strike(riffCount: -1)?.notesVel, 99, "an event that does not report a count reads as MONO's one riff pitch: the later pitches are the notes layer's… (-1 = 1)")
        XCTAssertEqual(strike(riffCount: -1)?.riffVel, 80)
        XCTAssertEqual(Router.EuclideousNoteViewEventSnapshot(onsetBeat: 0, durationBeat: 1, kind: 0, notes: [], hasRiffNote: true).riffNotes, 1)
        XCTAssertEqual(Router.EuclideousNoteViewEventSnapshot(onsetBeat: 0, durationBeat: 1, kind: 0, notes: []).riffNotes, 0)
    }
    func testTheMirrorsCarryTheGridWidthAndTheShiftedWindow() {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4); l.rate = .r1_4; l.riffOn = true; l.riffLength = 4; l.riffRotate = 12
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, riffColumns: 16)!
        XCTAssertEqual(euclideousNotesWalk(from: cfg).columns, 16, "the strip's notes count k walks the grid the Router walks")
        // notes only on columns 12…15 — the window LEN 4 from SHIFT 12 — used to be taken for an empty riff (the check ran over columns 0…3)
        var ranks = [Int](repeating: 0, count: 16); for c in 12..<16 { ranks[c] = 3 }
        let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: 1, secondsPerBeat: 0.5, polledStep: 12, running: false)
        XCTAssertNotNil(plan); XCTAssertEqual(plan?.seatStep, 12); XCTAssertEqual(plan?.seatRank, 3)
        XCTAssertEqual(euclideousRiffWindowColumns(length: 6, shift: 14, columns: 16), [14, 15, 0, 1, 2, 3])
        XCTAssertEqual(euclideousRiffWindowColumns(length: 6, shift: 14), [6, 7, 0, 1, 2, 3], "MONO wraps at 8")
        let off = euclideousRailSpec(lane: 0, riffOn: false, running: false, muted: false, played: [], current: nil, trail: [], heading: .still, flare: 0, columns: 16)
        XCTAssertEqual(off.segments.count, 16)
        let on = euclideousRailSpec(lane: 0, riffOn: true, running: true, muted: false, played: [12, 13], current: 13, trail: [12], heading: .right, flare: 0, columns: 16)
        XCTAssertEqual(on.segments[13].look, .current(.right)); XCTAssertEqual(on.segments[12].look, .trail(0)); XCTAssertEqual(on.segments.count, 16)
        XCTAssertEqual(euclideousRailSpec(lane: 0, riffOn: true, running: true, muted: false, played: [], current: 13, trail: [], heading: .right, flare: 0).segments.count, 8, "MONO's rail is eight")
    }
    func testACellStrikeOnAColumnPastEightLightsItsCell() {
        let order = euclideousRiffCycleOrder(dir: .forward, length: 16, stride: 1, shift: 0, columns: 16)
        var s = EuclideousPulseStrike(onsetBeat: 0, onsetAt: 10, riffVel: 100, notesVel: 0); s.cellColumn = 12
        let bank = euclideousRestartCellStrikes([s], columnCells: order.columnCells, now: 10.05)
        XCTAssertGreaterThan(bank.mix(cell: 12, scale: 1, reduceMotion: false), 0.5); XCTAssertEqual(bank.mix(cell: 4, scale: 1, reduceMotion: false), 0)
    }
    /// Random mode rolled over an 8-column grid: a LEN-12 POLY lane with notes only on columns 8…11 had "NOTHING TO CHANGE", TWEAK's SHIFT folded to 8, and THROW could pick TIE / REPEAT (dead in POLY).
    func testRandomRiffRollsOverTheGridTheLaneWalks() {
        var written = [Int](repeating: 0, count: 16); for c in 8..<12 { written[c] = 4 }
        let cov8 = euclideousRandomRiffCoverage(dir: .forward, every: 1, stride: 1, shift: 0, length: 12, hits: 4, writtenRanks: written)
        let cov16 = euclideousRandomRiffCoverage(dir: .forward, every: 1, stride: 1, shift: 0, length: 12, hits: 4, writtenRanks: written, columns: 16)
        XCTAssertTrue(cov8.reached.allSatisfy { $0 < 8 }); XCTAssertEqual(cov16.reached, Set(0..<12), "LEN 12 from SHIFT 0 reaches columns 0…11")
        XCTAssertTrue(cov16.soundingReached)
        var thrown = 0
        for seed in 1...40 {
            var rng = EuclideousRandomRNG(seed: UInt64(seed))
            let cur = (dir: RiffDir.forward, advanceStep: false, advanceEvery: 1, invert: false, onRest: EuclidRiffOnRest.tie, stride: 1, shift: 0, length: 12, hits: 4, role: EuclideousRandomRole.medium)
            if let r = euclideousRandomThrowRiff(current: cur, writtenRanks: written, others: [], columns: 16, onRestFixed: true, rng: &rng) { thrown += 1; XCTAssertEqual(r.onRest, .tie, "ON REST is not rolled in POLY — the stored choice is kept") }
            var rng2 = EuclideousRandomRNG(seed: UInt64(seed))
            let cur2 = (dir: RiffDir.forward, advanceStep: false, advanceEvery: 1, invert: false, onRest: EuclidRiffOnRest.tie, stride: 1, shift: 0, length: 12, hits: 4)
            if let r = euclideousRandomTweakRiff(current: cur2, writtenRanks: written, columns: 16, onRestFixed: true, rng: &rng2) { XCTAssertEqual(r.onRest, .tie); XCTAssertTrue(r.shift >= 0 && r.shift < 12) }
        }
        XCTAssertGreaterThan(thrown, 10, "a POLY lane with notes past column 8 can be thrown")
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
