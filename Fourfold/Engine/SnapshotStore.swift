//  SnapshotStore.swift
//  MidiSpark — the atomic publish/acquire bridge (spec v2.8 §7).
//
//  Split from Snapshot.swift so that file stays Foundation-only and unit-testable (the store is the
//  one piece that needs swift-atomics). The render thread NEVER reads the document; it reads a
//  SnapshotBox published here by an atomic pointer swap. publish() is MAIN THREAD ONLY; acquire() is
//  one lock-free, allocation-free atomic load.

import Foundation
import Atomics   // swift-atomics via SPM — see project.yml `packages:`

final class SnapshotStore {
    private let current: ManagedAtomic<UnsafeMutableRawPointer>
    private var live: [SnapshotBox]          // MAIN THREAD ONLY — keeps recent boxes alive
    // Lifetime rule: render uses a box only within one render callback — acquire() is deliberately
    // `takeUnretainedValue()` (zero retain traffic on the render path, per the no-locks/no-ObjC-dispatch
    // invariant), so the box's ONLY thing keeping it alive while render reads it is this array's strong
    // reference. The retention window must outlive every render call that could still be holding a box
    // acquired before the most recent few publishes. A render callback's wall-clock budget is bounded by
    // its buffer duration (a few ms at typical settings) but can be stretched by OS scheduling jitter; a
    // publish-storm on the main thread (e.g. a fast UI drag, each tick calling scheduleRebuild()) can
    // plausibly fire faster than that. `3` was cutting it close enough to be a real (if rare) use-after-
    // free risk, not just a theoretical one — widened generously; the real fix would be an acquire/
    // release handshake (render reports back which generation it's done with), deliberately not built
    // here since it would add atomic traffic to the render path for a finding this margin already covers.
    private static let retainWindow = 16

    init(initial: SnapshotBox) {
        live = [initial]
        current = ManagedAtomic(Unmanaged.passUnretained(initial).toOpaque())
    }

    func publish(_ box: SnapshotBox) {
        dispatchPrecondition(condition: .onQueue(.main))
        live.append(box)
        current.store(Unmanaged.passUnretained(box).toOpaque(), ordering: .releasing)
        if live.count > Self.retainWindow { live.removeFirst(live.count - Self.retainWindow) }
    }

    @inline(__always)
    func acquire() -> SnapshotBox {
        Unmanaged<SnapshotBox>.fromOpaque(current.load(ordering: .acquiring)).takeUnretainedValue()
    }
}
