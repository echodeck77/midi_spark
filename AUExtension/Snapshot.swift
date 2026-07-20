//  Snapshot.swift
//  MidiSpark — the snapshot bridge (spec v2.8 §7).
//
//  The render thread NEVER reads the document. It reads a SnapshotBox: flat, fixed-size,
//  immutable after construction, published by atomic pointer swap. The UI thread builds
//  boxes (SnapshotBuilder) and publishes them (SnapshotStore.publish, MAIN THREAD ONLY).
//  Reads on the render thread are lock-free and allocation-free (acquire = one atomic load).

import Foundation
import Atomics   // swift-atomics via SPM — see project.yml `packages:`

// MARK: - Fixed geometry

enum Snap {
    static let cols = 8, rows = 8, colours = 16
    // Rate ladder shared by builder and kernel. Order MUST match ArpRate.allCases (§8: stable).
    static let arpRateBeats: [Double] = ArpRate.allCases.map(\.beats)
}

// MARK: - Flat cell (one per grid position; colourIndex < 0 = empty)

struct SnapCell {
    var colourIndex: Int8 = -1
    var stack = false          // ▾
    var srcMix = false         // +SRC
    var alt = false
    var bypassed = false
    var muted = false
    var busMask: UInt8 = 0     // bits 0–3 = A–D (§2.3: the only exits)
    var runStartColumn: Int8 = -1   // LEGATO precompute (§7 v2.4) — UI-thread work, render just reads
}

// MARK: - Resolved per-state params (paramsB pre-merged over paramsA at build time)

struct SnapParams {
    var type: ProcessorType = .arp
    var patternIndex: UInt8 = 0
    var rateIndex: Int8 = 3          // index into Snap.arpRateBeats
    var octaves: UInt8 = 1
    var gate: Double = 0.6
    var phase: ArpPhase = .retrig
    var count: UInt8 = 3             // ratchet
    var ramp: Double = 0.5
    var passMask: UInt8 = 0b1111     // passgate
}

struct SnapColour {
    var outChannel: UInt8 = 0        // 0 = INHERIT (§2.6)
    var transpose: Int8 = 0
    var morph: Double = 0
    var a = SnapParams()
    var b = SnapParams()             // fully resolved B (sparse overrides already applied)
}

// MARK: - The box: immutable after construction → safe concurrent reads, no locks

final class SnapshotBox {
    let stepBeats: Double
    let swing: Double                // 50…75 (§4 v2.3)
    let morphMaster: Double          // §13.5, parameter #35
    let colours: [SnapColour]        // exactly 16
    let cells: [SnapCell]            // 64, index = column * 8 + row

    init(stepBeats: Double, swing: Double, morphMaster: Double,
         colours: [SnapColour], cells: [SnapCell]) {
        self.stepBeats = stepBeats
        self.swing = swing
        self.morphMaster = morphMaster
        self.colours = colours
        self.cells = cells
    }
}

// MARK: - Effective params (render-side, §3.2: stepped fields quantize, never glide)

@inline(__always)
func effectiveMorph(_ colourMorph: Double, master: Double) -> Double {
    min(1.0, colourMorph + (1.0 - colourMorph) * master)      // §13.5
}

@inline(__always)
func effectiveRateBeats(_ c: SnapColour, t: Double) -> Double {
    let ia = Double(c.a.rateIndex), ib = Double(c.b.rateIndex)
    let idx = Int((ia + (ib - ia) * t).rounded())
    return Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, idx))]
}

@inline(__always)
func effectiveGate(_ c: SnapColour, t: Double) -> Double {
    c.a.gate + (c.b.gate - c.a.gate) * t                      // continuous: linear
}

@inline(__always)
func effectiveOctaves(_ c: SnapColour, t: Double) -> Int {
    let v = Double(c.a.octaves) + (Double(c.b.octaves) - Double(c.a.octaves)) * t
    return max(1, min(4, Int(v.rounded())))                   // stepped: round, clamp legal
}

// MARK: - The store: single-writer (main thread) publish, lock-free render acquire

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
