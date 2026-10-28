//  NoteRollRing.swift — CARD BACKS (2026-10-28) §5: the feed behind each part's live piano roll.
//
//  The render thread pushes ONE record for every note a part strikes — including a note whose part is routed to no output (it is drawn, marked silent) — and, when a sounding note is cut before its planned end
//  (a mute, a solo, a stop, a legato hold that finally closes), one END record carrying the actual end. The main thread drains the ring from the AU's 30 Hz poll and keeps `NoteRollModel`, which the card back reads.
//
//  Why a new ring: the NOTE VIEW ring holds 8 events × 9 notes per lane with no note-off, no layer per pitch and no silent mark, and `SessionTape` records only what went out on the wire. This one is a single-producer ring
//  of 16-byte records modelled on the tape's chunk ring: the producer writes a record and then publishes the new count with a release store (no lock, no allocation); the consumer reads the count with an acquire load, copies,
//  and re-reads it — anything the producer could have overwritten meanwhile is discarded, and a consumer that falls more than a ring behind SKIPS TO THE NEWEST (the oldest are dropped, never the newest).

import Foundation
import Atomics

/// One struck note, as a part's roll draws it. 16 bytes.
struct NoteRollRecord: Equatable {
    var onBeat: Double          // the host beat the note starts on
    var length: Float           // planned length in beats; for an END record the actual length; `.infinity` while a legato hold has no end yet
    var pitch: UInt8
    var velocity: UInt8
    var part: UInt8             // 0…7: 2·lane + (notes ? 1 : 0) — the part the note LEFT from (after a HOCKET pass, the receiving part)
    var flags: UInt8            // bits 0–3: the outputs A–D it left on (0 = routed nowhere: silent) · bit 4: END record · bit 5: held (a legato note with no planned end)

    static let outsMask: UInt8 = 0x0F, endFlag: UInt8 = 0x10, heldFlag: UInt8 = 0x20
    var outs: UInt8 { flags & NoteRollRecord.outsMask }
    var isEnd: Bool { flags & NoteRollRecord.endFlag != 0 }
    var isHeld: Bool { flags & NoteRollRecord.heldFlag != 0 }
    var isSilent: Bool { outs == 0 }
}

/// Single-producer (the render thread) / single-consumer (the main thread) ring of `NoteRollRecord`s that drops the OLDEST when the consumer falls behind.
final class NoteRollRing {
    static let capacity = 4096                                       // a power of two; 2 bars of a very busy page is a few hundred
    private let mask: UInt64 = UInt64(NoteRollRing.capacity - 1)
    private let buffer: UnsafeMutablePointer<NoteRollRecord>
    private let written = ManagedAtomic<UInt64>(0)                   // records ever pushed
    private var cursor: UInt64 = 0                                   // main thread only: records already drained
    private(set) var dropped: UInt64 = 0                             // main thread only: records the consumer fell too far behind to read

    init() {
        buffer = UnsafeMutablePointer<NoteRollRecord>.allocate(capacity: NoteRollRing.capacity)
        buffer.initialize(repeating: NoteRollRecord(onBeat: 0, length: 0, pitch: 0, velocity: 0, part: 0, flags: 0), count: NoteRollRing.capacity)
    }
    deinit { buffer.deallocate() }

    /// Render thread. Never allocates, never locks.
    @inline(__always) func push(_ r: NoteRollRecord) {
        let w = written.load(ordering: .relaxed)
        buffer[Int(w & mask)] = r
        written.store(w &+ 1, ordering: .releasing)
    }

    /// Main thread. Everything pushed since the last drain, oldest first — except what the producer overwrote, which is dropped and counted.
    func drain() -> [NoteRollRecord] {
        let cap = UInt64(NoteRollRing.capacity)
        let tail = written.load(ordering: .acquiring)
        if tail <= cursor { return [] }
        // The producer starts writing record n into the slot of record n − cap BEFORE it publishes n + 1, so while `written == tail` the slot of record tail − cap may already be half-written: the consumer never trusts more than
        // cap − 1 records. A consumer that has fallen further behind than that skips to the newest cap − 1 (the oldest are dropped, never the newest).
        let safe = cap - 1
        var start = cursor
        if tail - start > safe { dropped &+= (tail - safe) - start; start = tail - safe }
        var out: [NoteRollRecord] = []
        out.reserveCapacity(Int(tail - start))
        var i = start
        while i < tail { out.append(buffer[Int(i & mask)]); i &+= 1 }
        // the producer may have lapped the slots read first while they were being copied: re-read the count and drop whatever it could have started overwriting — record i is at risk once written ≥ i + cap (those copies may be torn)
        let tail2 = written.load(ordering: .acquiring)
        if tail2 >= cap, tail2 - cap + 1 > start {
            let lost = Int(min(tail, tail2 - cap + 1) - start)
            dropped &+= UInt64(lost)
            out.removeFirst(min(lost, out.count))
        }
        cursor = tail
        return out
    }
}

/// One note as the roll draws it.
struct NoteRollNote: Equatable {
    var onBeat: Double
    var endBeat: Double?        // nil while it is still held
    var pitch: UInt8
    var velocity: UInt8
    var outs: UInt8             // 0 = silent (the part is routed nowhere)
}

/// Main-thread state behind the card backs: each part's recent notes. Pure — fed with drained records, read with a beat window.
struct NoteRollModel: Equatable {
    static let perPartCap = 768
    private(set) var parts: [[NoteRollNote]] = Array(repeating: [], count: 8)
    /// The newest strike per part, as a host beat.
    private(set) var lastOnBeat: [Double] = Array(repeating: -.infinity, count: 8)
    /// The newest strike per part and OUTPUT (A–D = 0…3), as a host beat — the jacks' activity lights read it (a part routed nowhere never lights one).
    private(set) var lastOnBeatByOutput: [[Double]] = Array(repeating: Array(repeating: -.infinity, count: 4), count: 8)

    mutating func ingest(_ records: [NoteRollRecord]) {
        for r in records {
            let p = Int(r.part & 7)
            if r.isEnd {
                // close the open note this record names: same part, same pitch, same start (an END record repeats the start it closes)
                if let i = parts[p].lastIndex(where: { $0.pitch == r.pitch && abs($0.onBeat - r.onBeat) < 1e-6 }) { parts[p][i].endBeat = r.onBeat + Double(r.length) }
                continue
            }
            parts[p].append(NoteRollNote(onBeat: r.onBeat, endBeat: r.isHeld || !r.length.isFinite ? nil : r.onBeat + Double(r.length), pitch: r.pitch, velocity: r.velocity, outs: r.outs))
            if parts[p].count > NoteRollModel.perPartCap { parts[p].removeFirst(parts[p].count - NoteRollModel.perPartCap) }
            lastOnBeat[p] = max(lastOnBeat[p], r.onBeat)
            for o in 0..<4 where r.outs & (1 << UInt8(o)) != 0 { lastOnBeatByOutput[p][o] = max(lastOnBeatByOutput[p][o], r.onBeat) }
        }
    }
    /// Notes of a part that touch the beat window [from, to) — a held note counts until `now`.
    func notes(part: Int, from: Double, to: Double, now: Double) -> [NoteRollNote] {
        guard part >= 0, part < 8 else { return [] }
        return parts[part].filter { $0.onBeat < to && ($0.endBeat ?? max(now, $0.onBeat)) > from }
    }
    /// Forget everything (the transport started again, or jumped back).
    mutating func clear() {
        for i in parts.indices { parts[i].removeAll(keepingCapacity: true) }
        lastOnBeat = Array(repeating: -.infinity, count: 8); lastOnBeatByOutput = Array(repeating: Array(repeating: -.infinity, count: 4), count: 8)
    }
    /// Drop notes that ended before `beat` (the window moved on).
    mutating func prune(before beat: Double) {
        for i in parts.indices { parts[i].removeAll { ($0.endBeat ?? .infinity) < beat } }
    }
    /// Notes still held (no end yet) — a stop must leave none.
    var openCount: Int { parts.reduce(0) { $0 + $1.filter { $0.endBeat == nil }.count } }
}
