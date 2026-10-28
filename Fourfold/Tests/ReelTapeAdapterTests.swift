//  ReelTapeAdapterTests.swift — REEL PHASE 1c: the old pass browser reading the session tape (Fourfold/Engine/ReelTapeAdapter.swift), and the hand-off that replays one of its passes.
//  The comparison against the old ring (same Router, same passes) is in RouterTests (`testTheTapeShowsTheBrowserWhatTheDeckDid`); these use a tape built by hand.

import XCTest

private final class Heard: MIDIEmitter {
    struct E: Equatable { var sample: Int64; var cable: UInt8; var b0: UInt8; var b1: UInt8; var b2: UInt8 }
    var events: [E] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(E(sample: sampleTime, cable: cable, b0: b0, b1: b1, b2: b2)) }
}

final class ReelTapeAdapterTests: XCTestCase {
    private let bps = 120.0 / 60.0 / 48_000.0          // 120 BPM at 48 kHz = 24 000 samples a beat

    /// A tape of `passes` whole 4-beat passes, then a start of the next. Each pass has: a note on A at beat 0 (C4 for 1 beat), one at beat 2 (pitch = 60 + pass), a note on B at beat 3, and — in pass 1 only — a CC.
    private func tape(passes: Int, bpm: Double = 120, startBeat: Double = 0) -> SessionTape {
        let t = SessionTape(chunkEvents: 256, poolSize: 64), rec = TapeRecorder(writer: t.writer)
        var beat = startBeat
        let wb = 512 * bps
        func window() { rec.beginWindow(playing: true, beatPos: beat, windowBeats: wb, tempo: bpm, cycleBeats: 4, sampleStart: Int64((beat / bps).rounded()), beatsPerSample: bps) }
        func put(_ b: Double, _ cable: UInt8, _ b0: UInt8, _ k: UInt8, _ v: UInt8) { rec.record(sampleTime: Int64((b / bps).rounded()), cable: cable, b0, k, v, lane: -1) }
        var scheduled: [(beat: Double, cable: UInt8, b0: UInt8, k: UInt8, v: UInt8)] = []
        for p in 0..<passes + 1 {
            let o = Double(p) * 4
            scheduled += [(o, 1, 0x90, 60, 100), (o + 1, 1, 0x80, 60, 0), (o + 2, 1, 0x90, UInt8(60 + p), 80), (o + 2.5, 1, 0x80, UInt8(60 + p), 0),
                          (o + 3, 2, 0x90, 48, 90), (o + 3.75, 2, 0x80, 48, 0)]
            if p == 1 { scheduled.append((o + 1.5, 0, 0xB0, 74, 99)) }
        }
        scheduled.sort { $0.beat < $1.beat }
        var next = 0
        while beat < Double(passes) * 4 + 0.5 {
            window()
            while next < scheduled.count, scheduled[next].beat < beat + wb { let e = scheduled[next]; if e.beat >= beat { put(e.beat, e.cable, e.b0, e.k, e.v) }; next += 1 }
            beat += wb
        }
        return t
    }

    func testTheBrowserListsEveryPassPlayedWhole() {
        let t = tape(passes: 5)
        XCTAssertEqual(t.filedPasses().count, 5)
        XCTAssertEqual(t.reelPassCycleBeats(0), 4)
        XCTAssertNil(t.reelPassCycleBeats(5), "the pass still being played is not listed")
        XCTAssertNil(t.reelPassCycleBeats(-1))
    }
    func testAPartialFirstPassIsNotListed() {
        let t = tape(passes: 3, startBeat: 2)                                     // the run began half way through a pass
        XCTAssertEqual(t.filedPasses().count, 2)
    }
    func testPassEventsArePassRelativeAndInTimeOrder() {
        let t = tape(passes: 3)
        let e = t.reelPassEvents(1)
        XCTAssertEqual(e.map { $0.beat }, e.map { $0.beat }.sorted())
        XCTAssertEqual(e.first?.beat ?? -1, 0, accuracy: 1e-9)
        XCTAssertTrue(e.allSatisfy { $0.beat >= 0 && $0.beat < 4 })
        XCTAssertEqual(e.filter { $0.b0 == 0xB0 }.count, 1, "the control change is part of the pass")
        XCTAssertEqual(e.first { $0.b0 == 0x90 && $0.cable == 1 && $0.b1 == 61 }.map { $0.beat }, 2, "the note struck at beat 2 of the second pass")
        XCTAssertEqual(t.reelPassEvents(7), [])
    }
    func testRollJoinsPassesAndHoldsAcrossTheBoundary() {
        let t = tape(passes: 4)
        let one = t.reelRangeRoll(from: 1, to: 1)
        XCTAssertEqual(one.totalBeats, 4)
        XCTAssertEqual(one.notes.count, 3, "two on A, one on B — the ALL cable is not drawn")
        let a = one.notes.first { $0.cable == 1 && $0.note == 61 }!
        XCTAssertEqual(a.start, 2, accuracy: 1e-6); XCTAssertEqual(a.end, 2.5, accuracy: 1e-6); XCTAssertEqual(a.vel, 80)
        let range = t.reelRangeRoll(from: 1, to: 3)
        XCTAssertEqual(range.totalBeats, 12)
        XCTAssertEqual(range.notes.count, 9)
        XCTAssertEqual(range.notes.map { $0.start }.max() ?? 0, 11, accuracy: 1e-6, "the last pass sits two passes after the first")
    }
    func testExportEventsAreLaidEndToEndPerOutput() {
        let t = tape(passes: 4)
        let a = t.reelExportEvents(from: 0, to: 2, cables: [1])
        XCTAssertEqual(a.totalBeats, 12)
        XCTAssertEqual(a.events.count, 12, "four messages on A per pass")
        XCTAssertEqual(a.events.map { $0.beat }, a.events.map { $0.beat }.sorted())
        XCTAssertEqual(t.reelExportEvents(from: 0, to: 2, cables: [2]).events.count, 6)
        XCTAssertEqual(t.reelExportEvents(from: 0, to: 0, cables: [3]).events.count, 0)
        let both = t.reelExportEvents(from: 0, to: 0, cables: [0, 1, 2, 3, 4]).events.count
        XCTAssertEqual(both, 6, "this tape was built with no ALL-cable notes, only the one control change in pass 1")
    }
    func testExportFilesCarryTheTempoThePassWasPlayedAt() {
        func tempoOf(_ d: Data) -> Double? {
            let b = [UInt8](d)
            for i in 0..<(b.count - 6) where b[i] == 0xFF && b[i + 1] == 0x51 && b[i + 2] == 0x03 {
                let us = Double(Int(b[i + 3]) << 16 | Int(b[i + 4]) << 8 | Int(b[i + 5])); return 60_000_000 / us
            }
            return nil
        }
        let t = tape(passes: 3, bpm: 97.3)
        let files = t.reelExportFiles(from: 0, to: 1, emitterMask: 0)
        XCTAssertEqual(files.map { $0.name }, ["Fourfold-All.mid"])
        XCTAssertEqual(tempoOf(files[0].data) ?? 0, 97.3, accuracy: 0.05)
        XCTAssertEqual(t.reelExportFiles(from: 0, to: 1, emitterMask: 0b0011).map { $0.name }, ["Fourfold-A.mid", "Fourfold-B.mid"])
        XCTAssertEqual(t.reelExportFiles(from: 0, to: 1, emitterMask: 0b0100).count, 0, "an output with nothing on it makes no file")
        XCTAssertEqual(SessionTape(chunkEvents: 16, poolSize: 2).reelExportFiles(from: 0, to: 0, emitterMask: 0).count, 0)
    }
    func testIdenticalPassesHashEqualAndDifferentOnesDoNot() {
        let t = tape(passes: 4)
        let s = t.reelSignatures()
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(Set(s).count, 4, "each pass strikes a different pitch at beat 2, so no two match")
        XCTAssertEqual(t.reelSignatures(), s, "stable, and cached")
        let u = tape(passes: 4)
        XCTAssertEqual(u.reelSignatures(), s, "the same music hashes the same on another tape")
    }

    // MARK: the hand-off

    func testAStagedPassBecomesTheLoopOnTheNextWindowAndIsPinned() {
        let deck = ReelDeck()
        let evs = [ReelDeck.Ev(beat: 0, cable: 1, b0: 0x90, b1: 60, b2: 100, machine: 0), ReelDeck.Ev(beat: 1, cable: 1, b0: 0x80, b1: 60, b2: 0, machine: 0), ReelDeck.Ev(beat: 3, cable: 1, b0: 0x90, b1: 64, b2: 90, machine: 0)]
        XCTAssertFalse(deck.adoptStagedLoop(), "nothing staged")
        XCTAssertTrue(deck.stageLoop(evs, cycle: 4, pass: 7))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertFalse(deck.adoptStagedLoop(), "adopted once")
        XCTAssertTrue(deck.hasLoop)
        XCTAssertEqual(deck.selectedPassNo, 7)
        XCTAssertEqual(deck.loopCycle, 4)
        XCTAssertEqual(deck.loopN, 4, "the three events and a synthetic note-off closing the note still open at the end")
        XCTAssertEqual(deck.loop[3].b0, 0x80); XCTAssertEqual(deck.loop[3].b1, 64); XCTAssertEqual(deck.loop[3].beat, 4)
    }
    func testTheLastStagedPassWins() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageLoop([ReelDeck.Ev(beat: 0, cable: 1, b0: 0x90, b1: 60, b2: 100, machine: 0)], cycle: 4, pass: 1))
        XCTAssertTrue(deck.stageLoop([ReelDeck.Ev(beat: 2, cable: 2, b0: 0x90, b1: 70, b2: 100, machine: 0)], cycle: 8, pass: 2))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.selectedPassNo, 2); XCTAssertEqual(deck.loopCycle, 8); XCTAssertEqual(deck.loop[0].b1, 70)
    }
    func testAnOverlongPassIsTruncatedNotOverrun() {
        let deck = ReelDeck()
        let big = (0..<(ReelDeck.cap + 500)).map { ReelDeck.Ev(beat: Double($0 % 4), cable: 1, b0: 0x90, b1: UInt8($0 % 100), b2: 90, machine: 0) }
        XCTAssertTrue(deck.stageLoop(big, cycle: 4, pass: 0))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.loopN, ReelDeck.cap)
    }
    func testAnEmptyPassStagesNoLoop() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageLoop([], cycle: 4, pass: 3))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertFalse(deck.hasLoop)
    }
    func testStagingAndAdoptingFromTwoThreadsNeverTearsALoop() {
        // main stages loops whose events all carry the same pitch; the "render" thread adopts and checks every adopted loop is whole (one pitch throughout, as long as it was staged)
        let deck = ReelDeck()
        let stop = ManagedFlag()
        var torn = 0, adopted = 0
        let reader = Thread {
            while !stop.isSet {
                if deck.adoptStagedLoop() {
                    adopted += 1
                    let k = deck.loop[0].b1
                    for i in 0..<deck.loopN where deck.loop[i].b0 == 0x90 && deck.loop[i].b1 != k { torn += 1 }
                }
            }
        }
        reader.start()
        for n in 0..<3000 {
            let k = UInt8(n % 100 + 20)
            _ = deck.stageLoop((0..<200).map { ReelDeck.Ev(beat: Double($0) / 100, cable: 1, b0: 0x90, b1: k, b2: 90, machine: 0) }, cycle: 4, pass: n)
            if n % 50 == 0 { usleep(100) }
        }
        usleep(2000)
        stop.set()
        while reader.isExecuting { usleep(100) }
        XCTAssertEqual(torn, 0)
        XCTAssertGreaterThan(adopted, 0)
    }

    // MARK: replaying a tape pass

    func testReplayingATapePassSendsExactlyThatPassAtTheRightSamples() {
        let t = tape(passes: 4)
        let pass = 2
        let evs = t.reelPassEvents(pass), cycle = t.reelPassCycleBeats(pass)!
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageLoop(evs, cycle: cycle, pass: pass)); XCTAssertTrue(deck.adoptStagedLoop())
        for frames in [64, 333, 512, 4096] {
            let heard = Heard()
            var s: Int64 = 0
            while Double(s) * bps < 8 {                                            // two laps of the loop, window by window, as the Kernel drives it
                deck.replay(beatPos: Double(s) * bps, windowBeats: Double(frames) * bps, cycleBeats: deck.loopCycle, beatsPerSample: bps, windowStart: s, out: heard)
                s += Int64(frames)
            }
            let lap = heard.events.filter { Double($0.sample) * bps < 4 }
            let want = evs.filter { $0.cable != 99 }
            XCTAssertEqual(lap.count, want.count + deck.loopN - evs.count, "the loop's own events plus any closing note-offs, in lap one (frames \(frames))")
            for e in evs {
                let expect = Int64((e.beat / bps).rounded())
                XCTAssertTrue(lap.contains { $0.cable == e.cable && $0.b0 == e.b0 && $0.b1 == e.b1 && abs($0.sample - expect) <= 1 }, "\(e) at sample ~\(expect) (frames \(frames))")
            }
            XCTAssertEqual(heard.events.filter { Double($0.sample) * bps < 8 }.count, lap.count * 2, "the second lap repeats the first (frames \(frames))")
        }
    }
}

private final class ManagedFlag { private let lock = NSLock(); private var v = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return v }
    func set() { lock.lock(); v = true; lock.unlock() }
}
