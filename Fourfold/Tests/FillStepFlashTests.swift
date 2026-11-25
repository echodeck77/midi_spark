//  FillStepFlashTests.swift — STEP DISPLAY part 2 (FILL step flash, 2026-11-25): the lane card step grid's fill overlay.
//
//  Pins `euclideousFillStepFlash` — which displayed step boxes a hit-changing fill SOUNDS / SILENCES while it holds over
//  the region. The function reuses the Router's own fired-step / BREAK / hit-test functions, so these cases double as the
//  contract the cells draw against; the visual itself is device-owed.

import XCTest

final class FillStepFlashTests: XCTestCase {

    // An 8-step lane, 3-of-8 hits at boxes 0, 3, 6; sub 0.5, a BAR-length fill ⇒ 8 slots cover all 8 boxes.
    private let std = [true, false, false, true, false, false, true, false]

    private func plan(hits: EuclideousFillHits = .keep, order: EuclideousFillOrder = .fwd, m: Double = 1,
                      breakOn: Bool = false, ranks: Int = 0, curve: EuclideousFillCurve = .steady,
                      lengthFraction: Double = 1.0, chance: Int = 100, lane: Int = 0, armedBar0: Bool = true) -> EuclideousFillPlan {
        var p = EuclideousFillPlan()
        p.active = true; p.armed = armedBar0 ? 1 : 0; p.loop = 8; p.lane = lane; p.m = m; p.lengthFraction = lengthFraction
        p.curve = curve; p.order = order; p.hits = hits; p.ranks = ranks; p.breakOn = breakOn; p.chance = chance
        p.originBeat = 0; p.beatsPerBar = 4; p.sub = 0.5
        return p
    }
    private func flash(_ p: EuclideousFillPlan, beat: Double = 1.0) -> EuclideousFillStepFlash {
        euclideousFillStepFlash(plan: p, beat: beat, n: 8, dir: .fwd, sub: 0.5, standardHits: std)
    }

    // §: ALL — every visited box sounds (incl. the standard rests), nothing silenced.
    func testAllSoundsEveryBox() {
        let f = flash(plan(hits: .all))
        XCTAssertEqual(f.sounds, Set(0..<8))
        XCTAssertTrue(f.silenced.isEmpty)
    }

    // §: FLIP — the standard rests sound, the standard hits go silent.
    func testFlipInvertsTheSet() {
        let f = flash(plan(hits: .flip))
        XCTAssertEqual(f.sounds, Set([1, 2, 4, 5, 7]))   // the rests
        XCTAssertEqual(f.silenced, Set([0, 3, 6]))       // the standard hits, now silent
    }

    // §: a KEEP fill that only REORDERS (REV) plays the SAME set — a visible no-op (sounds == the standard hits, nothing silenced).
    func testReorderOnlyMatchesStandard() {
        let f = flash(plan(order: .rev))   // changesHits (order ≠ fwd) but the SET is unchanged
        XCTAssertEqual(f.sounds, Set([0, 3, 6]))
        XCTAssertTrue(f.silenced.isEmpty)
    }

    // §: BREAK drops the region's last quarter — a standard hit there reads as a rest.
    func testBreakSilencesTheLastQuarter() {
        let f = flash(plan(breakOn: true))   // last quarter [3,4) ⇒ slots 6,7 (box 6 is a hit, box 7 a rest)
        XCTAssertEqual(f.sounds, Set([0, 3]))
        XCTAssertEqual(f.silenced, Set([6]))
    }

    // §: a fill that doesn't change the HITS (RANKS only) is empty ⇒ the cells draw the standard pattern.
    func testRecolourOnlyFillIsEmpty() {
        XCTAssertFalse(flash(plan(ranks: 5)).active)
    }

    // §: no active region (an unarmed bar, or a beat outside [F, E), or CHANCE 0 skipping) ⇒ empty.
    func testNoRegionIsEmpty() {
        XCTAssertFalse(flash(plan(hits: .all, armedBar0: false)).active)     // bar 0 not armed
        XCTAssertFalse(flash(plan(hits: .all), beat: 5.0).active)            // bar 1, not armed
        XCTAssertFalse(flash(plan(hits: .all, chance: 0)).active)            // CHANCE 0 never plays
        XCTAssertFalse(euclideousFillStepFlash(plan: nil, beat: 1, n: 8, dir: .fwd, sub: 0.5, standardHits: std).active)
    }

    // §: sounds and silenced are always disjoint (a box that sounds in any slot wins).
    func testSoundsAndSilencedDisjoint() {
        for h in [EuclideousFillHits.keep, .all, .flip, .build] {
            for ord in [EuclideousFillOrder.fwd, .rev, .bounce] {
                for br in [false, true] {
                    let f = flash(plan(hits: h, order: ord, breakOn: br))
                    XCTAssertTrue(f.sounds.isDisjoint(with: f.silenced), "hits=\(h) order=\(ord) break=\(br)")
                    XCTAssertTrue(f.silenced.allSatisfy { std[$0] }, "a silenced box must be a standard hit (hits=\(h))")
                }
            }
        }
    }
}
