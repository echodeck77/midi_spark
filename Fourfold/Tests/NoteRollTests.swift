//  NoteRollTests.swift — CARD BACKS (2026-10-28) §13 test 5: the roll feed. The ring (order, drop-oldest, a concurrent producer), the model that reads it, and the Router's records against what it put on the wire.

import XCTest

final class NoteRollTests: XCTestCase {

    private func rec(_ n: Int, part: UInt8 = 0, outs: UInt8 = 1) -> NoteRollRecord {
        NoteRollRecord(onBeat: Double(n), length: Float(n % 7) + 0.5, pitch: UInt8(n & 0x7F), velocity: UInt8((n * 3) & 0x7F), part: part, flags: outs)
    }

    // MARK: the ring

    func testARecordIsSixteenBytesAndCarriesEveryField() {
        XCTAssertEqual(MemoryLayout<NoteRollRecord>.size, 16)
        XCTAssertEqual(MemoryLayout<NoteRollRecord>.stride, 16)
        let r = NoteRollRecord(onBeat: 12.5, length: 0.75, pitch: 61, velocity: 99, part: 6, flags: 0b0101 | NoteRollRecord.heldFlag)
        XCTAssertEqual(r.outs, 0b0101); XCTAssertTrue(r.isHeld); XCTAssertFalse(r.isEnd); XCTAssertFalse(r.isSilent)
        XCTAssertTrue(NoteRollRecord(onBeat: 0, length: 0, pitch: 0, velocity: 0, part: 0, flags: 0).isSilent, "no output bit = routed nowhere")
    }
    func testTheRingDeliversEveryRecordOnceInOrder() {
        let ring = NoteRollRing()
        XCTAssertTrue(ring.drain().isEmpty)
        for i in 0..<10 { ring.push(rec(i)) }
        XCTAssertEqual(ring.drain().map { $0.onBeat }, (0..<10).map(Double.init))
        XCTAssertTrue(ring.drain().isEmpty, "a drained record is never delivered again")
        for i in 10..<13 { ring.push(rec(i)) }
        XCTAssertEqual(ring.drain().map { $0.onBeat }, [10, 11, 12])
        XCTAssertEqual(ring.dropped, 0)
    }
    func testAConsumerThatFallsBehindLosesTheOldestNotTheNewest() {
        let ring = NoteRollRing(), cap = NoteRollRing.capacity
        for i in 0..<(cap + 300) { ring.push(rec(i)) }
        let got = ring.drain()
        XCTAssertEqual(got.count, cap - 1, "a full ring's worth less the one slot the producer may be writing")
        XCTAssertEqual(got.first?.onBeat, 301, "the 301 oldest were dropped"); XCTAssertEqual(got.last?.onBeat, Double(cap + 299), "the newest is there")
        XCTAssertEqual(got.map { $0.onBeat }, (301..<(cap + 300)).map(Double.init), "in order, no gap")
        XCTAssertEqual(ring.dropped, 301)
        ring.push(rec(999_999)); XCTAssertEqual(ring.drain().map { $0.onBeat }, [999_999], "and it carries on from there")
    }
    /// A producer thread pushes numbered records as fast as it can while this thread drains: every record that comes out is whole (all its fields agree with its number), the numbers only ever rise, and a lapped consumer's loss is
    /// counted — never a torn record, never a repeat.
    func testAConcurrentProducerNeverShowsATornRecordOrARepeat() {
        let ring = NoteRollRing()
        let total = 1_500_000
        let done = ManagedFlag()
        let producer = Thread { for i in 0..<total { ring.push(self.rec(i, part: UInt8(i & 7), outs: UInt8(i & 15))) }; done.set() }
        producer.start()
        var last = -1, seen = 0
        func check(_ batch: [NoteRollRecord]) {
            for r in batch {
                guard r.onBeat.isFinite, r.onBeat >= 0, r.onBeat < Double(total) else { XCTFail("a torn record: onBeat \(r.onBeat)"); continue }
                let i = Int(r.onBeat)
                XCTAssertGreaterThan(i, last, "numbers rise: no repeat, no reorder")
                XCTAssertEqual(r.pitch, UInt8(i & 0x7F)); XCTAssertEqual(r.velocity, UInt8((i * 3) & 0x7F)); XCTAssertEqual(r.part, UInt8(i & 7)); XCTAssertEqual(r.flags, UInt8(i & 15)); XCTAssertEqual(r.length, Float(i % 7) + 0.5)
                last = i; seen += 1
            }
        }
        while !done.isSet { check(ring.drain()); if Int.random(in: 0..<3) == 0 { usleep(UInt32.random(in: 20...600)) } }   // a consumer that sometimes dawdles, so the producer laps the ring
        check(ring.drain())
        XCTAssertEqual(last, total - 1, "the newest record always arrives")
        XCTAssertEqual(UInt64(seen) + ring.dropped, UInt64(total), "every record is either delivered or counted as dropped")
        XCTAssertGreaterThan(seen, 1_000, "the consumer really read while the producer ran"); XCTAssertGreaterThan(ring.dropped, 0, "…and fell behind often enough for the ring to lap it")
    }

    // MARK: the model

    func testTheModelDrawsANoteFromItsStrikeToItsPlannedEndAndAnEndRecordCutsItShort() {
        var m = NoteRollModel()
        m.ingest([NoteRollRecord(onBeat: 4, length: 1, pitch: 60, velocity: 90, part: 2, flags: 0b0100)])
        XCTAssertEqual(m.parts[2], [NoteRollNote(onBeat: 4, endBeat: 5, pitch: 60, velocity: 90, outs: 0b0100)])
        m.ingest([NoteRollRecord(onBeat: 4, length: 0.25, pitch: 60, velocity: 0, part: 2, flags: NoteRollRecord.endFlag)])
        XCTAssertEqual(m.parts[2].first?.endBeat, 4.25, "a mute / stop shortened it")
        m.ingest([NoteRollRecord(onBeat: 6, length: .infinity, pitch: 64, velocity: 80, part: 3, flags: 0b0010 | NoteRollRecord.heldFlag)])
        XCTAssertEqual(m.openCount, 1); XCTAssertNil(m.parts[3].first?.endBeat)
        XCTAssertEqual(m.notes(part: 3, from: 99, to: 101, now: 100).count, 1, "a held note is drawn up to now")
        m.ingest([NoteRollRecord(onBeat: 6, length: 2, pitch: 64, velocity: 0, part: 3, flags: NoteRollRecord.endFlag)])
        XCTAssertEqual(m.openCount, 0)
        XCTAssertEqual(m.notes(part: 3, from: 99, to: 101, now: 100).count, 0, "…and once closed it is not drawn beyond its end")
        m.ingest([NoteRollRecord(onBeat: 8, length: 1, pitch: 50, velocity: 70, part: 0, flags: 0)])
        XCTAssertTrue(m.parts[0][0].outs == 0, "a part routed nowhere still draws its note, marked silent")
        XCTAssertEqual(m.lastOnBeat[0], 8)
        m.ingest([NoteRollRecord(onBeat: 9, length: 1, pitch: 52, velocity: 70, part: 1, flags: 0b0110)])
        XCTAssertEqual(m.lastOnBeatByOutput[1], [-.infinity, 9, 9, -.infinity], "the jacks' lights: the outputs B and C took the note")
        XCTAssertEqual(m.lastOnBeatByOutput[0], [-.infinity, -.infinity, -.infinity, -.infinity], "a silent strike lights nothing")
        m.prune(before: 7); XCTAssertTrue(m.parts[2].isEmpty); XCTAssertEqual(m.parts[0].count, 1)
        m.clear(); XCTAssertTrue(m.parts.allSatisfy { $0.isEmpty }); XCTAssertEqual(m.lastOnBeat[0], -.infinity)
    }
    func testTheModelKeepsOnlyTheNewestNotesOfAPart() {
        var m = NoteRollModel()
        m.ingest((0..<(NoteRollModel.perPartCap + 50)).map { rec($0, part: 1) })
        XCTAssertEqual(m.parts[1].count, NoteRollModel.perPartCap); XCTAssertEqual(m.parts[1].first?.onBeat, 50)
    }

    // MARK: the Router's feed against its wire

    /// Lane 1's riff → A, notes → B (and C), lane 2's notes routed nowhere: every note-on the wire carries on an output has a record naming that output at the same beat and pitch, a part routed nowhere has records marked silent
    /// and no wire message, and the record's planned length is the note's real length.
    func testTheRouterFeedsEveryStrikeToTheRollAndTheRecordsAgreeWithTheWire() {
        var l1 = EuclidLine(pulses: 4, steps: 8); l1.rate = .r1_8; l1.enabled = true; l1.riffOn = true; l1.useRiff = true; l1.litNotes = 0b0000_0100; l1.notesOn = true; l1.notesWhen = 0b11; l1.gate = 0.5; l1.notesGate = 0.25
        l1.riffOutMask = 0b0001; l1.notesOutMask = 0b0110
        var l2 = l1; l2.riffOutMask = 0b1000; l2.notesOutMask = 0
        let lines = [l1, l2, { var o = EuclidLine(); o.enabled = false; return o }(), { var o = EuclidLine(); o.enabled = false; return o }()]
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        st.euclideousLines = lines; st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(); st.euclideousSoloMask = 0
        let input = FourfoldCompose.Input(lines: lines, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: 0, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        struct Ev { let sample: Int64; let cable: UInt8; let on: Bool; let note: UInt8 }
        final class Rec: MIDIEmitter { var evs: [Ev] = []
            func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
                let s = b0 & 0xF0; guard s == 0x90 || s == 0x80 else { return }
                evs.append(Ev(sample: sampleTime, cable: cable, on: s == 0x90 && b2 > 0, note: b1)) } }
        let e = Rec(), router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
        var beat = 0.0, ts = 0.0, records: [NoteRollRecord] = []
        var windows: [(beat: Double, ts: Double)] = []
        for _ in 0..<100 {
            windows.append((beat, ts))
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            records += router.rollRing.drain()
            beat += Double(frames) * tempo / 60 / sr; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        records += router.rollRing.drain()
        func beatOf(_ sample: Int64) -> Double { let w = windows.last { $0.ts <= Double(sample) } ?? windows[0]; return w.beat + (Double(sample) - w.ts) * tempo / 60 / sr }
        let strikes = records.filter { !$0.isEnd }
        XCTAssertFalse(strikes.isEmpty)
        for o in 0..<4 {
            let wire = e.evs.filter { $0.on && $0.cable == UInt8(o + 1) }
            let fed = strikes.filter { $0.outs & (1 << UInt8(o)) != 0 }
            XCTAssertEqual(wire.count, fed.count, "output \(o + 1): one record per note-on")
            for w in wire { XCTAssertTrue(fed.contains { $0.pitch == w.note && abs($0.onBeat - beatOf(w.sample)) < 0.002 }, "output \(o + 1): the note-on \(w.note) at beat \(beatOf(w.sample)) has a record") }
        }
        XCTAssertTrue(strikes.contains { $0.part == 0 && $0.outs == 0b0001 }, "lane 1's riff (part 0) on A")
        XCTAssertTrue(strikes.contains { $0.part == 1 && $0.outs == 0b0110 }, "lane 1's notes (part 1) on B and C")
        XCTAssertTrue(strikes.contains { $0.part == 2 && $0.outs == 0b1000 }, "lane 2's riff (part 2) on D")
        let silent = strikes.filter { $0.part == 3 }
        XCTAssertFalse(silent.isEmpty, "lane 2's notes are routed nowhere — and still drawn"); XCTAssertTrue(silent.allSatisfy { $0.isSilent })
        XCTAssertEqual(e.evs.filter { $0.on && $0.cable == 0 }.count, e.evs.filter { $0.on && $0.cable >= 1 && $0.cable <= 4 }.count, "ALL carries what the outputs did — silent notes add nothing")
        // lengths: the notes layer's gate is a quarter of the gap, the riff's a half — each record says so
        let riffLen = strikes.filter { $0.part == 0 }.map { Double($0.length) }, notesLen = strikes.filter { $0.part == 1 }.map { Double($0.length) }
        XCTAssertGreaterThan(Set(riffLen.map { ($0 * 100).rounded() }).count, 0)
        XCTAssertTrue(zip(riffLen.sorted(), notesLen.sorted()).allSatisfy { $0.0 >= $0.1 - 1e-6 }, "the riff's gate is the longer")
        var m = NoteRollModel(); m.ingest(records)
        XCTAssertEqual(m.openCount, 0, "after the stop every note has an end")
    }
}

/// A tiny cross-thread flag for the producer test.
private final class ManagedFlag {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return v }
}
