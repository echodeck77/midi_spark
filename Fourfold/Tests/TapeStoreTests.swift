//  TapeStoreTests.swift — REEL PHASE 1d: the tape's file (Fourfold/Engine/TapeStore.swift), spilling old chunks to it, and a session surviving a relaunch.

import XCTest

final class TapeStoreTests: XCTestCase {
    private var dir: URL!
    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TapeStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private func url(_ n: String = "session.tape") -> URL { dir.appendingPathComponent(n) }

    private func block(_ salt: Int, count: Int) -> [TapeEvent] {
        (0..<count).map { TapeEvent.note(tick: UInt32(salt * 1000 + $0), on: $0 % 2 == 0, note: UInt8((salt + $0) % 100 + 10), vel: UInt8($0 % 100 + 20), cable: $0 % 5, lane: $0 % 3 == 0 ? nil : $0 % 4, channel: UInt8($0 % 16)) }
    }
    private func put(_ s: TapeStore, _ evs: [TapeEvent]) -> Int? {
        evs.withUnsafeBufferPointer { s.appendBlock(from: $0.baseAddress!, count: evs.count, minTick: evs.map { $0.tick }.min()!, maxTick: evs.map { $0.tick }.max()!) }
    }
    private func loadAll(_ s: TapeStore) -> [[TapeEvent]] {
        var out: [[TapeEvent]] = []
        s.load { _, b, p in out.append((0..<b.count).map { p[$0] }) }
        return out
    }

    // MARK: the file

    func testBlocksRoundTripThroughTheFile() {
        let a = block(1, count: 16), b = block(2, count: 16), c = block(3, count: 5)
        do {
            let s = TapeStore(url: url(), chunkEvents: 16)!
            _ = loadAll(s)
            XCTAssertEqual(put(s, a), 0); XCTAssertEqual(put(s, b), 1); XCTAssertEqual(put(s, c), 2)
        }
        let s = TapeStore(url: url(), chunkEvents: 16)!
        XCTAssertEqual(loadAll(s), [a, b, c])
        XCTAssertEqual(s.blocks.map { $0.count }, [16, 16, 5])
        XCTAssertEqual(s.blocks[1].minTick, 2000)
        var out = [TapeEvent](repeating: a[0], count: 16)
        XCTAssertTrue(out.withUnsafeMutableBufferPointer { s.read(block: 1, into: $0.baseAddress!) })
        XCTAssertEqual(out, b)
    }
    // Review 2026-10-27: a session.tape written before the nine ports has cables 1-4 meaning "outputs A–D"; read with the new meaning every pass would land on the wrong port. Its old magic makes it start over.
    func testATapeWrittenBeforeTheNinePortsIsResetNotMisread() {
        let a = block(1, count: 16)
        do { let s = TapeStore(url: url(), chunkEvents: 16)!; _ = loadAll(s); _ = put(s, a) }
        let h = try! FileHandle(forUpdating: url()); try! h.seek(toOffset: 7); try! h.write(contentsOf: Data([0x01])); try! h.close()   // the version-1 magic
        let s = TapeStore(url: url(), chunkEvents: 16)!
        XCTAssertEqual(loadAll(s), [], "an old-meaning tape is discarded")
        XCTAssertEqual(s.blocks.count, 0)
        XCTAssertEqual(put(s, a), 0, "and the store is usable from a clean start")
    }
    func testATornTailIsCutAndTheGoodPartKept() {
        let a = block(1, count: 16), b = block(2, count: 16), c = block(3, count: 16)
        do { let s = TapeStore(url: url(), chunkEvents: 16)!; _ = loadAll(s); _ = put(s, a); _ = put(s, b); _ = put(s, c) }
        let h = try! FileHandle(forUpdating: url()); let len = try! h.seekToEnd(); try! h.truncate(atOffset: len - 10); try! h.close()     // power cut in the middle of writing the third block
        let s = TapeStore(url: url(), chunkEvents: 16)!
        XCTAssertEqual(loadAll(s), [a, b])
        XCTAssertEqual(s.lengthBytes(), s.tailOffset, "the torn bytes are gone")
        XCTAssertEqual(put(s, c), 2, "and writing carries on from the good part")
        let t = TapeStore(url: url(), chunkEvents: 16, exclusive: false)!
        XCTAssertEqual(loadAll(t), [a, b, c])
    }
    func testACorruptedBlockEndsTheList() {
        let a = block(1, count: 16), b = block(2, count: 16), c = block(3, count: 16)
        do { let s = TapeStore(url: url(), chunkEvents: 16)!; _ = loadAll(s); _ = put(s, a); _ = put(s, b); _ = put(s, c) }
        let h = try! FileHandle(forUpdating: url())
        try! h.seek(toOffset: TapeStore.fileHeaderBytes + (TapeStore.blockHeaderBytes + 16 * 8) + TapeStore.blockHeaderBytes + 20)        // one byte inside the second block's records
        let was = try! h.read(upToCount: 1)!; try! h.seek(toOffset: TapeStore.fileHeaderBytes + (TapeStore.blockHeaderBytes + 16 * 8) + TapeStore.blockHeaderBytes + 20)
        try! h.write(contentsOf: Data([was[0] ^ 0xFF])); try! h.close()
        let s = TapeStore(url: url(), chunkEvents: 16)!
        XCTAssertEqual(loadAll(s), [a], "everything from the damaged block on is dropped")
    }
    func testAFileThatIsNotATapeOrWasMadeWithAnotherChunkSizeStartsFresh() {
        try! Data("this is not a tape file at all".utf8).write(to: url())
        let s = TapeStore(url: url(), chunkEvents: 16)!
        XCTAssertEqual(loadAll(s), [])
        XCTAssertNotNil(put(s, block(1, count: 16)))
        XCTAssertEqual(loadAll(TapeStore(url: url(), chunkEvents: 16, exclusive: false)!).count, 1)
        XCTAssertEqual(loadAll(TapeStore(url: url(), chunkEvents: 32, exclusive: false)!), [], "a different chunk size cannot be read, so it starts over")
    }
    func testTheTailIsRewrittenInPlaceAndReplacedByTheFullBlock() {
        let full = block(9, count: 16)
        let s = TapeStore(url: url(), chunkEvents: 16)!; _ = loadAll(s)
        _ = put(s, block(1, count: 16))
        XCTAssertTrue(full.withUnsafeBufferPointer { s.writeTail(from: $0.baseAddress!, count: 3, minTick: 9000, maxTick: 9002) })
        XCTAssertTrue(full.withUnsafeBufferPointer { s.writeTail(from: $0.baseAddress!, count: 11, minTick: 9000, maxTick: 9010) })
        XCTAssertEqual(loadAll(TapeStore(url: url(), chunkEvents: 16, exclusive: false)!).map { $0.count }, [16, 11], "a crash now keeps the tail as far as it was written")
        XCTAssertNotNil(put(s, full))
        XCTAssertEqual(loadAll(TapeStore(url: url(), chunkEvents: 16, exclusive: false)!).map { $0.count }, [16, 16], "and the full block takes its place exactly")
    }
    func testTwoStoresCannotHoldTheSameFileAndALockGoesWithItsOwner() {
        var first: TapeStore? = TapeStore(url: url(), chunkEvents: 16)
        XCTAssertNotNil(first)
        XCTAssertNil(TapeStore(url: url(), chunkEvents: 16), "a second writer is refused")
        XCTAssertNotNil(TapeStore(url: url(), chunkEvents: 16, exclusive: false), "a reader that does not lock is not")
        first = nil
        XCTAssertNotNil(TapeStore(url: url(), chunkEvents: 16), "once the first is gone the file is free again")
    }
    func testOnlyFilesNoLiveStoreHoldsAreSweptAway() {
        let live = TapeStore(url: url("spill-live.tape"), chunkEvents: 16)
        try! Data("x".utf8).write(to: url("spill-dead1.tape")); try! Data("x".utf8).write(to: url("spill-dead2.tape")); try! Data("x".utf8).write(to: url("keep.me"))
        TapeStore.removeStale(in: dir, prefix: "spill-")
        let left = Set(try! FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertEqual(left, ["spill-live.tape", "keep.me"])
        withExtendedLifetime(live) {}
    }
    func testADeleteOnCloseStoreLeavesNothingBehind() {
        var s: TapeStore? = TapeStore(url: url("temp.tape"), chunkEvents: 16, deleteOnClose: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("temp.tape").path))
        s = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url("temp.tape").path))
    }
    func testAStoreThatCannotBeOpenedIsNil() {
        XCTAssertNil(TapeStore(url: URL(fileURLWithPath: "/dev/null/nowhere/session.tape"), chunkEvents: 16))
    }

    // MARK: the tape with a file

    /// The same notes into a tape with no file and a tape with a file that keeps only 3 chunks in memory.
    private func fill(_ tape: SessionTape, notes: Int) {
        var tick: UInt32 = 0
        tape.writer.append(.segment(tick: 0, starting: true)); tape.writer.append(.tempo(tick: 0, bpm: 120)); tape.writer.append(.pass(tick: 0, cycleTicks: 3840))
        for i in 0..<notes {
            tick += 37
            tape.writer.append(.note(tick: tick, on: i % 2 == 0, note: UInt8(i % 100 + 10), vel: 90, cable: i % 5, lane: i % 4, channel: 0))
            if tick / 3840 > (tick - 37) / 3840 { tape.writer.append(.pass(tick: (tick / 3840) * 3840, cycleTicks: 3840)) }
            if i % 211 == 0 { tape.drain() }
        }
        tape.drain()
    }
    func testASpilledTapeAnswersExactlyLikeAMemoryTape() {
        let mem = SessionTape(chunkEvents: 32, poolSize: 8), spilled = SessionTape(chunkEvents: 32, poolSize: 8)
        spilled.residentChunks = 3
        spilled.attach(store: TapeStore(url: url(), chunkEvents: 32, exclusive: false)!)
        fill(mem, notes: 6000); fill(spilled, notes: 6000)
        XCTAssertEqual(spilled.eventCount, mem.eventCount)
        XCTAssertEqual(spilled.events(from: 0, to: Int.max, kinds: [.note, .control, .tempo, .pass, .segment]), mem.events(from: 0, to: Int.max, kinds: [.note, .control, .tempo, .pass, .segment]))
        XCTAssertEqual(spilled.events(from: 50_000, to: 52_000), mem.events(from: 50_000, to: 52_000), "a range inside the evicted part")
        XCTAssertEqual(spilled.passes(), mem.passes())
        XCTAssertEqual(spilled.filedPasses(), mem.filedPasses())
        XCTAssertEqual(spilled.bpm(at: 10_000), mem.bpm(at: 10_000))
        XCTAssertGreaterThan(mem.sealedCount, 100)
        let chunkBytes = 32 * MemoryLayout<TapeEvent>.stride
        XCTAssertLessThanOrEqual(spilled.residentBytes, (3 + 8 + 2 + 8 + 2) * chunkBytes, "3 kept, the pool, the open one, the read-back cache, a little slack")
        XCTAssertLessThan(spilled.residentBytes, mem.residentBytes / 4)
    }
    func testFullChunksReachTheDiskWithoutAnyFlush() {
        let tape = SessionTape(chunkEvents: 32, poolSize: 8)
        tape.attach(store: TapeStore(url: url(), chunkEvents: 32, exclusive: false)!)
        fill(tape, notes: 500)
        let retained = Unmanaged.passRetained(tape)                       // a crash: the tape is never torn down, so nothing gets a last flush
        let onDisk = TapeStore(url: url(), chunkEvents: 32, exclusive: false)!
        let n = loadAll(onDisk).reduce(0) { $0 + $1.count }
        XCTAssertEqual(n, (tape.eventCount / 32) * 32, "every finished chunk is already on disk; only the one still open is not")
        retained.release()
    }
    func testASessionSurvivesARelaunch() {
        let bps = 120.0 / 60.0 / 48_000.0, wb = 512 * bps
        func play(_ rec: TapeRecorder, _ tape: SessionTape, from b0: Double, beats: Double) {
            var beat = b0, windows = 0
            while beat < b0 + beats {
                windows += 1; if windows % 20 == 0 { tape.drain() }                    // the UI's timer
                rec.beginWindow(playing: true, beatPos: beat, windowBeats: wb, tempo: 120, cycleBeats: 4, sampleStart: Int64((beat / bps).rounded()), beatsPerSample: bps)
                for k in 0..<4 { let b = beat + Double(k) * wb / 4; rec.record(sampleTime: Int64((b / bps).rounded()), cable: UInt8(1 + k % 2), k % 2 == 0 ? 0x90 : 0x80, UInt8(50 + k), k % 2 == 0 ? 100 : 0, lane: k % 4) }
                beat += wb
            }
        }
        var before: (events: [TapeEvent], filed: [TapePass], end: Int, count: Int) = ([], [], 0, 0)
        do {
            let tape = SessionTape(chunkEvents: 64, poolSize: 8)
            tape.attach(store: TapeStore(url: url(), chunkEvents: 64)!)
            let rec = TapeRecorder(writer: tape.writer)
            play(rec, tape, from: 0, beats: 22)                                  // five whole passes and part of a sixth
            tape.flushNow()
            before = (tape.events(from: 0, to: Int.max, kinds: [.note, .control, .tempo, .pass, .segment]), tape.filedPasses(), tape.endTick(), tape.eventCount)
            XCTAssertEqual(before.filed.count, 5)
        }                                                                  // the app quits
        let tape = SessionTape(chunkEvents: 64, poolSize: 8)
        XCTAssertEqual(tape.attach(store: TapeStore(url: url(), chunkEvents: 64)!), before.count)
        XCTAssertEqual(tape.eventCount, before.count)
        XCTAssertEqual(tape.events(from: 0, to: Int.max, kinds: [.note, .control, .tempo, .pass, .segment]), before.events, "every record, the unfinished chunk too")
        XCTAssertEqual(tape.filedPasses(), before.filed)
        XCTAssertEqual(tape.endTick(), before.end)
        XCTAssertEqual(tape.bpm(at: before.end), 120)
        // the new run picks up where the old one ended
        let rec = TapeRecorder(writer: tape.writer)
        rec.setOrigin(tick: tape.endTick())
        play(rec, tape, from: 0, beats: 12)                                      // the host starts again at beat 0
        let segs = tape.events(from: 0, to: Int.max, kinds: [.segment])
        XCTAssertEqual(Int(segs.last!.tick), before.end, "the new run starts where the old one stopped")
        XCTAssertTrue(segs.last!.isSegmentStart)
        XCTAssertEqual(tape.filedPasses().count, before.filed.count + 2, "the old run's unfinished sixth pass is not whole; the new run adds its own whole passes")
        XCTAssertTrue(tape.events(from: before.end, to: Int.max).count > 0)
        XCTAssertEqual(tape.events(from: 0, to: before.end, kinds: [.note, .control, .tempo, .pass, .segment]), before.events.filter { Int($0.tick) < before.end }, "what was recorded stays exactly where it was")
    }
    func testAnAttachedStoreIsIgnoredOnceRecordingHasStarted() {
        do { let s = TapeStore(url: url(), chunkEvents: 32)!; _ = loadAll(s); _ = put(s, block(1, count: 32)); _ = put(s, block(2, count: 32)) }
        let tape = SessionTape(chunkEvents: 32, poolSize: 8)
        fill(tape, notes: 200)                                              // the live session wins: the old file is not merged in under it
        let live = tape.eventCount
        XCTAssertEqual(tape.attach(store: TapeStore(url: url(), chunkEvents: 32, exclusive: false)!), 0)
        XCTAssertEqual(tape.eventCount, live)
        tape.flushNow()
        let onDisk = loadAll(TapeStore(url: url(), chunkEvents: 32, exclusive: false)!).reduce(0) { $0 + $1.count }
        XCTAssertEqual(onDisk, live, "the file now holds this session, finished chunks and the open one")
    }
    func testATapeKeepsGoingInMemoryIfItsFileDies() {
        let s = TapeStore(url: url(), chunkEvents: 32)!
        let tape = SessionTape(chunkEvents: 32, poolSize: 8)
        tape.residentChunks = 2
        tape.attach(store: s)
        s.close()                                                          // the disk goes away
        fill(tape, notes: 3000)
        XCTAssertEqual(tape.events(from: 0, to: Int.max).count, 3000, "every note is still there: with no file to fall back on, nothing is evicted")
        XCTAssertEqual(tape.droppedEvents, 0)
    }
    func testFourSimulatedHoursStayInsideTheMemoryCeiling() {
        // 4 h at 120 BPM = 28 800 beats, ~150 records a beat (the audit's mean), a whole pass every 16 beats. The 8 MiB budget plus the pool is what may be resident; the rest lives in the file.
        let tape = SessionTape()
        tape.attach(store: TapeStore(url: url(), chunkEvents: tape.chunkEvents)!)
        let w = tape.writer
        w.append(.segment(tick: 0, starting: true)); w.append(.tempo(tick: 0, bpm: 120))
        var peak = 0, notes = 0
        for beat in 0..<28_800 {
            let t0 = beat * 960
            if beat % 16 == 0 { w.append(.pass(tick: UInt32(t0), cycleTicks: 15_360)) }
            for k in 0..<75 {
                let t = UInt32(t0 + k * 12)
                w.append(.note(tick: t, on: true, note: UInt8(40 + k % 48), vel: 90, cable: 1 + k % 4, lane: k % 4, channel: 0))
                w.append(.note(tick: t + 6, on: false, note: UInt8(40 + k % 48), vel: 0, cable: 1 + k % 4, lane: k % 4, channel: 0))
                notes += 2
            }
            if beat % 40 == 0 { tape.drain(); peak = max(peak, tape.residentBytes) }     // the UI's timer: about every 20 000 records, well inside the pool
        }
        tape.drain(); peak = max(peak, tape.residentBytes)
        print("TAPE4H records=\(tape.eventCount) (\(tape.eventCount * 8 / 1024) KiB of tape) peak resident=\(peak / 1024) KiB")
        XCTAssertEqual(tape.droppedEvents, 0)
        XCTAssertEqual(tape.eventCount, notes + 2 + 28_800 / 16)
        XCTAssertLessThan(peak, 11 * 1024 * 1024, "peak resident \(peak / 1024) KiB — the budget is 8 MiB of finished chunks plus the pool, the open chunk and the read-back cache")
        XCTAssertGreaterThan(tape.eventCount * 8, 30 * 1024 * 1024, "and the tape really is bigger than that")
        XCTAssertEqual(tape.filedPasses().count, 28_800 / 16 - 1)
        let first = tape.events(from: 0, to: 15_360)                       // the very first pass, long since evicted
        XCTAssertEqual(first.count, 16 * 150)
        XCTAssertEqual(first.first?.tick, 0)
    }
}
