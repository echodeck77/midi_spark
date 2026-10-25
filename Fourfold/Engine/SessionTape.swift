//  SessionTape.swift — REEL PHASE 1 (2026-10-25, Docs/reel-redesign-plan.md): the whole-session recorder.
//
//  Today's reel keeps the newest 64 passes in a ring (`ReelDeck`). This keeps EVERYTHING played since the first play: an append-only stream of 8-byte records in chunks, on a session clock of 1/960 beat that
//  only runs while the transport plays. Two sides, kept strictly apart:
//   • the AUDIO THREAD side (`TapeWriter`) only appends into a chunk it already owns; when the chunk is full it hands it back and takes a fresh one from a pool. It never allocates and never locks: the pool is two
//     single-producer/single-consumer rings of pointers (swift-atomics). If the pool is ever empty (the main thread stalled) the event is counted and dropped — it does not wait and does not allocate.
//   • the MAIN THREAD side (`SessionTape`) allocates chunks, keeps the pool topped up, takes sealed chunks back, and answers every question about what was played (events in a time range, the pass index, the tempo map).
//  The two sides share ONE atomic word, `published`: (chunks the writer has finished) << 32 | (events in the chunk it is writing). The reader loads it once and gets a consistent picture — events are numbered by one running
//  index, event i living in chunk i / chunkEvents at offset i % chunkEvents.
//  Foundation + Atomics only, so the unit-test target compiles it.

import Foundation
import Atomics

/// One recorded record, 8 bytes. `tick` is session time (`SessionTape.ppq` per beat). `meta`: bits 0-1 output (0…3 = A…D) · bit 2 note-on · bits 3-4 lane (0…3) · bit 5 lane known · bits 6-7 kind.
struct TapeEvent: Equatable {
    var tick: UInt32
    var note: UInt8
    var vel: UInt8
    var meta: UInt8
    var aux: UInt8

    enum Kind: UInt8 { case note = 0, tempo = 1, pass = 2, segment = 3 }
    var kind: Kind { Kind(rawValue: meta >> 6) ?? .note }
    var isOn: Bool { meta & 0x04 != 0 }
    var output: Int { Int(meta & 0x03) }
    var lane: Int? { meta & 0x20 != 0 ? Int((meta >> 3) & 0x03) : nil }
    var channel: UInt8 { aux & 0x0F }
    private var payload16: Int { Int(note) << 8 | Int(vel) }

    /// A note-on (`vel` > 0) or note-off on one output. `lane` = the Euclid lane that played it, if known.
    static func note(tick: UInt32, on: Bool, note: UInt8, vel: UInt8, output: Int, lane: Int?, channel: UInt8) -> TapeEvent {
        var m = UInt8(max(0, min(3, output)))
        if on { m |= 0x04 }
        if let l = lane { m |= UInt8(max(0, min(3, l))) << 3 | 0x20 }
        return TapeEvent(tick: tick, note: note & 0x7F, vel: on ? max(1, vel & 0x7F) : 0, meta: m, aux: channel & 0x0F)
    }
    /// A tempo change to `bpm` (stored in hundredths, so 0.01 BPM resolution up to 655 BPM).
    static func tempo(tick: UInt32, bpm: Double) -> TapeEvent {
        let v = UInt16(max(1, min(65_535, (bpm * 100).rounded())))
        return TapeEvent(tick: tick, note: UInt8(v >> 8), vel: UInt8(v & 0xFF), meta: TapeEvent.Kind.tempo.rawValue << 6, aux: 0)
    }
    var bpm: Double { Double(payload16) / 100 }
    /// A pass starts here (the Kernel's 8-step cycle; its length in ticks is carried so the tape knows what a complete pass is).
    static func pass(tick: UInt32, cycleTicks: Int) -> TapeEvent {
        let v = UInt16(max(1, min(65_535, cycleTicks)))
        return TapeEvent(tick: tick, note: UInt8(v >> 8), vel: UInt8(v & 0xFF), meta: TapeEvent.Kind.pass.rawValue << 6, aux: 0)
    }
    var cycleTicks: Int { payload16 }
    /// The transport started (`starting` true) or stopped / jumped here. The tape clock does not run while stopped, so a stop and the next start share a tick.
    static func segment(tick: UInt32, starting: Bool) -> TapeEvent {
        TapeEvent(tick: tick, note: 0, vel: 0, meta: TapeEvent.Kind.segment.rawValue << 6, aux: starting ? 1 : 0)
    }
    var isSegmentStart: Bool { aux & 1 != 0 }
}

/// A single-producer / single-consumer ring of chunk pointers. Fixed capacity (a power of two); no allocation after init; one side only ever pushes, the other only ever pops.
final class TapeChunkRing {
    private let capacity: Int, mask: Int
    private let slots: UnsafeMutablePointer<UnsafeMutablePointer<TapeEvent>?>
    private let head = ManagedAtomic<Int>(0)   // next slot to pop (written by the consumer)
    private let tail = ManagedAtomic<Int>(0)   // next slot to push (written by the producer)
    init(capacity: Int) {
        precondition(capacity > 1 && capacity & (capacity - 1) == 0, "a power of two")
        self.capacity = capacity; mask = capacity - 1
        slots = UnsafeMutablePointer<UnsafeMutablePointer<TapeEvent>?>.allocate(capacity: capacity)
        slots.initialize(repeating: nil, count: capacity)
    }
    deinit { slots.deallocate() }
    /// Producer side. False if the ring is full.
    @inline(__always) func push(_ p: UnsafeMutablePointer<TapeEvent>) -> Bool {
        let t = tail.load(ordering: .relaxed), h = head.load(ordering: .acquiring)
        if t - h >= capacity { return false }
        slots[t & mask] = p
        tail.store(t + 1, ordering: .releasing)
        return true
    }
    /// Consumer side. Nil if the ring is empty.
    @inline(__always) func pop() -> UnsafeMutablePointer<TapeEvent>? {
        let h = head.load(ordering: .relaxed), t = tail.load(ordering: .acquiring)
        if h == t { return nil }
        let p = slots[h & mask]
        head.store(h + 1, ordering: .releasing)
        return p
    }
    var count: Int { tail.load(ordering: .acquiring) - head.load(ordering: .acquiring) }
}

/// The audio-thread side of the tape. `append` is the only thing the render thread calls.
final class TapeWriter {
    fileprivate let free: TapeChunkRing      // main → audio: empty chunks
    fileprivate let full: TapeChunkRing      // audio → main: chunks that are full
    fileprivate let chunkEvents: Int
    private var cur: UnsafeMutablePointer<TapeEvent>?
    private var n = 0
    private var gen = 0                      // chunks this writer has finished
    fileprivate let published = ManagedAtomic<UInt64>(0)      // gen << 32 | events written into the current chunk (release/acquire with the reader)
    fileprivate let dropped = ManagedAtomic<Int>(0)

    fileprivate init(free: TapeChunkRing, full: TapeChunkRing, chunkEvents: Int) { self.free = free; self.full = full; self.chunkEvents = chunkEvents }
    fileprivate func adopt(_ first: UnsafeMutablePointer<TapeEvent>) { cur = first; n = 0; gen = 0; published.store(0, ordering: .releasing) }

    /// Append one record. Never allocates, never waits: with no chunk to write into the record is counted as dropped.
    @inline(__always) func append(_ e: TapeEvent) {
        if cur == nil {
            guard let c = free.pop() else { dropped.wrappingIncrement(ordering: .relaxed); return }
            cur = c; n = 0
        }
        cur![n] = e
        n += 1
        if n == chunkEvents {                          // full: hand it back (one atomic word says "gen+1 chunks done, none started"), and try for a fresh one right away
            _ = full.push(cur!)
            gen += 1; n = 0; cur = free.pop()
        }
        published.store(UInt64(gen) << 32 | UInt64(n), ordering: .releasing)
    }
    var droppedEvents: Int { dropped.load(ordering: .relaxed) }
}

/// A chunk handed back by the writer: all `chunkEvents` records are valid and will never change.
struct TapeChunk {
    let base: UnsafeMutablePointer<TapeEvent>
    let minTick: UInt32
    let maxTick: UInt32
}

/// One pass the tape knows about: where it starts, how long a complete one is, and whether it ran its whole length uninterrupted.
struct TapePass: Equatable {
    var number: Int            // 0-based, in the order the passes started
    var startTick: Int
    var cycleTicks: Int
    var endTick: Int?          // where the next pass started (nil while this one is still being played)
    var complete: Bool         // it ran its whole length without the transport stopping or jumping
}

/// The main-thread side: owns the memory, keeps the writer supplied, and answers questions about what was played. Not thread-safe by itself — call it from the main thread (or one test thread).
final class SessionTape {
    static let ppq = 960
    static let defaultChunkEvents = 8192          // 64 KiB
    static let defaultPoolSize = 4

    let writer: TapeWriter
    let chunkEvents: Int
    private let poolSize: Int
    private let free: TapeChunkRing, full: TapeChunkRing
    private var inFlight: [UnsafeMutablePointer<TapeEvent>] = []   // chunks the writer holds or will hold, oldest first: finished-but-not-drained, then the one being written, then the pool
    private(set) var sealed: [TapeChunk] = []                       // chunks taken back, in order
    private var allocated: [UnsafeMutablePointer<TapeEvent>] = []   // everything ever allocated, for deinit
    private var indexed = 0                                         // events [0, indexed) are in the marker index below
    private var passMarkers: [(tick: Int, cycle: Int)] = []
    private var segmentTicks: [Int] = []
    private(set) var tempoChanges: [(tick: Int, bpm: Double)] = []
    private var lastTick = 0

    init(chunkEvents: Int = SessionTape.defaultChunkEvents, poolSize: Int = SessionTape.defaultPoolSize) {
        precondition(chunkEvents >= 2 && poolSize >= 1)
        self.chunkEvents = chunkEvents; self.poolSize = poolSize
        var cap = 2; while cap < poolSize + 4 { cap *= 2 }
        free = TapeChunkRing(capacity: cap); full = TapeChunkRing(capacity: cap)
        writer = TapeWriter(free: free, full: full, chunkEvents: chunkEvents)
        let first = newChunk()
        inFlight.append(first); writer.adopt(first)
        topUp()
    }
    deinit { allocated.forEach { $0.deallocate() } }

    private func newChunk() -> UnsafeMutablePointer<TapeEvent> {
        let p = UnsafeMutablePointer<TapeEvent>.allocate(capacity: chunkEvents)
        p.initialize(repeating: TapeEvent(tick: 0, note: 0, vel: 0, meta: 0, aux: 0), count: chunkEvents)
        allocated.append(p)
        return p
    }
    private func topUp() {
        while free.count < poolSize {
            let c = newChunk()
            guard free.push(c) else { break }
            inFlight.append(c)
        }
    }

    /// Main thread: take back the chunks the writer filled, refill the pool, and index what arrived. Call this from the UI's poll (a few times a second); every reading call also does it.
    func drain() {
        while let p = full.pop() {
            guard let first = inFlight.first, first == p else { assertionFailure("chunks come back in the order they were handed out"); continue }
            inFlight.removeFirst()
            var lo = UInt32.max, hi: UInt32 = 0
            for i in 0..<chunkEvents { let t = p[i].tick; if t < lo { lo = t }; if t > hi { hi = t } }
            sealed.append(TapeChunk(base: p, minTick: lo, maxTick: hi))
        }
        topUp()
        index()
    }

    /// One consistent snapshot of how much the writer has published: (total events, chunks the writer has finished).
    private func published() -> (total: Int, finished: Int) {
        let p = writer.published.load(ordering: .acquiring)
        let gen = Int(p >> 32), n = Int(p & 0xFFFF_FFFF)
        return (gen * chunkEvents + n, gen)
    }
    private func chunkBase(_ c: Int) -> UnsafeMutablePointer<TapeEvent>? {
        if c < sealed.count { return sealed[c].base }
        let k = c - sealed.count
        return k < inFlight.count ? inFlight[k] : nil
    }
    /// Visit events [start, end) in the order they were appended.
    private func forEachEvent(from start: Int, to end: Int, _ body: (TapeEvent) -> Void) {
        var i = start
        while i < end {
            let c = i / chunkEvents, o = i % chunkEvents
            guard let b = chunkBase(c) else { return }
            let stop = min(end, (c + 1) * chunkEvents)
            for j in 0..<(stop - i) { body(b[o + j]) }
            i = stop
        }
    }

    private func index() {
        let total = published().total
        guard total > indexed else { return }
        forEachEvent(from: indexed, to: total) { e in
            switch e.kind {
            case .pass: passMarkers.append((Int(e.tick), e.cycleTicks))
            case .segment: segmentTicks.append(Int(e.tick))
            case .tempo: tempoChanges.append((Int(e.tick), e.bpm))
            case .note: break
            }
            lastTick = max(lastTick, Int(e.tick))
        }
        indexed = total
    }

    // MARK: reading

    var eventCount: Int { published().total }
    var droppedEvents: Int { writer.droppedEvents }
    var residentBytes: Int { allocated.count * chunkEvents * MemoryLayout<TapeEvent>.stride }
    /// Where the tape ends, in ticks (the latest record seen so far).
    func endTick() -> Int { drain(); return lastTick }

    /// The records with `lo <= tick < hi`, of the given kinds, in time order (records with the same tick keep the order they were appended in).
    func events(from lo: Int, to hi: Int, kinds: Set<TapeEvent.Kind> = [.note]) -> [TapeEvent] {
        drain()
        let total = published().total
        var out: [(e: TapeEvent, seq: Int)] = []
        var c = 0
        while c * chunkEvents < total {
            let startIdx = c * chunkEvents, count = min(chunkEvents, total - startIdx)
            if c < sealed.count, Int(sealed[c].maxTick) < lo || Int(sealed[c].minTick) >= hi { c += 1; continue }   // a sealed chunk that cannot hold anything in range
            if let b = chunkBase(c) {
                for j in 0..<count {
                    let e = b[j], t = Int(e.tick)
                    if t >= lo && t < hi && kinds.contains(e.kind) { out.append((e, startIdx + j)) }
                }
            }
            c += 1
        }
        out.sort { $0.e.tick != $1.e.tick ? $0.e.tick < $1.e.tick : $0.seq < $1.seq }
        return out.map { $0.e }
    }

    /// The tempo in force at `tick` (120 until the tape says otherwise).
    func bpm(at tick: Int) -> Double {
        drain()
        var b = 120.0
        for t in tempoChanges { if t.tick <= tick { b = t.bpm } else { break } }
        return b
    }

    /// The passes in the order they started, each with its length and whether it ran uninterrupted. The newest (still being played) has no end yet and is never complete.
    func passes() -> [TapePass] {
        drain()
        var out: [TapePass] = []
        for (i, m) in passMarkers.enumerated() {
            let end = i + 1 < passMarkers.count ? passMarkers[i + 1].tick : nil
            var complete = false
            if let e = end, abs((e - m.tick) - m.cycle) <= 1 {
                complete = !segmentTicks.contains { $0 > m.tick && $0 < e }   // a stop or jump inside the pass breaks it (one at the very end, on the next pass's own tick, does not)
            }
            out.append(TapePass(number: i, startTick: m.tick, cycleTicks: m.cycle, endTick: end, complete: complete))
        }
        return out
    }
}
