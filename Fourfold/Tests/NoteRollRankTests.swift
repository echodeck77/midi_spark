//  NoteRollRankTests.swift — MIX ROWS (2026-11-03) §4.3 / §12 test 7: the note feed carries each note's POOL rank. Every START record names the rank (1…8) its pitch was chosen from — before the part's out-transpose and octave — and an END
//  record repeats its START's. The rig holds the pool C D E F G A B C (so a rank names a note), a riff that walks it rank by rank, and 120 BPM at 48 kHz; the generic invariant is `pitch == pool[rank − 1] + 12 × the part's octave`.

import XCTest

private final class RankEmitter: MIDIEmitter {
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {}
}

final class NoteRollRankTests: XCTestCase {
    private let heldPool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]

    // MARK: harness

    private func lane(pulses: Int = 8, steps: Int = 8, rate: ArpRate = .r1_4, gate: Double = 0.5, oct: Int = 0, outTranspose: Int? = nil, notes: UInt8? = nil) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps, velocityAbsolute: 100, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = gate; l.riffOctave = oct; l.riffOutTranspose = outTranspose
        if let n = notes { l.notesOn = true; l.litNotes = n; l.notesGate = gate } else { l.notesOn = false }
        return l
    }
    private func state(_ lines: [EuclidLine], fx: EuclideousFX? = nil, mutate: (inout PluginState) -> Void = { _ in }) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        if let fx { st.euclideousFX = fx }
        mutate(&st)
        return st
    }
    /// `beats` of playing windows, then one STOP window (cutting what still sounds). Returns every roll record in order.
    private func play(_ st: PluginState, beats: Double, pool: [UInt8]? = nil) -> [NoteRollRecord] {
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = RankEmitter()
        let p = NotePool(); for n in pool ?? heldPool { p.noteOn(n, velocity: 100, channel: 0) }
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
        var ts = 0.0, out: [NoteRollRecord] = []
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        out += router.rollRing.drain()
        return out
    }
    private func starts(_ r: [NoteRollRecord], part: UInt8) -> [NoteRollRecord] { r.filter { !$0.isEnd && $0.part == part } }
    private func poolSlice() -> ArraySlice<(note: Int, vel: UInt8)> { heldPool.map { (note: Int($0), vel: UInt8(100)) }[...] }

    // MARK: the pure lookup

    func testThePoolRankOfANoteIsTheRankWhoseNoteItIs() {
        let pool: ArraySlice<(note: Int, vel: UInt8)> = [(60, 100), (64, 100), (67, 100)][...]
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 60), 1); XCTAssertEqual(euclideousPoolRankOf(pool, note: 64), 2); XCTAssertEqual(euclideousPoolRankOf(pool, note: 67), 3)
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 72), 4, "octave copies: rank 4 is the lowest note an octave up")
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 76), 5); XCTAssertEqual(euclideousPoolRankOf(pool, note: 79), 6)
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 91), 8, "the eighth rank is the last one there is")
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 66), 3, "a note no rank names takes the nearest rank by pitch")
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 62), 1, "…the lower on a tie")
        XCTAssertEqual(euclideousPoolRankOf(pool, note: 120), 8, "…and a note above every rank sits on the top one")
        let two: ArraySlice<(note: Int, vel: UInt8)> = [(60, 100), (72, 100)][...]
        XCTAssertEqual(euclideousPoolRankOf(two, note: 72), 2, "two ranks naming one pitch: the lowest rank")
        XCTAssertEqual(euclideousPoolRankOf([][...], note: 60), 0, "an empty pool names no rank")
    }
    func testTheRecordCarriesARankAndTheModelKeepsIt() {
        XCTAssertEqual(MemoryLayout<NoteRollRecord>.size, 17); XCTAssertEqual(MemoryLayout<NoteRollRecord>.stride, 24)
        XCTAssertEqual(NoteRollRecord(onBeat: 0, length: 1, pitch: 60, velocity: 90, part: 0, flags: 1).rank, 0, "a record built without a rank names none")
        var m = NoteRollModel()
        m.ingest([NoteRollRecord(onBeat: 1, length: 1, pitch: 60, velocity: 90, part: 2, flags: 1, rank: 5),
                  NoteRollRecord(onBeat: 1, length: 0.5, pitch: 60, velocity: 0, part: 2, flags: NoteRollRecord.endFlag | 1, rank: 5)])
        XCTAssertEqual(m.parts[2].first?.rank, 5); XCTAssertEqual(m.parts[2].first?.endBeat, 1.5)
    }

    // MARK: the Router's records

    func testRiffStrikesCarryTheRankOfThePoolNoteTheyPlay() {
        let r = play(state([lane()]), beats: 8.5)
        let s = starts(r, part: 0)
        XCTAssertGreaterThanOrEqual(s.count, 8)
        for (i, rec) in s.enumerated() {
            XCTAssertEqual(Int(rec.rank), i % 8 + 1, "hit \(i): the riff walks ranks 1…8")
            XCTAssertEqual(Int(rec.pitch), Int(heldPool[Int(rec.rank) - 1]), "the pitch is the pool's note at that rank")
        }
    }
    func testOutTransposeAndOctaveMoveThePitchButNeverTheRank() {
        let r = play(state([lane(oct: 1, outTranspose: 2)]), beats: 8.5)
        let s = starts(r, part: 0)
        XCTAssertGreaterThanOrEqual(s.count, 8)
        for (i, rec) in s.enumerated() {
            XCTAssertEqual(Int(rec.rank), i % 8 + 1, "the rank is the pool's — hit \(i)")
            XCTAssertNotEqual(Int(rec.pitch), Int(heldPool[Int(rec.rank) - 1]), "…while the pitch moved (octave + 2 scale steps)")
        }
    }
    func testTheNotesLayerCarriesItsOwnRanksOctaveCopiesIncluded() {
        // MIDI pool C E G (three notes): rank 2 is E; rank 5 is E an octave up (an octave copy). Both lit → part 1 strikes both, each naming its rank.
        let lines = [lane(pulses: 4, steps: 4, notes: 0b0001_0010)]
        let r = play(state(lines), beats: 6.5, pool: [60, 64, 67])
        let n = starts(r, part: 1)
        XCTAssertFalse(n.isEmpty, "the notes layer struck")
        XCTAssertEqual(Set(n.map { Int($0.rank) }), [2, 5], "the two lit ranks, nothing else")
        for rec in n { XCTAssertEqual(Int(rec.pitch), rec.rank == 2 ? 64 : 76, "rank 2 is E, rank 5 is E an octave up") }
    }
    func testARatchetedHitsEveryStrikeCarriesTheHitsRank() {
        var fx = EuclideousFX(); fx.cells[0 * 8 + 2] = 3          // RATCH row, riff column 3 (rank 3): three strikes
        let r = play(state([lane()], fx: fx), beats: 8.5)
        let s = starts(r, part: 0)
        let ratcheted = s.filter { $0.rank == 3 }
        let plain = s.filter { $0.rank == 4 }
        XCTAssertGreaterThanOrEqual(ratcheted.count, plain.count * 3 - 2, "the ratcheted hit strikes three times (its deferred strikes come through the echo ring)")
        XCTAssertTrue(ratcheted.allSatisfy { Int($0.pitch) == Int(heldPool[2]) }, "…all of rank 3's note")
        XCTAssertTrue(s.allSatisfy { $0.rank >= 1 && $0.rank <= 8 }, "no strike lost its rank on the way through the echo ring")
    }
    func testAnEndRecordRepeatsItsStartsRank() {
        // a long gate (almost the whole beat) and a stop half way through a note: the cut writes an END record
        let r = play(state([lane(rate: .r1_4, gate: 0.99)]), beats: 4.5)
        let ends = r.filter { $0.isEnd }
        XCTAssertFalse(ends.isEmpty, "the stop cut a sounding note")
        for e in ends {
            let start = r.first { !$0.isEnd && $0.part == e.part && $0.pitch == e.pitch && abs($0.onBeat - e.onBeat) < 1e-6 }
            XCTAssertNotNil(start); XCTAssertEqual(e.rank, start?.rank, "the END names the START's rank")
            XCTAssertGreaterThan(e.rank, 0)
        }
    }
    func testATradedHitKeepsTheSendersRankOnTheReceivingPart() {
        // lane 1 (octave 0) and lane 2 (octave +1) SWAP every phase; both walk the pool. Whoever sounds a note, its rank names the pool note it came from and its pitch adds the PART's octave.
        var one = lane(pulses: 8, steps: 8, rate: .r1_4, oct: 0), two = lane(pulses: 8, steps: 8, rate: .r1_4, oct: 1)
        one.answerTradeOn = true; one.answerTradeMode = .swap; one.answerTradeWith = 1; one.answerCycleEach = 1
        two.answerTradeOn = true; two.answerTradeMode = .swap; two.answerTradeWith = 0; two.answerCycleEach = 1
        let r = play(state([one, two]), beats: 16.5)
        let octaveOfPart: [Int: Int] = [0: 0, 2: 1]
        var seen: Set<UInt8> = []
        for rec in r where !rec.isEnd {
            guard let oct = octaveOfPart[Int(rec.part)] else { continue }
            XCTAssertGreaterThan(rec.rank, 0)
            XCTAssertEqual(Int(rec.pitch), Int(heldPool[Int(rec.rank) - 1]) + 12 * oct, "part \(rec.part): rank \(rec.rank) names the note it was struck from")
            seen.insert(rec.part)
        }
        XCTAssertEqual(seen, [0, 2], "both lanes' riff parts struck")
    }
    func testAShadowFollowerWithAnEmptyOwnPoolDrawsTheNotesOnTheRanksTheyCameFrom() {
        // lane 2 SHADOWs lane 1 but has every source switched off (an EMPTY pool of its own): its strikes copy lane 1's pitches, so each is struck on the rank lane 1 chose it from — not rank 0, and not a lookup in a pool it does not have
        let one = lane(pulses: 8, steps: 8, rate: .r1_4)
        var two = lane(pulses: 8, steps: 8, rate: .r1_4)
        for b in 0..<5 { two.setPoolSrc(b, false) }
        two.listenSource = 0; two.answerPitchOn = true; two.answerPitchMode = .shadow
        let r = play(state([one, two]), beats: 8.5)
        let leader = starts(r, part: 0), follower = starts(r, part: 2)
        XCTAssertGreaterThanOrEqual(follower.count, 6, "the follower struck")
        XCTAssertTrue(follower.allSatisfy { $0.rank >= 1 && $0.rank <= 8 }, "no follower strike is unranked (an empty own pool)")
        for f in follower { XCTAssertTrue(leader.contains { $0.rank == f.rank && $0.pitch == f.pitch }, "the follower's rank \(f.rank) is a rank the leader struck that pitch on") }
    }
    func testEveryStrikeOfADenseRandomishDocumentCarriesAValidRank() {
        var a = lane(pulses: 5, steps: 8, rate: .r1_8, gate: 0.99, outTranspose: 3, notes: 0b1000_0101), b = lane(pulses: 11, steps: 16, rate: .r1_16, oct: -1, notes: 0b0000_0110)
        a.riffOutMask = 0b0011; b.notesOutMask = 0
        var fx = EuclideousFX(); fx.cells[0 * 8 + 1] = 2; fx.cells[0 * 8 + 5] = 4
        let r = play(state([a, b], fx: fx), beats: 16.5)
        let s = r.filter { !$0.isEnd }
        XCTAssertGreaterThan(s.count, 60)
        XCTAssertTrue(s.allSatisfy { $0.rank >= 1 && $0.rank <= 8 }, "a non-empty pool: every strike names a rank 1…8 — \(s.filter { $0.rank < 1 || $0.rank > 8 }.count) did not")
        XCTAssertTrue(r.filter { $0.isEnd }.allSatisfy { $0.rank >= 1 && $0.rank <= 8 })
    }
    func testNoStrikeOfANonEmptyPoolNamesRankZero() {
        // rank 0 means "the pool was empty"; a lane only strikes from a pool that has notes, so a strike never carries it
        let r = play(state([lane()]), beats: 4.5)
        XCTAssertFalse(starts(r, part: 0).contains { $0.rank == 0 })
    }
}
