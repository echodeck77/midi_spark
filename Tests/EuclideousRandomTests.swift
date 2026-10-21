//  EuclideousRandomTests.swift
//  RANDOM MODE ferry §13 tests 1-8 (the pure throw/tweak/role functions) plus a unit test for the §7.2
//  undo-sequence builder. Tests 9-11 (landing on a bar line, the hold, stopped-page) and 13 (writes) need
//  the real Router/EuclidLine writers and live in RouterTests, added with the apply-at-a-beat ferry step.

import XCTest

final class EuclideousRandomTests: XCTestCase {

    // MARK: §13 fixture lanes (verbatim from the ferry text)

    private struct Fixture { var steps: Int; var hits: Int; var offset: Int; var stepBeats: Double }
    // 1) 8 steps of 1/8, HITS 2, OFFSET 4, riff on — ρ = 2/(8×0.5) = 0.5 (sparse)
    private let lane1 = Fixture(steps: 8, hits: 2, offset: 4, stepBeats: 0.5)
    // 2) 16 of 1/16, HITS 3, riff off, notes on — ρ = 3/(16×0.25) = 0.75 (medium)
    private let lane2 = Fixture(steps: 16, hits: 3, offset: 0, stepBeats: 0.25)
    // 3) 16 of 1/16, HITS 7, riff on, ADV STEP — ρ = 7/(16×0.25) = 1.75 (dense)
    private let lane3 = Fixture(steps: 16, hits: 7, offset: 0, stepBeats: 0.25)
    // 4) 8 of 1/2, HITS 3, riff on — ρ = 3/(8×2) = 0.1875 (sparse)
    private let lane4 = Fixture(steps: 8, hits: 3, offset: 0, stepBeats: 2.0)
    // riff 4 1 1 1 1 1 1 1 (rank 4 then rank 1 seven times), LEN 8
    private let defaultRiff = [4, 1, 1, 1, 1, 1, 1, 1]

    private func other(_ f: Fixture, participates: Bool = true, riffOn: Bool = false) -> EuclideousRandomOtherLane {
        EuclideousRandomOtherLane(steps: f.steps, hits: f.hits, offset: f.offset, stepBeats: f.stepBeats,
                                   participates: participates, riffOn: riffOn, riffDir: .forward,
                                   riffAdvanceStep: false, riffAdvanceEvery: 1, riffStride: 1, riffShift: 0)
    }

    // MARK: Test 1 — roles

    func testRoles() {
        XCTAssertEqual(euclideousRandomRole(hits: lane1.hits, steps: lane1.steps, stepBeats: lane1.stepBeats), .sparse)
        XCTAssertEqual(euclideousRandomRole(hits: lane2.hits, steps: lane2.steps, stepBeats: lane2.stepBeats), .medium)
        XCTAssertEqual(euclideousRandomRole(hits: lane3.hits, steps: lane3.steps, stepBeats: lane3.stepBeats), .dense)
        XCTAssertEqual(euclideousRandomRole(hits: lane4.hits, steps: lane4.steps, stepBeats: lane4.stepBeats), .sparse)
    }

    // MARK: Test 2 — RHYTHM throw: bounds, never a copy, never a twin, pyramid, odd-steps

    func testRhythmThrowBoundsAndNoCopy() {
        let fixtures = [lane1, lane2, lane3, lane4]
        for seed in UInt64(1)...1000 {
            for i in 0..<4 {
                var rng = EuclideousRandomRNG(seed: seed &* 4 &+ UInt64(i))
                let current = fixtures[i]
                let others = (0..<4).filter { $0 != i }.map { other(fixtures[$0]) }
                let r = euclideousRandomThrowRhythm(current: (current.steps, current.hits, current.offset, current.stepBeats),
                                                     others: others, rng: &rng)
                XCTAssertTrue(r.hits >= 1 && r.hits <= r.steps - 1, "hits \(r.hits) steps \(r.steps)")
                XCTAssertTrue(r.steps >= 2 && r.steps <= 16)
                let isCopy = r.steps == current.steps && r.hits == current.hits && r.offset == current.offset
                XCTAssertFalse(isCopy, "seed \(seed) lane \(i): threw an exact copy")
                for o in others {
                    let isTwin = o.steps == r.steps && o.hits == r.hits && o.offset == r.offset && o.stepBeats == current.stepBeats
                    XCTAssertFalse(isTwin, "seed \(seed) lane \(i): threw another lane's twin")
                }
            }
        }
    }

    func testRhythmThrowPyramidAndOddSteps() {
        let fixtures = [lane1, lane2, lane3, lane4]
        for seed in UInt64(1)...500 {
            var states = fixtures
            for i in 0..<4 {
                var rng = EuclideousRandomRNG(seed: seed &* 10 &+ UInt64(i))
                let others = (0..<4).filter { $0 != i }.map { other(states[$0]) }
                let r = euclideousRandomThrowRhythm(current: (states[i].steps, states[i].hits, states[i].offset, states[i].stepBeats),
                                                     others: others, rng: &rng)
                states[i] = Fixture(steps: r.steps, hits: r.hits, offset: r.offset, stepBeats: states[i].stepBeats)
                let roles = states.map { euclideousRandomRole(hits: $0.hits, steps: $0.steps, stepBeats: $0.stepBeats) }
                XCTAssertTrue(euclideousRandomPyramidHolds(roles), "seed \(seed) after lane \(i): pyramid broke")
                XCTAssertTrue(euclideousRandomOddStepsHolds(states.map { $0.steps }), "seed \(seed) after lane \(i): >1 odd STEPS")
            }
        }
    }

    // MARK: Test 3 — RHYTHM tweak: one field, HITS keeps overlap, OFFSET is a rotation, pyramid holds

    func testRhythmTweakChain() {
        let fixtures = [lane1, lane2, lane3, lane4]
        for seed in UInt64(1)...800 {
            var rng = EuclideousRandomRNG(seed: seed)
            var state = fixtures[Int(seed % 4)]
            let others = (0..<4).filter { $0 != Int(seed % 4) }.map { other(fixtures[$0]) }
            for _ in 0..<30 {
                let before = state
                let beforePattern = euclideousRandomPattern(hits: before.hits, steps: before.steps, offset: before.offset, tilt: 0)
                let r = euclideousRandomTweakRhythm(current: (state.steps, state.hits, state.offset, state.stepBeats, 0), others: others, rng: &rng)
                let hitsChanged = r.hits != before.hits
                let stepsChanged = r.steps != before.steps
                XCTAssertFalse(hitsChanged && stepsChanged, "seed \(seed): both HITS and STEPS changed")
                if hitsChanged {
                    let afterPattern = euclideousRandomPattern(hits: r.hits, steps: r.steps, offset: r.offset, tilt: 0)
                    let shared = (0..<min(beforePattern.count, afterPattern.count)).filter { beforePattern[$0] && afterPattern[$0] }.count
                    XCTAssertGreaterThanOrEqual(shared, min(before.hits, r.hits) - 1, "seed \(seed): HITS move lost too many shared steps")
                }
                if !hitsChanged && !stepsChanged, r.offset != before.offset {
                    let n = before.steps
                    let delta = ((r.offset - before.offset) % n + n) % n
                    XCTAssertTrue(delta == 1 || delta == n - 1, "seed \(seed): OFFSET moved by more than one step")
                }
                state = Fixture(steps: r.steps, hits: r.hits, offset: r.offset, stepBeats: before.stepBeats)
            }
        }
    }

    // MARK: Test 4 — RIFF throw: coverage, LEN/TRANS unchanged, direction diversity

    private let riffs: [[Int]] = [
        [4, 1, 1, 1, 1, 1, 1, 1],
        [1, 3, 0, 4, 5, 0, 3, 2],
        [5, 0, 6, 0, 4, 0, 3, 4],
    ]

    func testRiffThrowCoverage() {
        for riff in riffs {
            for seed in UInt64(1)...1000 {
                for i in 0..<4 {
                    var rng = EuclideousRandomRNG(seed: seed &* 4 &+ UInt64(i) &+ 1)
                    let current: (dir: RiffDir, advanceStep: Bool, advanceEvery: Int, invert: Bool, onRest: EuclidRiffOnRest,
                                  stride: Int, shift: Int, length: Int, hits: Int, role: EuclideousRandomRole) =
                        (.forward, false, 1, false, .skip, 1, 0, 8, 3, .medium)
                    guard let r = euclideousRandomThrowRiff(current: current, writtenRanks: riff, others: [], rng: &rng) else { continue }
                    let (reached, sounding) = euclideousRandomRiffCoverage(dir: r.dir, every: r.advanceEvery, stride: r.stride,
                                                                            shift: r.shift, length: 8, hits: 3, writtenRanks: riff)
                    XCTAssertGreaterThanOrEqual(reached.count, 4, "seed \(seed) lane \(i): coverage under half")
                    XCTAssertLessThanOrEqual(8 - reached.count, 2, "seed \(seed) lane \(i): more than 2 columns unreached")
                    XCTAssertTrue(sounding, "seed \(seed) lane \(i): no reached column sounds")
                }
            }
        }
    }

    func testRiffThrowDirectionDiversity() {
        var differentCount = 0
        for seed in UInt64(1)...500 {
            var rng = EuclideousRandomRNG(seed: seed)
            let fwdOthers = [EuclideousRandomOtherLane(steps: 8, hits: 3, offset: 0, stepBeats: 0.5, participates: true,
                                                        riffOn: true, riffDir: .forward, riffAdvanceStep: false,
                                                        riffAdvanceEvery: 1, riffStride: 1, riffShift: 0)]
            let current: (dir: RiffDir, advanceStep: Bool, advanceEvery: Int, invert: Bool, onRest: EuclidRiffOnRest,
                          stride: Int, shift: Int, length: Int, hits: Int, role: EuclideousRandomRole) =
                (.forward, false, 1, false, .skip, 1, 0, 8, 3, .medium)
            if let r = euclideousRandomThrowRiff(current: current, writtenRanks: defaultRiff, others: fwdOthers, rng: &rng), r.dir != .forward {
                differentCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(differentCount, 350, "expected >=70% of 500 throws to pick a non-FWD direction next to an FWD riff lane")
    }

    // MARK: Test 5 — RIFF tweak: one field, coverage holds, INV/LEN/TRANS unchanged

    func testRiffTweakChain() {
        for seed in UInt64(1)...3000 {
            var rng = EuclideousRandomRNG(seed: seed)
            let current: (dir: RiffDir, advanceStep: Bool, advanceEvery: Int, invert: Bool, onRest: EuclidRiffOnRest,
                          stride: Int, shift: Int, length: Int, hits: Int) = (.forward, false, 1, false, .skip, 1, 0, 8, 3)
            guard let r = euclideousRandomTweakRiff(current: current, writtenRanks: defaultRiff, rng: &rng) else { continue }
            XCTAssertEqual(r.invert, current.invert, "seed \(seed): INV changed")
            let changed = [r.dir != current.dir, r.advanceEvery != current.advanceEvery, r.stride != current.stride,
                            r.shift != current.shift, r.advanceStep != current.advanceStep, r.onRest != current.onRest]
            XCTAssertEqual(changed.filter { $0 }.count, 1, "seed \(seed): expected exactly one field to change, got \(changed)")
            let (reached, sounding) = euclideousRandomRiffCoverage(dir: r.dir, every: r.advanceEvery, stride: r.stride,
                                                                    shift: r.shift, length: 8, hits: 3, writtenRanks: defaultRiff)
            XCTAssertGreaterThanOrEqual(reached.count, 4)
            XCTAssertTrue(sounding)
        }
    }

    // MARK: Test 6 — NOTES throw

    func testNotesThrow() {
        for (riffIdx, riff) in riffs.enumerated() {
            for seed in UInt64(1)...1000 {
                for i in 0..<4 {
                    let received = (seed % 5 == 0)
                    var rng = EuclideousRandomRNG(seed: seed &* 4 &+ UInt64(i) &+ UInt64(riffIdx) &* 4000)
                    let role: EuclideousRandomRole = [.sparse, .medium, .dense][i % 3]
                    let current = (litOrder: EuclideousLitOrder(), when: UInt8(0b11), chance: 100, playAs: EuclidNotesPlayAs.chord)
                    guard let r = euclideousRandomThrowNotes(role: role, current: current, riffOn: true, writtenRanks: riff, length: 8,
                                                              receivedOnly: received, receivedCount: received ? 3 : 0, rng: &rng) else { continue }
                    XCTAssertTrue(r.litOrder.count >= 2 && r.litOrder.count <= 4, "seed \(seed): lit count \(r.litOrder.count) out of 2-4")
                    var seen = Set<Int>()
                    for k in 0..<r.litOrder.count { XCTAssertTrue(seen.insert(r.litOrder[k]).inserted, "seed \(seed): repeated position") }
                    if let mostWritten = euclideousRandomRiffMostWrittenRank(writtenRanks: riff, length: 8) {
                        XCTAssertFalse(r.litOrder.contains(mostWritten - 1), "seed \(seed): lit the riff's most-written rank")
                    }
                    if received {
                        for k in 0..<r.litOrder.count {
                            let p = r.litOrder[k]
                            if p < 8 { XCTAssertLessThanOrEqual(p + 1, 3, "seed \(seed): lit an octave copy under RECEIVED") }
                        }
                    }
                    let hasRest = riff.prefix(8).contains { $0 < 1 }
                    if !hasRest { XCTAssertNotEqual(r.when, 0b10, "seed \(seed): WHEN=RESTS with no rest in the riff") }
                    if r.playAs == .split { XCTAssertGreaterThanOrEqual(r.litOrder.count, 3) }
                }
            }
        }
    }

    // MARK: Test 7 — NOTES tweak

    func testNotesTweak() {
        for seed in UInt64(1)...3000 {
            var rng = EuclideousRandomRNG(seed: seed)
            var order = EuclideousLitOrder()
            order.append(0); order.append(2); order.append(4)
            let current = (litOrder: order, when: UInt8(0b11), chance: 75, playAs: EuclidNotesPlayAs.roll)
            let allowed = [0, 1, 2, 3, 4, 5, 8]
            guard let r = euclideousRandomTweakNotes(role: .medium, current: current, allowed: allowed, riffOn: true,
                                                       writtenRanks: defaultRiff, length: 8, rng: &rng) else { continue }
            let litChanged = r.litOrder.array != current.litOrder.array
            let changed = [litChanged, r.playAs != current.playAs, r.chance != current.chance, r.when != current.when]
            XCTAssertLessThanOrEqual(changed.filter { $0 }.count, 2, "seed \(seed): more than one dimension moved (order move can touch only litOrder)")
            XCTAssertTrue(r.chance >= 25 && r.chance <= 100, "seed \(seed): chance \(r.chance) out of range")
        }
    }

    // MARK: Test 8 — determinism

    func testDeterminism() {
        var rngA = EuclideousRandomRNG(seed: 42)
        var rngB = EuclideousRandomRNG(seed: 42)
        let others = [other(lane2), other(lane3), other(lane4)]
        let a = euclideousRandomThrowRhythm(current: (lane1.steps, lane1.hits, lane1.offset, lane1.stepBeats), others: others, rng: &rngA)
        let b = euclideousRandomThrowRhythm(current: (lane1.steps, lane1.hits, lane1.offset, lane1.stepBeats), others: others, rng: &rngB)
        XCTAssertEqual(a, b)
    }

    // MARK: §7.2 undo-sequence builder (pure unit test — the full finishing/undo integration is RouterTests)

    func testUndoSequenceBuilderOrdersOneTabPerStep() {
        var lane0 = EuclidLine()
        lane0.steps = 16; lane0.pulses = 4; lane0.rotate = 2
        var lane1Original = EuclidLine()
        lane1Original.riffDir = .forward
        var settled = EuclideousUndoSnapshot(lines: [lane0, EuclidLine(), EuclidLine(), EuclidLine()],
                                              riff: EuclideousRiff(), resetSpanBars: 0, keyRoot: 0, keyType: .major,
                                              chords: MachineParams(), noteSource: .midi, riffs: [], activeRiff: 0,
                                              lanesSeq: EuclideousLanesSeq(), riffsSeq: EuclideousRiffsSeq())
        settled.lines[1].riffDir = .reverse   // "kept" new state for lane 1's RIFF tab

        let entries = [
            EuclideousRandomUndoEntry(lane: 0, tab: .rhythm, original: EuclidLine()),   // lane 0's original had steps 8/pulses 1/rotate 0 (defaults)
            EuclideousRandomUndoEntry(lane: 1, tab: .riff, original: lane1Original),
        ]
        let seq = euclideousRandomUndoSequence(settled: settled, entries: entries)
        XCTAssertEqual(seq.count, 2)
        // S0: BOTH tabs reverted.
        XCTAssertEqual(seq[0].lines[0].steps, 8)
        XCTAssertEqual(seq[0].lines[1].riffDir, .forward)
        // S1: the first entry (lane 0 rhythm) re-applied, lane 1's riff still reverted.
        XCTAssertEqual(seq[1].lines[0].steps, 16)
        XCTAssertEqual(seq[1].lines[0].pulses, 4)
        XCTAssertEqual(seq[1].lines[1].riffDir, .forward)
    }

    func testUndoSequenceBuilderEmptyForNoEntries() {
        let settled = EuclideousUndoSnapshot(lines: [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()],
                                              riff: EuclideousRiff(), resetSpanBars: 0, keyRoot: 0, keyType: .major,
                                              chords: MachineParams(), noteSource: .midi, riffs: [], activeRiff: 0,
                                              lanesSeq: EuclideousLanesSeq(), riffsSeq: EuclideousRiffsSeq())
        XCTAssertEqual(euclideousRandomUndoSequence(settled: settled, entries: []).count, 0)
    }

    // MARK: Landing-beat math

    func testNextBarLineRespectsMargin() {
        // 4 beats/bar, currently at beat 7.5, margin 1 beat -> next bar line at or after 8.5 is 8... wait
        // bar lines are multiples of 4: 8 is < 8.5, so the answer must be 12.
        let next = euclideousRandomNextBarLine(afterBeat: 7.5, barBeats: 4, marginBeats: 1)
        XCTAssertEqual(next, 12, accuracy: 1e-9)
    }

    func testShouldApplyIsExactBoundary() {
        XCTAssertFalse(euclideousRandomShouldApply(hostBeat: 7.999, landingBeat: 8))
        XCTAssertTrue(euclideousRandomShouldApply(hostBeat: 8, landingBeat: 8))
    }
}
