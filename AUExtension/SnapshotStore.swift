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
    // Lifetime rule: render uses a box only within one render callback (< ms); the publisher
    // keeps the last 3 boxes strongly referenced, so an in-flight render can never see a
    // deallocated box. Publish is main-only; violating that voids the guarantee.

    init(initial: SnapshotBox) {
        live = [initial]
        current = ManagedAtomic(Unmanaged.passUnretained(initial).toOpaque())
    }

    func publish(_ box: SnapshotBox) {
        dispatchPrecondition(condition: .onQueue(.main))
        live.append(box)
        current.store(Unmanaged.passUnretained(box).toOpaque(), ordering: .releasing)
        if live.count > 3 { live.removeFirst(live.count - 3) }
    }

    @inline(__always)
    func acquire() -> SnapshotBox {
        Unmanaged<SnapshotBox>.fromOpaque(current.load(ordering: .acquiring)).takeUnretainedValue()
    }
}
