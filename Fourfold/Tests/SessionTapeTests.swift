//  SessionTapeTests.swift — REEL PHASE 1a: the whole-session recorder's store (Fourfold/Engine/SessionTape.swift).
//  The store alone: records, chunk hand-off, drops when the pool runs dry, range queries, the pass index and the tempo map, and a real two-thread run.

import XCTest

final class SessionTapeTests: XCTestCase {

    // MARK: the 8-byte record

    func testEventIsEightBytes() {
        XCTAssertEqual(MemoryLayout<TapeEvent>.size, 8)
        XCTAssertEqual(MemoryLayout<TapeEvent>.stride, 8)
    }

    func testNoteRoundTripsEveryField() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let tick = UInt32.random(in: 0...UInt32.max, using: &rng)
            let on = Bool.random(using: &rng)
            let note = UInt8.random(in: 0...127, using: &rng)
            let vel = UInt8.random(in: 1...127, using: &rng)
            let cab = Int.random(in: 0...4, using: &rng)
            let lane: Int? = Bool.random(using: &rng) ? Int.random(in: 0...3, using: &rng) : nil
            let ch = UInt8.random(in: 0...15, using: &rng)
            let e = TapeEvent.note(tick: tick, on: on, note: note, vel: vel, cable: cab, lane: lane, channel: ch)
            XCTAssertEqual(e.kind, .note)
            XCTAssertEqual(e.tick, tick)
            XCTAssertEqual(e.isOn, on)
            XCTAssertEqual(e.note, note)
            XCTAssertEqual(e.vel, on ? vel : 0, "a note-off carries no velocity")
            XCTAssertEqual(e.cable, cab)
            XCTAssertEqual(e.output, cab >= 1 ? cab - 1 : nil)
            XCTAssertEqual(e.lane, lane)
            XCTAssertEqual(e.channel, ch)
        }
    }

    func testLaneZeroIsNotLaneUnknown() {
        let a = TapeEvent.note(tick: 0, on: true, note: 60, vel: 100, cable: 1, lane: 0, channel: 0)
        let b = TapeEvent.note(tick: 0, on: true, note: 60, vel: 100, cable: 1, lane: nil, channel: 0)
        XCTAssertEqual(a.lane, 0)
        XCTAssertNil(b.lane)
    }

    func testNoteOnVelocityIsNeverZero() {
        XCTAssertEqual(TapeEvent.note(tick: 0, on: true, note: 60, vel: 0, cable: 1, lane: nil, channel: 0).vel, 1, "velocity 0 would read back as a note-off")
    }

    func testOutOfRangeFieldsAreClamped() {
        let e = TapeEvent.note(tick: 5, on: true, note: 200, vel: 255, cable: 9, lane: 7, channel: 31)
        XCTAssertEqual(e.note, 200 & 0x7F)
        XCTAssertEqual(e.cable, 4)
        XCTAssertEqual(e.lane, 3)
        XCTAssertEqual(e.channel, 15)
    }

    func testTempoRoundTripsToAHundredth() {
        for bpm in [20.0, 59.99, 90, 120, 120.5, 133.33, 299, 480.25, 655.0] {
            XCTAssertEqual(TapeEvent.tempo(tick: 7, bpm: bpm).bpm, bpm, accuracy: 0.005)
            XCTAssertEqual(TapeEvent.tempo(tick: 7, bpm: bpm).kind, .tempo)
        }
        XCTAssertEqual(TapeEvent.tempo(tick: 0, bpm: 100_000).bpm, 655.35, accuracy: 0.005, "clamped, not wrapped")
        XCTAssertEqual(TapeEvent.tempo(tick: 0, bpm: 0).bpm, 0.01, accuracy: 0.005, "never zero")
    }

    func testPassAndSegmentRoundTrip() {
        let p = TapeEvent.pass(tick: 3840, cycleTicks: 7680)
        XCTAssertEqual(p.kind, .pass)
        XCTAssertEqual(p.cycleTicks, 7680)
        XCTAssertEqual(p.tick, 3840)
        XCTAssertTrue(TapeEvent.segment(tick: 1, starting: true).isSegmentStart)
        XCTAssertFalse(TapeEvent.segment(tick: 1, starting: false).isSegmentStart)
        XCTAssertEqual(TapeEvent.segment(tick: 1, starting: true).kind, .segment)
    }

    // MARK: the ring of chunk pointers

    func testChunkRingIsFifoAndBounded() {
        let ring = TapeChunkRing(capacity: 4)
        let ps = (0..<5).map { _ in UnsafeMutablePointer<TapeEvent>.allocate(capacity: 1) }
        defer { ps.forEach { $0.deallocate() } }
        XCTAssertNil(ring.pop())
        for i in 0..<4 { XCTAssertTrue(ring.push(ps[i])) }
        XCTAssertFalse(ring.push(ps[4]), "full")
        XCTAssertEqual(ring.count, 4)
        for i in 0..<4 { XCTAssertEqual(ring.pop(), ps[i]) }
        XCTAssertNil(ring.pop())
        XCTAssertTrue(ring.push(ps[4]), "room again")
        XCTAssertEqual(ring.pop(), ps[4])
    }

    // MARK: appending and draining

    private func note(_ i: Int, tick: Int? = nil) -> TapeEvent {
        .note(tick: UInt32(tick ?? i), on: i % 2 == 0, note: UInt8(i % 100 + 20), vel: UInt8(i % 100 + 20), cable: i % 5, lane: i % 3 == 0 ? nil : i % 4, channel: UInt8(i % 16))
    }

    func testEventsComeBackInOrderAcrossManyChunks() {
        let tape = SessionTape(chunkEvents: 8, poolSize: 3)
        var sent: [TapeEvent] = []
        for i in 0..<200 {
            let e = note(i); sent.append(e); tape.writer.append(e)
            if i % 17 == 0 { tape.drain() }       // the UI polls now and then
        }
        let got = tape.events(from: 0, to: Int.max)
        XCTAssertEqual(got, sent)
        XCTAssertEqual(tape.eventCount, 200)
        XCTAssertEqual(tape.droppedEvents, 0)
    }

    func testReadingWithoutDrainingStillSeesTheOpenChunk() {
        let tape = SessionTape(chunkEvents: 16, poolSize: 2)
        for i in 0..<5 { tape.writer.append(note(i)) }
        XCTAssertEqual(tape.eventCount, 5)
        XCTAssertEqual(tape.events(from: 0, to: 100).count, 5)
    }

    func testExactlyFullChunkIsReadable() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 2)
        for i in 0..<4 { tape.writer.append(note(i)) }
        XCTAssertEqual(tape.events(from: 0, to: 100).map { Int($0.tick) }, [0, 1, 2, 3])
        tape.writer.append(note(4))
        XCTAssertEqual(tape.events(from: 0, to: 100).map { Int($0.tick) }, [0, 1, 2, 3, 4])
    }

    func testEmptyTape() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 2)
        XCTAssertEqual(tape.eventCount, 0)
        XCTAssertEqual(tape.events(from: 0, to: Int.max), [])
        XCTAssertEqual(tape.passes(), [])
        XCTAssertEqual(tape.endTick(), 0)
        XCTAssertEqual(tape.bpm(at: 0), 120)
    }

    // MARK: the pool running dry

    func testPoolExhaustionDropsAndCountsInsteadOfWaiting() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 2)      // 1 open chunk + 2 spare = 12 events before anyone drains
        for i in 0..<20 { tape.writer.append(note(i)) }
        XCTAssertEqual(tape.eventCount, 12)
        XCTAssertEqual(tape.droppedEvents, 8)
        XCTAssertEqual(tape.events(from: 0, to: 100).map { Int($0.tick) }, Array(0..<12), "what it kept is the first 12, intact and in order")
    }

    func testRecoversAfterTheMainThreadCatchesUp() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 2)
        for i in 0..<20 { tape.writer.append(note(i)) }
        tape.drain()
        for i in 100..<108 { tape.writer.append(note(i)) }      // the refilled pool holds exactly two chunks
        XCTAssertEqual(tape.droppedEvents, 8, "no new drops once the pool is refilled")
        XCTAssertEqual(tape.eventCount, 20)
        tape.writer.append(note(108))
        XCTAssertEqual(tape.droppedEvents, 9, "and dry again after that, until the next drain")
        XCTAssertEqual(tape.events(from: 0, to: 1000).map { Int($0.tick) }, Array(0..<12) + Array(100..<108))
    }

    func testResidentMemoryIsBoundedByPoolPlusSealed() {
        let tape = SessionTape(chunkEvents: 8, poolSize: 3)
        let stride = MemoryLayout<TapeEvent>.stride
        XCTAssertEqual(tape.residentBytes, (1 + 3) * 8 * stride)
        for i in 0..<80 { tape.writer.append(note(i)); if i % 5 == 0 { tape.drain() } }
        tape.drain()
        XCTAssertEqual(tape.eventCount + tape.droppedEvents, 80)
        // every chunk allocated is either sealed, being written, or in the pool
        XCTAssertEqual(tape.residentBytes, (tape.sealed.count + 1 + 3) * 8 * stride)
    }

    // MARK: range queries

    func testRangeIsHalfOpenAndAcrossChunks() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 16)
        for i in 0..<40 { tape.writer.append(note(i, tick: i * 10)) }
        XCTAssertEqual(tape.events(from: 100, to: 130).map { Int($0.tick) }, [100, 110, 120])
        XCTAssertEqual(tape.events(from: 101, to: 131).map { Int($0.tick) }, [110, 120, 130])
        XCTAssertEqual(tape.events(from: 390, to: 10_000).map { Int($0.tick) }, [390])
        XCTAssertEqual(tape.events(from: 5000, to: 6000), [])
        XCTAssertEqual(tape.events(from: 50, to: 50), [])
    }

    func testEventsAreReturnedInTimeOrderEvenWhenAppendedOutOfOrder() {
        // the Router can file a note-off for a window slightly before a note-on it filed after (deferred echoes and ratchets): time order is the query's job
        let tape = SessionTape(chunkEvents: 4, poolSize: 8)
        for t in [100, 50, 120, 60, 55, 130, 10] { tape.writer.append(note(0, tick: t)) }
        XCTAssertEqual(tape.events(from: 0, to: 1000).map { Int($0.tick) }, [10, 50, 55, 60, 100, 120, 130])
        XCTAssertEqual(tape.events(from: 0, to: 100).map { Int($0.tick) }, [10, 50, 55, 60])
    }

    func testSameTickKeepsTheOrderItWasAppended() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 8)
        let a = TapeEvent.note(tick: 500, on: false, note: 60, vel: 0, cable: 1, lane: 0, channel: 0)
        let b = TapeEvent.note(tick: 500, on: true, note: 60, vel: 90, cable: 1, lane: 0, channel: 0)
        tape.writer.append(note(0, tick: 10)); tape.writer.append(a); tape.writer.append(note(1, tick: 20)); tape.writer.append(b); tape.writer.append(note(2, tick: 30))
        let got = tape.events(from: 500, to: 501)
        XCTAssertEqual(got, [a, b], "off then on, as the Router filed them: a re-struck note must not be cut by its own old note-off")
    }

    func testQueryByKind() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 8)
        tape.writer.append(.tempo(tick: 0, bpm: 120))
        tape.writer.append(.pass(tick: 0, cycleTicks: 3840))
        tape.writer.append(note(1, tick: 10))
        tape.writer.append(.segment(tick: 20, starting: false))
        XCTAssertEqual(tape.events(from: 0, to: 100).count, 1, "notes only by default")
        XCTAssertEqual(tape.events(from: 0, to: 100, kinds: [.tempo, .pass, .segment, .note]).count, 4)
        XCTAssertEqual(tape.events(from: 0, to: 100, kinds: [.segment]).first?.isSegmentStart, false)
    }

    func testRangeSkippingNeverLosesAnEventThatIsInRange() {
        // randomised: compare the chunk-skipping query against a plain filter
        var rng = SystemRandomNumberGenerator()
        let tape = SessionTape(chunkEvents: 8, poolSize: 64)
        var all: [(TapeEvent, Int)] = []
        for i in 0..<300 {
            let t = max(0, i * 7 + Int.random(in: -20...20, using: &rng))
            let e = note(i, tick: t); all.append((e, i)); tape.writer.append(e)
            if i % 9 == 0 { tape.drain() }
        }
        for _ in 0..<200 {
            let lo = Int.random(in: 0...2200, using: &rng), hi = lo + Int.random(in: 0...400, using: &rng)
            let want = all.filter { Int($0.0.tick) >= lo && Int($0.0.tick) < hi }.sorted { $0.0.tick != $1.0.tick ? $0.0.tick < $1.0.tick : $0.1 < $1.1 }.map { $0.0 }
            XCTAssertEqual(tape.events(from: lo, to: hi), want)
        }
    }

    // MARK: markers

    func testEndTickIsTheLatestRecord() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 8)
        for t in [10, 500, 300, 20] { tape.writer.append(note(0, tick: t)) }
        XCTAssertEqual(tape.endTick(), 500)
    }

    func testTempoMap() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 8)
        tape.writer.append(.tempo(tick: 0, bpm: 120))
        tape.writer.append(note(0, tick: 5))
        tape.writer.append(.tempo(tick: 1000, bpm: 90))
        tape.writer.append(.tempo(tick: 5000, bpm: 140.25))
        XCTAssertEqual(tape.bpm(at: 0), 120)
        XCTAssertEqual(tape.bpm(at: 999), 120)
        XCTAssertEqual(tape.bpm(at: 1000), 90)
        XCTAssertEqual(tape.bpm(at: 4999), 90)
        XCTAssertEqual(tape.bpm(at: 5000), 140.25, accuracy: 0.005)
        XCTAssertEqual(tape.bpm(at: 1_000_000), 140.25, accuracy: 0.005)
        XCTAssertEqual(tape.tempoChanges.count, 3)
    }

    func testPassIndexAndCompleteness() {
        let tape = SessionTape(chunkEvents: 4, poolSize: 16)
        let cyc = 3840
        tape.writer.append(.pass(tick: 0, cycleTicks: cyc))
        tape.writer.append(note(0, tick: 10))
        tape.writer.append(.pass(tick: UInt32(cyc), cycleTicks: cyc))
        tape.writer.append(.segment(tick: 5000, starting: false))      // the transport stopped inside pass 1
        tape.writer.append(.segment(tick: 5000, starting: true))
        tape.writer.append(.pass(tick: UInt32(2 * cyc), cycleTicks: cyc))
        tape.writer.append(.pass(tick: UInt32(3 * cyc), cycleTicks: cyc))
        let ps = tape.passes()
        XCTAssertEqual(ps.map { $0.number }, [0, 1, 2, 3])
        XCTAssertEqual(ps.map { $0.startTick }, [0, cyc, 2 * cyc, 3 * cyc])
        XCTAssertEqual(ps.map { $0.complete }, [true, false, true, false], "pass 1 was cut by a stop; the newest has no end yet")
        XCTAssertEqual(ps[0].endTick, cyc)
        XCTAssertNil(ps[3].endTick)
    }

    func testAPassThatEndsShortIsNotComplete() {
        let tape = SessionTape(chunkEvents: 8, poolSize: 4)
        tape.writer.append(.pass(tick: 0, cycleTicks: 3840))
        tape.writer.append(.pass(tick: 1000, cycleTicks: 3840))      // a jump or a tempo-sync edge started a new one early
        XCTAssertEqual(tape.passes().map { $0.complete }, [false, false])
    }

    func testSegmentExactlyOnAPassBoundaryDoesNotBreakIt() {
        let tape = SessionTape(chunkEvents: 8, poolSize: 4)
        tape.writer.append(.pass(tick: 0, cycleTicks: 3840))
        tape.writer.append(.segment(tick: 3840, starting: false))
        tape.writer.append(.segment(tick: 3840, starting: true))
        tape.writer.append(.pass(tick: 3840, cycleTicks: 3840))
        XCTAssertEqual(tape.passes().first?.complete, true)
    }

    func testMarkersSurviveChunkBoundaries() {
        let tape = SessionTape(chunkEvents: 3, poolSize: 32)
        for p in 0..<20 {
            tape.writer.append(.pass(tick: UInt32(p * 3840), cycleTicks: 3840))
            tape.writer.append(note(p, tick: p * 3840 + 5))
            tape.writer.append(.tempo(tick: UInt32(p * 3840), bpm: 100 + Double(p)))
            if p % 4 == 0 { tape.drain() }
        }
        let ps = tape.passes()
        XCTAssertEqual(ps.count, 20)
        XCTAssertEqual(ps.dropLast().map { $0.complete }, Array(repeating: true, count: 19))
        XCTAssertEqual(tape.bpm(at: 7 * 3840 + 1), 107, accuracy: 0.005)
        XCTAssertEqual(tape.tempoChanges.count, 20)
    }

    // MARK: two threads

    func testProducerAndConsumerOnTwoThreads() {
        // The render thread appends flat out while the main thread drains, indexes and reads. A reader may fall behind and the writer then
        // drops (and counts) — but nothing it kept may be torn, repeated or reordered, and every append is accounted for.
        let total = 120_000
        let tape = SessionTape(chunkEvents: 64, poolSize: 8)
        let done = DispatchSemaphore(value: 0)
        let producer = Thread {
            for i in 0..<total {
                tape.writer.append(.note(tick: UInt32(i), on: i % 2 == 0, note: UInt8(i % 100 + 20), vel: UInt8(i % 100 + 20), cable: i % 5, lane: nil, channel: UInt8(i % 16)))
                if i % 4096 == 4095 { usleep(200) }       // a render callback's gaps
            }
            done.signal()
        }
        producer.start()
        var reads = 0
        while done.wait(timeout: .now() + .microseconds(300)) == .timedOut {
            tape.drain()
            if reads % 8 == 0 {
                let got = tape.events(from: 0, to: Int.max)
                var last = -1
                for e in got {
                    let i = Int(e.tick)
                    XCTAssertGreaterThan(i, last, "in order, no repeats")
                    last = i
                    XCTAssertEqual(e.note, UInt8(i % 100 + 20) & 0x7F)
                    XCTAssertEqual(e.isOn, i % 2 == 0)
                    XCTAssertEqual(e.cable, i % 5)
                }
            }
            reads += 1
        }
        tape.drain()
        XCTAssertEqual(tape.eventCount + tape.droppedEvents, total, "every append is either kept or counted as dropped")
        let got = tape.events(from: 0, to: Int.max)
        XCTAssertEqual(got.count, tape.eventCount)
        var last = -1
        for e in got {
            let i = Int(e.tick)
            XCTAssertGreaterThan(i, last)
            last = i
            XCTAssertEqual(e.note, UInt8(i % 100 + 20) & 0x7F)
            XCTAssertEqual(e.vel, i % 2 == 0 ? UInt8(i % 100 + 20) & 0x7F : 0)
        }
    }

    // MARK: channel-voice messages

    func testMessagesRoundTripToTheSameWireBytes() {
        let cases: [(UInt8, UInt8, UInt8)] = [(0x90, 60, 100), (0x93, 127, 1), (0x80, 60, 0), (0x8F, 0, 0), (0xB0, 74, 127), (0xB5, 1, 0), (0xE0, 0, 64), (0xE2, 127, 127)]
        for (st, a, b) in cases {
            for cable in 0...4 {
                let e = TapeEvent.message(tick: 9, status: st, d1: a, d2: b, cable: cable, lane: 2)!
                XCTAssertEqual(e.wire.status, st); XCTAssertEqual(e.wire.d1, a); XCTAssertEqual(e.wire.d2, b)
                XCTAssertEqual(e.cable, cable); XCTAssertEqual(e.lane, 2); XCTAssertEqual(e.channel, st & 0x0F)
            }
        }
    }
    func testNoteOnWithVelocityZeroIsANoteOff() {
        let e = TapeEvent.message(tick: 1, status: 0x91, d1: 60, d2: 0, cable: 1, lane: nil)!
        XCTAssertFalse(e.isOn); XCTAssertEqual(e.kind, .note); XCTAssertEqual(e.wire.status, 0x81); XCTAssertEqual(e.wire.d2, 0)
    }
    func testControlMessagesAreControlNotNotes() {
        XCTAssertEqual(TapeEvent.message(tick: 1, status: 0xB0, d1: 74, d2: 9, cable: 0, lane: nil)?.kind, .control)
        XCTAssertEqual(TapeEvent.message(tick: 1, status: 0xE0, d1: 0, d2: 64, cable: 0, lane: nil)?.isPitchBend, true)
        XCTAssertNil(TapeEvent.message(tick: 1, status: 0xC0, d1: 5, d2: 0, cable: 0, lane: nil), "program change is not something the engine sends, and not something the tape keeps")
        XCTAssertNil(TapeEvent.message(tick: 1, status: 0xF8, d1: 0, d2: 0, cable: 0, lane: nil))
    }

    // MARK: the recorder (session clock)

    private func recorder(chunk: Int = 256, pool: Int = 16) -> (SessionTape, TapeRecorder) {
        let t = SessionTape(chunkEvents: chunk, poolSize: pool)
        return (t, TapeRecorder(writer: t.writer))
    }
    /// 120 BPM at 48 kHz: 24 000 samples a beat. A 512-frame window = 0.021333 beats.
    private let bps = 120.0 / 60.0 / 48_000.0
    private func window(_ r: TapeRecorder, playing: Bool = true, beat: Double, frames: Int = 512, tempo: Double = 120, cycle: Double = 4) {
        r.beginWindow(playing: playing, beatPos: beat, windowBeats: Double(frames) * bps, tempo: tempo, cycleBeats: cycle, sampleStart: Int64((beat / bps).rounded()), beatsPerSample: bps)
    }
    private func note(_ r: TapeRecorder, atBeat b: Double, on: Bool = true, cable: UInt8 = 1, key: UInt8 = 60, lane: Int = -1) {
        r.record(sampleTime: Int64((b / bps).rounded()), cable: cable, on ? 0x90 : 0x80, key, on ? 100 : 0, lane: lane)
    }

    func testRecorderFilesAStartSegmentTempoAndPassMarker() {
        let (tape, rec) = recorder()
        window(rec, beat: 0)
        let all = tape.events(from: 0, to: 10, kinds: [.segment, .tempo, .pass])
        XCTAssertEqual(all.map { $0.kind }, [.segment, .tempo, .pass])
        XCTAssertTrue(all[0].isSegmentStart)
        XCTAssertEqual(all[1].bpm, 120, accuracy: 0.005)
        XCTAssertEqual(all[2].cycleTicks, 3840)
    }
    func testRecorderMapsBeatsToTicks() {
        let (tape, rec) = recorder()
        window(rec, beat: 0)
        note(rec, atBeat: 0.0)
        note(rec, atBeat: 0.01)
        let n = tape.events(from: 0, to: 100).map { Int($0.tick) }
        XCTAssertEqual(n, [0, 10], "960 ticks a beat")
    }
    func testNothingIsRecordedWhileTheTransportIsStopped() {
        let (tape, rec) = recorder()
        window(rec, playing: false, beat: 0)
        note(rec, atBeat: 0.0)
        XCTAssertEqual(tape.eventCount, 0)
    }
    func testASecondRunContinuesFromWhereTheFirstEnded() {
        let (tape, rec) = recorder()
        var beat = 0.0
        let wb = 512 * bps
        for _ in 0..<94 { window(rec, beat: beat); beat += wb }           // ≈ 2 beats
        let ended = Int((beat * 960).rounded())
        window(rec, playing: false, beat: beat)                               // stop
        window(rec, beat: 40)                                                 // play again somewhere else on the host's timeline
        note(rec, atBeat: 40)
        let segs = tape.events(from: 0, to: Int.max, kinds: [.segment])
        XCTAssertEqual(segs.map { $0.isSegmentStart }, [true, false, true])
        XCTAssertEqual(Int(segs[1].tick), ended, accuracy: 1)
        XCTAssertEqual(segs[2].tick, segs[1].tick, "no gap on the tape for a stop of any length")
        XCTAssertEqual(Int(tape.events(from: 0, to: Int.max).last!.tick), Int(segs[2].tick), "the new run's first note is at its start")
    }
    func testABeatJumpClosesTheRunAndOpensANewOne() {
        let (tape, rec) = recorder()
        var beat = 0.0
        let wb = 512 * bps
        for _ in 0..<10 { window(rec, beat: beat); beat += wb }
        window(rec, beat: 1.0)                                                // a locate back to bar 1 beat 2 — nothing like the next window
        XCTAssertEqual(tape.events(from: 0, to: Int.max, kinds: [.segment]).map { $0.isSegmentStart }, [true, false, true])
    }
    func testContinuousWindowsMakeOneRun() {
        let (tape, rec) = recorder()
        var beat = 3.0
        let wb = 512 * bps
        for _ in 0..<500 { window(rec, beat: beat); beat += wb }
        XCTAssertEqual(tape.events(from: 0, to: Int.max, kinds: [.segment]).count, 1)
    }
    func testPassMarkersLandOnTheBoundaryAndFlagPartialFirstPass() {
        let (tape, rec) = recorder(chunk: 4096)
        var beat = 2.0                                                        // the run starts half way through pass 0
        let wb = 512 * bps
        while beat < 13 { window(rec, beat: beat); beat += wb }
        let ps = tape.passes()
        XCTAssertEqual(ps.map { $0.startTick }, [0, 1920, 5760, 9600], "the first marker is where the run began, then every 4 beats = 3840 ticks")
        XCTAssertEqual(ps.map { $0.complete }, [false, true, true, false], "the first pass was only half played; the last is still running")
    }
    func testPassBoundaryTickIsExactEvenThoughWindowsDoNotLandOnIt() {
        let (tape, rec) = recorder()
        var beat = 0.0
        let wb = 512 * bps
        while beat < 9 { window(rec, beat: beat); beat += wb }
        XCTAssertEqual(tape.passes().map { $0.startTick }, [0, 3840, 7680])
    }
    func testTempoChangesAreFiledAndRampsAreThinned() {
        let (tape, rec) = recorder(chunk: 4096)
        var beat = 0.0
        let wb = 512 * bps
        for i in 0..<400 { window(rec, beat: beat, tempo: 120 + Double(i) * 0.05); beat += wb }      // a slow ramp, a new hundredth almost every window
        tape.drain()
        let t = tape.tempoChanges
        XCTAssertGreaterThan(t.count, 2)
        XCTAssertLessThan(t.count, 200, "not one marker per window")
        for (a, b) in zip(t, t.dropFirst()) { XCTAssertGreaterThanOrEqual(b.tick - a.tick, TapeRecorder.minTempoGapTicks) }
        XCTAssertEqual(tape.bpm(at: 0), 120, accuracy: 0.01)
        XCTAssertGreaterThan(tape.bpm(at: Int.max / 2), 130)
    }
    func testStopWindowKeepsTheFlushOffsAtTheStopTick() {
        let (tape, rec) = recorder()
        var beat = 0.0
        let wb = 512 * bps
        for _ in 0..<50 { window(rec, beat: beat); beat += wb }
        note(rec, atBeat: beat - 0.001, on: true)
        window(rec, playing: false, beat: beat)
        rec.record(sampleTime: renderSampleImmediate, cable: 1, 0x80, 60, 0, lane: -1)         // the Router's stop flush
        window(rec, playing: false, beat: beat)
        rec.record(sampleTime: 0, cable: 1, 0x80, 61, 0, lane: -1)                               // nothing is recorded in later stopped windows
        let n = tape.events(from: 0, to: Int.max)
        XCTAssertEqual(n.map { $0.isOn }, [true, false])
        let seg = tape.events(from: 0, to: Int.max, kinds: [.segment]).last!
        XCTAssertFalse(seg.isSegmentStart)
        XCTAssertEqual(n[1].tick, seg.tick, "the flush note-off sits exactly on the stop")
    }
    func testAnImmediateTimeIsFiledAtTheWindowStart() {
        let (tape, rec) = recorder()
        var beat = 0.0
        while beat < 1.0 { window(rec, beat: beat); beat += 512 * bps }
        rec.record(sampleTime: renderSampleImmediate, cable: 0, 0xB0, 123, 0, lane: -1)
        XCTAssertEqual(Int(tape.events(from: 0, to: Int.max, kinds: [.control]).first!.tick), Int(((beat - 512 * bps) * 960).rounded()))
    }
    func testANoteOffTakesTheLaneOfItsNoteOn() {
        let (tape, rec) = recorder()
        window(rec, beat: 0)
        note(rec, atBeat: 0.0, on: true, cable: 1, key: 60, lane: 2)
        note(rec, atBeat: 0.0, on: true, cable: 0, key: 60, lane: 2)
        note(rec, atBeat: 0.0, on: true, cable: 1, key: 64, lane: 0)
        note(rec, atBeat: 0.25, on: false, cable: 1, key: 60)
        note(rec, atBeat: 0.25, on: false, cable: 0, key: 60)
        note(rec, atBeat: 0.5, on: false, cable: 1, key: 64)
        let n = tape.events(from: 0, to: Int.max)
        XCTAssertEqual(n.map { $0.lane }, [2, 2, 0, 2, 2, 0])
    }
    func testACCOnAnyCableIsRecordedAsControl() {
        let (tape, rec) = recorder()
        window(rec, beat: 0)
        rec.record(sampleTime: 1000, cable: 0, 0xB2, 74, 99, lane: -1)
        let c = tape.events(from: 0, to: Int.max, kinds: [.control])
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].wire.status, 0xB2); XCTAssertEqual(c[0].wire.d1, 74); XCTAssertEqual(c[0].wire.d2, 99); XCTAssertEqual(c[0].cable, 0)
    }
}
