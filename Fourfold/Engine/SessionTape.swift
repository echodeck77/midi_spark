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

/// One recorded record, 8 bytes — everything the output sent: channel-voice messages (note on/off, CC, pitch bend) exactly as the `ReelDeck` holds them, on cables 0–4 (0 = ALL, 1–4 = A–D), plus
/// three markers (tempo, pass start, transport segment). `tick` is session time (`SessionTape.ppq` per beat).
/// meta: bits 0-2 type · bits 3-4 lane (0…3) · bit 5 lane known.   aux: bits 0-3 MIDI channel · bits 4-6 cable (0…4) — for a segment marker bit 0 = starting.
struct TapeEvent: Equatable {
    var tick: UInt32
    var d1: UInt8
    var d2: UInt8
    var meta: UInt8
    var aux: UInt8

    enum Kind: UInt8 { case note, control, tempo, pass, segment }
    private enum T: UInt8 { case noteOff = 0, noteOn, controlChange, pitchBend, tempo, pass, segment }
    private var type: T { T(rawValue: meta & 0x07) ?? .noteOff }
    var kind: Kind {
        switch type {
        case .noteOff, .noteOn: return .note
        case .controlChange, .pitchBend: return .control
        case .tempo: return .tempo
        case .pass: return .pass
        case .segment: return .segment
        }
    }
    var isNote: Bool { kind == .note }
    var isOn: Bool { type == .noteOn }
    var isPitchBend: Bool { type == .pitchBend }
    /// 0 = the ALL cable, 1–4 = outputs A–D.
    var cable: Int { Int((aux >> 4) & 0x07) }
    /// 0…3 for A–D; nil for the ALL cable.
    var output: Int? { cable >= 1 && cable <= 4 ? cable - 1 : nil }
    var lane: Int? { meta & 0x20 != 0 ? Int((meta >> 3) & 0x03) : nil }
    var channel: UInt8 { aux & 0x0F }
    var note: UInt8 { d1 }
    var vel: UInt8 { d2 }
    private var payload16: Int { Int(d1) << 8 | Int(d2) }
    /// The three wire bytes of a channel-voice record (a note-off always carries release velocity 0, as the Router sends it).
    var wire: (status: UInt8, d1: UInt8, d2: UInt8) {
        switch type {
        case .noteOff: return (0x80 | channel, d1, 0)
        case .noteOn: return (0x90 | channel, d1, d2)
        case .controlChange: return (0xB0 | channel, d1, d2)
        case .pitchBend: return (0xE0 | channel, d1, d2)
        default: return (0, 0, 0)
        }
    }

    private static func pack(_ t: T, lane: Int?, cable: Int, channel: UInt8) -> (meta: UInt8, aux: UInt8) {
        var m = t.rawValue
        if let l = lane { m |= UInt8(max(0, min(3, l))) << 3 | 0x20 }
        return (m, (channel & 0x0F) | UInt8(max(0, min(4, cable))) << 4)
    }
    /// A raw MIDI message as the Router emitted it. Note-on with velocity 0 is a note-off. Nil for a status the tape does not keep (nothing the engine sends today).
    static func message(tick: UInt32, status: UInt8, d1: UInt8, d2: UInt8, cable: Int, lane: Int?) -> TapeEvent? {
        let t: T
        switch status & 0xF0 {
        case 0x80: t = .noteOff
        case 0x90: t = d2 > 0 ? .noteOn : .noteOff
        case 0xB0: t = .controlChange
        case 0xE0: t = .pitchBend
        default: return nil
        }
        let p = pack(t, lane: lane, cable: cable, channel: status & 0x0F)
        return TapeEvent(tick: tick, d1: d1 & 0x7F, d2: t == .noteOff ? 0 : d2 & 0x7F, meta: p.meta, aux: p.aux)
    }
    /// A note-on (`vel` > 0) or note-off. `lane` = the Euclid lane that played it, if known.
    static func note(tick: UInt32, on: Bool, note: UInt8, vel: UInt8, cable: Int, lane: Int?, channel: UInt8) -> TapeEvent {
        message(tick: tick, status: (on ? 0x90 : 0x80) | (channel & 0x0F), d1: note, d2: on ? max(1, vel & 0x7F) : 0, cable: cable, lane: lane)!
    }
    /// A tempo change to `bpm` (stored in hundredths, so 0.01 BPM resolution up to 655 BPM).
    static func tempo(tick: UInt32, bpm: Double) -> TapeEvent {
        let v = UInt16(max(1, min(65_535, (bpm * 100).rounded())))
        return TapeEvent(tick: tick, d1: UInt8(v >> 8), d2: UInt8(v & 0xFF), meta: T.tempo.rawValue, aux: 0)
    }
    var bpm: Double { Double(payload16) / 100 }
    /// A pass starts here (the Kernel's 8-step cycle; its length in ticks is carried so the tape knows what a complete pass is).
    static func pass(tick: UInt32, cycleTicks: Int) -> TapeEvent {
        let v = UInt16(max(1, min(65_535, cycleTicks)))
        return TapeEvent(tick: tick, d1: UInt8(v >> 8), d2: UInt8(v & 0xFF), meta: T.pass.rawValue, aux: 0)
    }
    var cycleTicks: Int { payload16 }
    /// The transport started (`starting` true) or stopped / jumped here. The tape clock does not run while stopped, so a stop and the next start share a tick.
    static func segment(tick: UInt32, starting: Bool) -> TapeEvent {
        TapeEvent(tick: tick, d1: 0, d2: 0, meta: T.segment.rawValue, aux: starting ? 1 : 0)
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
    static let defaultPoolSize = 8

    let writer: TapeWriter
    let chunkEvents: Int
    private let poolSize: Int
    private let free: TapeChunkRing, full: TapeChunkRing
    private var inFlight: [UnsafeMutablePointer<TapeEvent>] = []   // chunks the writer holds or will hold, oldest first: finished-but-not-drained, then the one being written, then the pool
    private(set) var sealed: [TapeChunk] = []                       // chunks taken back, in order
    private var allocated: [UnsafeMutablePointer<TapeEvent>] = []   // everything ever allocated, for deinit
    private var indexed = 0                                         // events [0, indexed) are in the marker index below
    private var passMarkers: [(tick: Int, cycle: Int)] = []
    private var segmentTicks: [Int] = []                            // ascending: the clock never runs backwards
    private var finals: [TapePass] = []                             // passes whose end is known (the next pass has started), final the moment they are made
    var reelSignatureCache: [UInt64] = []                       // the browser's REMOVE DUPLICATES hash per filed pass (ReelTapeAdapter.swift); a whole pass never changes, so each is computed once
    private(set) var filed: [TapePass] = []                         // the whole ones among them, in order: what the reel browser lists as passes 1, 2, 3 …
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
        p.initialize(repeating: TapeEvent(tick: 0, d1: 0, d2: 0, meta: 0, aux: 0), count: chunkEvents)
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
            case .pass:
                if let m = passMarkers.last { finalize(m, end: Int(e.tick)) }
                passMarkers.append((Int(e.tick), e.cycleTicks))
            case .segment: segmentTicks.append(Int(e.tick))
            case .tempo: tempoChanges.append((Int(e.tick), e.bpm))
            case .note, .control: break
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

    /// A pass is WHOLE if it ran its full length and no stop or jump fell inside it (one at its very end, on the next pass's own tick, does not count).
    private func finalize(_ m: (tick: Int, cycle: Int), end: Int) {
        var complete = abs((end - m.tick) - m.cycle) <= 1
        if complete {
            var lo = 0, hi = segmentTicks.count                       // first segment marker after the pass start
            while lo < hi { let mid = (lo + hi) / 2; if segmentTicks[mid] > m.tick { hi = mid } else { lo = mid + 1 } }
            complete = !(lo < segmentTicks.count && segmentTicks[lo] < end)
        }
        let p = TapePass(number: finals.count, startTick: m.tick, cycleTicks: m.cycle, endTick: end, complete: complete)
        finals.append(p)
        if complete { filed.append(p) }
    }

    /// The tempo in force at `tick` (120 until the tape says otherwise).
    func bpm(at tick: Int) -> Double {
        drain()
        var lo = 0, hi = tempoChanges.count                           // the last change at or before `tick`
        while lo < hi { let mid = (lo + hi) / 2; if tempoChanges[mid].tick <= tick { lo = mid + 1 } else { hi = mid } }
        return lo == 0 ? 120.0 : tempoChanges[lo - 1].bpm
    }

    /// The passes in the order they started, each with its length and whether it ran uninterrupted. The newest (still being played) has no end yet and is never complete.
    func passes() -> [TapePass] {
        drain()
        var out = finals
        if passMarkers.count > finals.count, let m = passMarkers.last {
            out.append(TapePass(number: finals.count, startTick: m.tick, cycleTicks: m.cycle, endTick: nil, complete: false))
        }
        return out
    }
    /// The whole passes (see `filed`), after bringing the tape up to date.
    func filedPasses() -> [TapePass] { drain(); return filed }
}

/// The render-thread side of the session clock: turns what the Kernel knows each window (is the transport playing, where is the beat, what tempo, how long is a pass) into the tape's markers, and turns each emitted message
/// into a `TapeEvent` at the right session tick. Foundation-only and allocation-free after init, so the unit tests drive it exactly as the Kernel does.
///
/// THE SESSION CLOCK. Ticks (960 per beat) run only while the host transport plays. A SEGMENT is one uninterrupted run of the transport: it opens when playing begins and closes when the transport stops or the beat jumps
/// (a loop point, a locate). The next segment starts at the tick the previous one ended, so a stop of any length leaves no gap on the tape and no segment overlaps another. Within a segment a beat maps to a tick by
/// `baseTick + (beat − startBeat) × 960`.
final class TapeRecorder {
    let writer: TapeWriter
    private(set) var isOpen = false              // a segment is running
    private var baseTick = 0
    private var startBeat = 0.0
    private var endBeat = 0.0                    // where the beat should be at the start of the next window
    private var lastTick = 0                     // the tick the last window ended at (where a segment closes)
    private var lastPass = Int.min
    private var lastTempoCenti = -1
    private var lastTempoTick = 0
    private var winBase = 0.0, winBps = 0.0, winStart: Int64 = 0
    private var stopWindow = false               // the one window after a stop: the Router's flush note-offs land here
    private var stopTick = 0
    private(set) var recordedEvents = 0
    // The lane that played each sounding note, so its note-off (which the Router sends without a tag) carries the same lane: [cable 0…4][channel][note].
    private let laneOfNote: UnsafeMutablePointer<Int8>
    static let jumpToleranceBeats = 0.05         // a beat further than this (plus one window) from where the last window ended is a jump, not a continuation
    static let minTempoGapTicks = 60             // a tempo ramp files at most one marker per 1/16 beat

    init(writer: TapeWriter) {
        self.writer = writer
        laneOfNote = UnsafeMutablePointer<Int8>.allocate(capacity: 5 * 16 * 128)
        laneOfNote.initialize(repeating: -1, count: 5 * 16 * 128)
    }
    deinit { laneOfNote.deallocate() }

    private func tick(forBeat b: Double) -> Int { max(baseTick, baseTick + Int(((b - startBeat) * Double(SessionTape.ppq)).rounded())) }

    /// Call once per render window, before the Router runs. `windowBeats` is the window's length in beats; `cycleBeats` the pass length (8 steps).
    func beginWindow(playing: Bool, beatPos: Double, windowBeats: Double, tempo: Double, cycleBeats: Double, sampleStart: Int64, beatsPerSample: Double) {
        stopWindow = false
        if !playing {
            if isOpen {
                writer.append(.segment(tick: UInt32(clamping: lastTick), starting: false))
                isOpen = false; stopWindow = true; stopTick = lastTick
            }
            lastPass = Int.min
            return
        }
        if isOpen, abs(beatPos - endBeat) > TapeRecorder.jumpToleranceBeats + windowBeats {          // a loop or a locate
            writer.append(.segment(tick: UInt32(clamping: lastTick), starting: false))
            isOpen = false; lastPass = Int.min
        }
        if !isOpen {
            isOpen = true; baseTick = lastTick; startBeat = beatPos
            writer.append(.segment(tick: UInt32(clamping: baseTick), starting: true))
            lastTempoCenti = -1
        }
        let now = tick(forBeat: beatPos)
        let centi = Int((tempo * 100).rounded())
        if centi != lastTempoCenti, lastTempoCenti < 0 || now - lastTempoTick >= TapeRecorder.minTempoGapTicks {
            writer.append(.tempo(tick: UInt32(clamping: now), bpm: tempo)); lastTempoCenti = centi; lastTempoTick = now
        }
        if cycleBeats > 0 {
            let pass = Int((beatPos / max(0.0001, cycleBeats)).rounded(.down))
            if pass != lastPass {
                let boundary = max(Double(pass) * cycleBeats, startBeat)       // the first window of a run that starts mid-pass: the pass "starts" where the run does
                writer.append(.pass(tick: UInt32(clamping: tick(forBeat: boundary)), cycleTicks: Int((cycleBeats * Double(SessionTape.ppq)).rounded())))
                lastPass = pass
            }
        }
        winBase = beatPos; winBps = beatsPerSample; winStart = sampleStart
        endBeat = beatPos + windowBeats
        lastTick = tick(forBeat: endBeat)
    }

    /// File one emitted message. `lane` is the tag the Router set before a note-on (−1 = none); a note-off takes the lane its note-on had.
    @inline(__always) func record(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8, lane: Int) {
        guard isOpen || stopWindow else { return }
        let t: Int
        if isOpen {
            let off = sampleTime > winStart ? sampleTime - winStart : 0               // an "immediate" flush (a hugely negative time) lands at the window's start
            t = tick(forBeat: winBase + Double(off) * winBps)
        } else { t = stopTick }
        var laneTag = -1
        let status = b0 & 0xF0
        if status == 0x80 || status == 0x90 {
            let idx = (Int(min(cable, 4)) * 16 + Int(b0 & 0x0F)) * 128 + Int(b1 & 0x7F)
            if status == 0x90 && b2 > 0 { laneOfNote[idx] = Int8(truncatingIfNeeded: lane); laneTag = lane } else { laneTag = Int(laneOfNote[idx]) }
        }
        guard let e = TapeEvent.message(tick: UInt32(clamping: t), status: b0, d1: b1, d2: b2, cable: Int(cable), lane: laneTag >= 0 ? laneTag : nil) else { return }
        writer.append(e)
        recordedEvents &+= 1
    }
}
