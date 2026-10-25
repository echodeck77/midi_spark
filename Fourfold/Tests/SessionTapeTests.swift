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
            let out = Int.random(in: 0...3, using: &rng)
            let lane: Int? = Bool.random(using: &rng) ? Int.random(in: 0...3, using: &rng) : nil
            let ch = UInt8.random(in: 0...15, using: &rng)
            let e = TapeEvent.note(tick: tick, on: on, note: note, vel: vel, output: out, lane: lane, channel: ch)
            XCTAssertEqual(e.kind, .note)
            XCTAssertEqual(e.tick, tick)
            XCTAssertEqual(e.isOn, on)
            XCTAssertEqual(e.note, note)
            XCTAssertEqual(e.vel, on ? vel : 0, "a note-off carries no velocity")
            XCTAssertEqual(e.output, out)
            XCTAssertEqual(e.lane, lane)
            XCTAssertEqual(e.channel, ch)
        }
    }

    func testLaneZeroIsNotLaneUnknown() {
        let a = TapeEvent.note(tick: 0, on: true, note: 60, vel: 100, output: 0, lane: 0, channel: 0)
        let b = TapeEvent.note(tick: 0, on: true, note: 60, vel: 100, output: 0, lane: nil, channel: 0)
        XCTAssertEqual(a.lane, 0)
        XCTAssertNil(b.lane)
    }

    func testNoteOnVelocityIsNeverZero() {
        XCTAssertEqual(TapeEvent.note(tick: 0, on: true, note: 60, vel: 0, output: 0, lane: nil, channel: 0).vel, 1, "velocity 0 would read back as a note-off")
    }

    func testOutOfRangeFieldsAreClamped() {
        let e = TapeEvent.note(tick: 5, on: true, note: 200, vel: 255, output: 9, lane: 7, channel: 31)
        XCTAssertEqual(e.note, 200 & 0x7F)
        XCTAssertEqual(e.output, 3)
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
        .note(tick: UInt32(tick ?? i), on: i % 2 == 0, note: UInt8(i % 100 + 20), vel: UInt8(i % 100 + 20), output: i % 4, lane: i % 3 == 0 ? nil : i % 4, channel: UInt8(i % 16))
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
        let a = TapeEvent.note(tick: 500, on: false, note: 60, vel: 0, output: 0, lane: 0, channel: 0)
        let b = TapeEvent.note(tick: 500, on: true, note: 60, vel: 90, output: 0, lane: 0, channel: 0)
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
                tape.writer.append(.note(tick: UInt32(i), on: i % 2 == 0, note: UInt8(i % 100 + 20), vel: UInt8(i % 100 + 20), output: i % 4, lane: nil, channel: UInt8(i % 16)))
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
                    XCTAssertEqual(e.output, i % 4)
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
}
