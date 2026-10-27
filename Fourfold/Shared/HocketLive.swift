//  HocketLive.swift
//  HOCKET ferry (2026-10-27) §8: what the live displays read. The Router publishes the count x of each lit rule (the SAME `hocketCount` the engine plays by) through the existing 30 Hz poll; the pop-up's chips, bars and
//  cycle-strip ring and the lane cards' glyphs derive the turn from it with the SAME `hocketTurn` / `hocketOutput` / `hocketPartView`. Leaf views observe this object, never the page body, so a turn changing does not re-run the page.

import SwiftUI

/// What the live displays read: the count x of each rule (as the Router last published it) and whether the transport runs. The turn is DERIVED here with the same `hocketTurn` the engine calls.
final class HocketLiveModel: ObservableObject {
    @Published private(set) var counts: [Int64] = [0, 0, 0, 0]
    @Published private(set) var running = false
    func update(counts c: [Int64], running r: Bool) {
        if c != counts { counts = c }
        if r != running { running = r }
    }
    func turn(rule i: Int, snap s: HocketRuleSnap) -> HocketTurn {
        hocketTurn(x: i < counts.count ? counts[i] : 0, offset: s.offset, mainLen: s.mainLen, altLen: s.altLen)
    }
}
