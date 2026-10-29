//  EmitterRatchetLive.swift
//  RATCH tab ferry (2026-10-28) §3.10: what the RATCH tab's strips read live — each output's pattern index at its most recent emitter hit, as the Router last published it (one byte per output, 0xFF = none yet) through the
//  existing 30 Hz poll. A leaf view observes this object, never the page body, so a hit moving an index does not re-run the page. Live indicators show only while the transport runs (the engine keeps a stopped lane's last step).

import SwiftUI

final class EmitterRatchetLive: ObservableObject {
    /// Output A…D's current pattern index, −1 = none (nothing has hit it yet, or the transport is not running).
    @Published private(set) var indices: [Int] = [-1, -1, -1, -1]
    /// The slot each output's most recent flare belongs to — kept through a stop (the flare's 1.5 s afterglow outlives the highlighted slot, which clears) and replaced by the next hit. Not published: the strip's TimelineView reads it.
    private(set) var lastIndices: [Int] = [-1, -1, -1, -1]
    func update(packed: UInt32, running: Bool) {
        var next = [Int](repeating: -1, count: 4)
        for x in 0..<4 { let b = (packed >> UInt32(8 * x)) & 0xFF; if b != 0xFF { lastIndices[x] = Int(b); if running { next[x] = Int(b) } } }
        if next != indices { indices = next }
    }
    func flareIndex(_ x: Int) -> Int? { x >= 0 && x < lastIndices.count && lastIndices[x] >= 0 ? lastIndices[x] : nil }
    func index(_ x: Int) -> Int? { x >= 0 && x < indices.count && indices[x] >= 0 ? indices[x] : nil }
}
