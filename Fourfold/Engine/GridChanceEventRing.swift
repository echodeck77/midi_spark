//  GridChanceEventRing.swift — GRID CHANCE amendment 2 (2026-11-24) §1: the feed behind the % toggle's live cells.
//
//  Each chance roll under 100 (ferry §2.1–§2.3) emits ONE event — grid, the axis it rolled on, the axis index, and whether it FIRED or DROPPED — to the UI, so the toggle can flash the cell solid (fired) or hollow (dropped).
//  A DROPPED roll strikes no note, so it has no `NoteRollRing` record and the NOTE-VIEW ring (strikes only) can't carry it either: this is a dedicated ring. Same single-producer (render) / single-consumer (main) seqlock as `NoteRollRing`,
//  pre-allocated, lock-free, allocation-free on the render thread; the main thread drains it on the AU's 30 Hz poll (§1.4: a closed UI / full ring just drops the oldest). Rolls at 100 emit nothing (§1.2) — the Router pushes only when the set axis's value < 100.

import Foundation
import Atomics

/// One chance roll, as the toggle flashes it. `onBeat` is the hit's musical beat (`mTickBeat` — what the strike / comet / NOTE-VIEW use), stamped to the display clock at ingest the way the PULSE feed stamps a strike, so a flash lines up with what's heard (§1.3).
struct GridChanceEvent: Equatable {
    var onBeat: Double
    var grid: UInt8     // 0 = riff, 1 = stack
    var axis: UInt8     // 0 = rank, 1 = the other axis (riff column / stack lane)
    var index: UInt8    // zero-based axis coordinate: rank − 1, or column / lane (0-based)
    var fired: Bool     // the roll's result (= the engine gate), by construction identical to it
}

/// Single-producer (render) / single-consumer (main) ring of `GridChanceEvent`s that drops the OLDEST when the consumer falls behind. A copy of `NoteRollRing`'s seqlock.
final class GridChanceEventRing {
    static let capacity = 1024                                       // a power of two; chance events are low-rate (only a hit on a < 100 axis)
    private let mask: UInt64 = UInt64(GridChanceEventRing.capacity - 1)
    private let buffer: UnsafeMutablePointer<GridChanceEvent>
    private let written = ManagedAtomic<UInt64>(0)
    private var cursor: UInt64 = 0
    private(set) var dropped: UInt64 = 0

    init() {
        buffer = UnsafeMutablePointer<GridChanceEvent>.allocate(capacity: GridChanceEventRing.capacity)
        buffer.initialize(repeating: GridChanceEvent(onBeat: 0, grid: 0, axis: 0, index: 0, fired: false), count: GridChanceEventRing.capacity)
    }
    deinit { buffer.deallocate() }

    /// Render thread. Never allocates, never locks.
    @inline(__always) func push(_ e: GridChanceEvent) {
        let w = written.load(ordering: .relaxed)
        buffer[Int(w & mask)] = e
        written.store(w &+ 1, ordering: .releasing)
    }

    /// Main thread. Everything pushed since the last drain, oldest first — except what the producer overwrote, which is dropped and counted. (The seqlock reader, identical to `NoteRollRing.drain`.)
    func drain() -> [GridChanceEvent] {
        let cap = UInt64(GridChanceEventRing.capacity)
        let tail = written.load(ordering: .acquiring)
        if tail <= cursor { return [] }
        let safe = cap - 1
        var start = cursor
        if tail - start > safe { dropped &+= (tail - safe) - start; start = tail - safe }
        var out: [GridChanceEvent] = []
        out.reserveCapacity(Int(tail - start))
        var i = start
        while i < tail { out.append(buffer[Int(i & mask)]); i &+= 1 }
        atomicMemoryFence(ordering: .acquiring)
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

/// Main-thread state behind the % toggle's cells: per (grid, axis, cell) the newest roll's display-clock onset + result. Pure — fed with drained events (stamped to the display clock), read with `now`. 2 grids × 2 axes × 8 cells, flat.
struct GridChanceFlashModel: Equatable {
    static let frameTol = 1.0 / 60.0           // §3.4: two events a frame apart count as "the same frame"
    private var onsetAt = [Double](repeating: -.infinity, count: 32)   // slot = grid·16 + axis·8 + cell
    private var fired   = [Bool](repeating: false, count: 32)

    @inline(__always) private static func slot(grid: Int, axis: Int, cell: Int) -> Int { grid * 16 + axis * 8 + min(7, max(0, cell)) }

    /// Ingest a drain, stamping each event's onset on the DISPLAY clock from the dejittered beat anchor (the PULSE feed's own formula, §1.3). §3.4: a later event restarts the cell with its result; a same-frame pair shows DROPPED.
    mutating func ingest(_ events: [GridChanceEvent], anchorBeat: Double, anchorAt: Double, tempo: Double) {
        let secPerBeat = 60.0 / max(1e-6, tempo)
        for e in events {
            let s = Self.slot(grid: Int(e.grid), axis: Int(e.axis), cell: Int(e.index))
            let at = anchorAt + (e.onBeat - anchorBeat) * secPerBeat
            if at > onsetAt[s] + Self.frameTol {
                onsetAt[s] = at; fired[s] = e.fired                     // a newer roll: restart with its result
            } else if abs(at - onsetAt[s]) <= Self.frameTol {
                if !e.fired { fired[s] = false }                       // same frame: DROPPED wins
                onsetAt[s] = max(onsetAt[s], at)
            }
            // an older event (at < onsetAt − tol) is ignored
        }
    }
    /// The newest roll for a cell, or nil if none — for `euclideousGridChanceCellFlash`.
    func latest(grid: Int, axis: Int, cell: Int) -> (onsetAt: Double, fired: Bool)? {
        let s = Self.slot(grid: grid, axis: axis, cell: cell)
        return onsetAt[s].isFinite ? (onsetAt[s], fired[s]) : nil
    }
    /// Forget everything (a transport restart / document load): the cells should not flash a beat that is about to come round again.
    mutating func clear() { onsetAt = [Double](repeating: -.infinity, count: 32); fired = [Bool](repeating: false, count: 32) }
}
