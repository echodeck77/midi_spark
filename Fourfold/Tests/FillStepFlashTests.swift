//  FillStepFlashTests.swift — STEP DISPLAY part 2 (FILL step flash, 2026-11-25; gated to the playhead 2026-11-26).
//
//  Pins `euclideousFillPlayheadFlash` — what a hit-changing fill does to the ONE box the playhead is sounding now:
//  `.sounds` (draw as a hit), `.silencedMiss` (a dropped standard hit — draw as a rest = the normal sounding-miss look),
//  or `.none` (standard pattern). The function reads the standard hit AT THE PLAYHEAD BOX and the fill's CURRENT slot
//  (s = floor((beat − F)/stepLen)), reusing the Router's own BREAK / hit-test; the visual itself is device-owed.

import XCTest

final class FillStepFlashTests: XCTestCase {

    // An 8-step lane, 3-of-8 hits at boxes 0, 3, 6; sub 0.5, a BAR-length fill ⇒ 8 slots (0.5 beat each), box i = forward slot i.
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
    /// box i's own forward slot sits at beat i × 0.5; this is the (beat, box) pair the comet is on for box i.
    private func flash(_ p: EuclideousFillPlan, box: Int) -> EuclideousFillPlayheadFlash {
        euclideousFillPlayheadFlash(plan: p, beat: Double(box) * 0.5 + 1e-6, sub: 0.5, playheadBox: box, standardHits: std)
    }

    // §: ALL — the box the playhead is on sounds whether it is a standard hit or a standard rest.
    func testAllSoundsAnyBox() {
        XCTAssertEqual(flash(plan(hits: .all), box: 0), .sounds)   // a standard hit
        XCTAssertEqual(flash(plan(hits: .all), box: 1), .sounds)   // a standard rest the fill plays
    }

    // §: FLIP — a standard hit reads as a (sounding) miss, a standard rest sounds.
    func testFlipInverts() {
        XCTAssertEqual(flash(plan(hits: .flip), box: 0), .silencedMiss)   // standard hit → dropped
        XCTAssertEqual(flash(plan(hits: .flip), box: 1), .sounds)         // standard rest → plays
    }

    // §: a KEEP fill that only REORDERS plays the SAME set — a standard hit sounds, a standard rest is a no-op (.none).
    func testKeepReorderIsANoOpPerBox() {
        XCTAssertEqual(flash(plan(order: .rev), box: 0), .sounds)   // a standard hit
        XCTAssertEqual(flash(plan(order: .rev), box: 1), .none)     // a standard rest stays a rest ⇒ draw the standard pattern
    }

    // §: BREAK drops the region's last quarter — a standard hit there reads as a sounding miss; a hit before it still sounds.
    func testBreakSilencesTheLastQuarter() {
        XCTAssertEqual(flash(plan(breakOn: true), box: 6), .silencedMiss)   // box 6 (slot 6) is in the last quarter
        XCTAssertEqual(flash(plan(breakOn: true), box: 0), .sounds)         // box 0 (slot 0) is not
    }

    // §: a fill that doesn't change the HITS (RANKS only) ⇒ .none for every box (the cells draw the standard pattern).
    func testRecolourOnlyFillIsNone() {
        for b in 0..<8 { XCTAssertEqual(flash(plan(ranks: 5), box: b), .none) }
    }

    // §: BUILD — the first half KEEPs (a standard rest is a no-op), the second half is ALL (a standard rest sounds).
    func testBuildKeepsThenPlaysAll() {
        XCTAssertEqual(flash(plan(hits: .build), box: 0), .sounds)   // first half, a standard hit
        XCTAssertEqual(flash(plan(hits: .build), box: 1), .none)     // first half, a standard rest ⇒ stays a rest
        XCTAssertEqual(flash(plan(hits: .build), box: 4), .sounds)   // second half (slot 4 ≥ (8+1)/2), a standard rest now sounds
    }

    // §: no active region (unarmed bar / outside [F,E) / CHANCE 0 / nil plan), and a box out of range ⇒ .none.
    func testNoRegionOrOutOfRangeIsNone() {
        XCTAssertEqual(flash(plan(hits: .all, armedBar0: false), box: 0), .none)   // bar 0 not armed
        XCTAssertEqual(euclideousFillPlayheadFlash(plan: plan(hits: .all), beat: 5.0, sub: 0.5, playheadBox: 0, standardHits: std), .none)   // bar 1, not armed
        XCTAssertEqual(flash(plan(hits: .all, chance: 0), box: 0), .none)          // CHANCE 0 never plays
        XCTAssertEqual(euclideousFillPlayheadFlash(plan: nil, beat: 1, sub: 0.5, playheadBox: 0, standardHits: std), .none)
        XCTAssertEqual(flash(plan(hits: .all), box: 99), .none)                    // box out of range
    }

    // §: a standard REST is never a silenced MISS (that look is only for a dropped standard hit), for every mode / order / break.
    func testARestIsNeverASilencedMiss() {
        for h in [EuclideousFillHits.keep, .all, .flip, .build] {
            for ord in [EuclideousFillOrder.fwd, .rev, .bounce] {
                for br in [false, true] {
                    for box in 0..<8 where !std[box] {
                        XCTAssertNotEqual(flash(plan(hits: h, order: ord, breakOn: br), box: box), .silencedMiss, "hits=\(h) order=\(ord) break=\(br) box=\(box)")
                    }
                }
            }
        }
    }
}
