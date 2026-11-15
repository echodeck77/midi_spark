//  EmitterRatchetV2Tests.swift — RATCH v2 ferry (2026-11-15) §11: the model decode (§1.7), the COUNTS roll (§2.2),
//  the SPREAD timing (§2.3), gate (§2.4) and the VEL ramp (§2.5), all pure. The engine wiring rides the golden
//  byte-identity + EmitterRatchetRouterTests; the strip layout rides slice 3; §11.6 choke is N/A under §0.2.

import XCTest

final class EmitterRatchetV2Tests: XCTestCase {

    // §11.1 — a default ratchet (FIX ×3, GAP FIT) resolves to COUNTS {3}, PER HIT off, LENGTH 1, BEND 0, VEL FLAT, DEPTH 50.
    func testDefaultsResolve() {
        let r = EmitterRatchet()   // mode .fix, strikes 3, gap .fit, all new fields nil
        XCTAssertEqual(r.countsMembers, [3])
        XCTAssertFalse(r.perHitResolved)
        XCTAssertEqual(r.lengthResolved, .one)
        XCTAssertEqual(r.bendResolved, 0)
        XCTAssertEqual(r.velResolved, .flat)
        XCTAssertEqual(r.depthResolved, 50)
    }

    // §11.2 — §1.7 derive from MODE/STRIKES/RANGE when the new fields are nil.
    func testDecodeDeriveCounts() {
        var r = EmitterRatchet(); r.mode = .fix; r.strikes = 4
        XCTAssertEqual(r.countsMembers, [4], "FIX → {STRIKES}")
        r = EmitterRatchet(); r.mode = .range; r.rangeMin = 2; r.rangeMax = 4
        XCTAssertEqual(r.countsMembers, [2, 3, 4], "RANGE 2–4 → {2,3,4}")
        r = EmitterRatchet(); r.mode = .range; r.rangeMin = 1; r.rangeMax = 3
        XCTAssertEqual(r.countsMembers, [2, 3], "RANGE 1–3 → {2,3} (the play-once option drops)")
        r = EmitterRatchet(); r.mode = .hit
        XCTAssertTrue(r.perHitResolved, "HIT → PER HIT on")
        XCTAssertEqual(r.countsMembers, [3], "HIT → COUNTS {3}")
        r = EmitterRatchet(); r.gap = .sixteenth
        XCTAssertEqual(r.lengthResolved, .one, "any GAP → LENGTH 1")
        // an explicit set wins over the derivation; an empty stored set derives (never empty).
        r = EmitterRatchet(); r.countsBits = EmitterRatchet.countBit(2) | EmitterRatchet.countBit(4)
        XCTAssertEqual(r.countsMembers, [2, 4])
        r = EmitterRatchet(); r.countsBits = 0; r = r.normalized()
        XCTAssertNil(r.countsBits, "an empty stored COUNTS set normalises to nil (derives)")
    }

    // §11.2 round-trip through Codable: the new fields survive encode→decode; an absent key stays nil (derives).
    func testCodableRoundTrip() throws {
        var r = EmitterRatchet(); r.on = true
        r.countsBits = EmitterRatchet.countBit(2) | EmitterRatchet.countBit(4); r.perHit = true
        r.length = .half; r.bend = -40; r.vel = .swell; r.depth = 75
        let back = try JSONDecoder().decode(EmitterRatchet.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.countsMembers, [2, 4]); XCTAssertTrue(back.perHitResolved)
        XCTAssertEqual(back.lengthResolved, .half); XCTAssertEqual(back.bendResolved, -40)
        XCTAssertEqual(back.velResolved, .swell); XCTAssertEqual(back.depthResolved, 75)
    }

    // §11.3 — COUNTS {2,4}: over many hits both 2 and 4 appear, 3 never; replay-exact; a single member is constant.
    func testCountsRoll() {
        var r = EmitterRatchet(); r.on = true; r.steps = 16; r.hits = 16; r.chance = 100   // every index a hit
        r.countsBits = EmitterRatchet.countBit(2) | EmitterRatchet.countBit(4)
        let cfg = EmitterRatchetCfg(r)
        var got = Set<Int>()
        for v in 0..<400 { got.insert(emitterRatchetDecide(cfg, output: 0, v: Int64(v)).strikes) }
        XCTAssertTrue(got.contains(2) && got.contains(4), "both 2 and 4 appear")
        XCTAssertFalse(got.contains(3), "3 never appears")
        XCTAssertEqual(emitterRatchetDecide(cfg, output: 0, v: 7).strikes, emitterRatchetDecide(cfg, output: 0, v: 7).strikes, "replay-exact")
        var one = EmitterRatchet(); one.on = true; one.steps = 16; one.hits = 16; one.countsBits = EmitterRatchet.countBit(3)
        let cfg1 = EmitterRatchetCfg(one)
        for v in 0..<50 { XCTAssertEqual(emitterRatchetDecide(cfg1, output: 0, v: Int64(v)).strikes, 3, "a single member is always that count") }
    }

    // §11.4 — BEND 0 start offsets (1/8 lane, stepBeats 0.5).
    func testTimingBendZero() {
        func starts(n: Int, length: EmitterStrikeLength) -> [Double] { (0..<n).map { emitterStrikeStartOffset(k: $0, n: n, length: length, bend: 0, stepBeats: 0.5) } }
        XCTAssertEqual(starts(n: 4, length: .one), [0, 0.125, 0.25, 0.375])
        XCTAssertEqual(starts(n: 4, length: .two), [0, 0.25, 0.5, 0.75])
    }

    // §11.5 — BEND start offsets. RUSH 50 (p 2), ×3, LENGTH 1, 1/8 lane: 0, 0.2778, 0.4444. DRAG 50: 0, 0.0556, 0.2222.
    func testTimingBend() {
        func starts(bend: Int) -> [Double] { (0..<3).map { emitterStrikeStartOffset(k: $0, n: 3, length: .one, bend: bend, stepBeats: 0.5) } }
        let rush = starts(bend: 50)
        XCTAssertEqual(rush[0], 0, accuracy: 1e-4); XCTAssertEqual(rush[1], 0.2778, accuracy: 1e-3); XCTAssertEqual(rush[2], 0.4444, accuracy: 1e-3)
        let drag = starts(bend: -50)
        XCTAssertEqual(drag[0], 0, accuracy: 1e-4); XCTAssertEqual(drag[1], 0.0556, accuracy: 1e-3); XCTAssertEqual(drag[2], 0.2222, accuracy: 1e-3)
    }

    // §11.7 — LENGTH ½: every strike starts in the first half of the step (offset < 0.5 × stepBeats).
    func testLengthHalfStaysInStep() {
        let half = 0.5 * 0.5   // ½ step of a 1/8 lane
        for bend in [-50, 0, 50] {
            for k in 0..<4 {
                XCTAssertLessThan(emitterStrikeStartOffset(k: k, n: 4, length: .half, bend: bend, stepBeats: 0.5), half + 1e-9, "LENGTH ½ strike \(k) (bend \(bend)) starts in the first half")
            }
        }
    }

    // §11.8 — gate: GATE 50, ×4, LENGTH 1, 1/8 lane ⇒ each strike slot 0.125, gate 0.0625 beats.
    func testGate() {
        for k in 0..<4 {
            let slot = emitterStrikeSlotBeats(k: k, n: 4, length: .one, bend: 0, stepBeats: 0.5)
            XCTAssertEqual(slot, 0.125, accuracy: 1e-9)
            XCTAssertEqual(0.5 * slot, 0.0625, accuracy: 1e-9, "GATE 50 × slot")
        }
    }

    // §11.11 — the strip layout: STEPS 8 fills the width, slot 4 sits +3 right (the group gap); COUNTS {2,4} ⇒ 4 marks, the last two faint.
    func testStripLayoutAndFaintMarks() {
        var r = EmitterRatchet(on: true, steps: 8, hits: 8); r.countsBits = EmitterRatchet.countBit(3)
        let s = euclideousRatchetStripV2(size: CGSize(width: 200, height: 26), r: r, current: 2, expanded: false)
        XCTAssertEqual(s.slots.count, 8)
        XCTAssertEqual(s.slots.last!.rect.maxX, 200, accuracy: 0.5, "the slots fill the width")
        XCTAssertTrue(s.slots[2].isCurrent)
        let cellW = s.slots[0].rect.width
        XCTAssertEqual(s.slots[4].rect.minX, 4 * (cellW + 2) + 3, accuracy: 0.5, "slot 4 sits +3 right of an even split (the group gap)")
        var m = EmitterRatchet(on: true, steps: 8, hits: 8); m.countsBits = EmitterRatchet.countBit(2) | EmitterRatchet.countBit(4)
        let sm = euclideousRatchetStripV2(size: CGSize(width: 200, height: 26), r: m, current: -1, expanded: false).marks.filter { $0.slot == 0 }
        XCTAssertEqual(sm.count, 4, "n_d = the largest member 4 ⇒ 4 marks")
        XCTAssertEqual(sm[0].alpha, 1.0, accuracy: 1e-9, "CHANCE 100 ⇒ solid")
        XCTAssertEqual(sm[2].alpha, 0.3, accuracy: 1e-9, "k = 2 ≥ smallest member 2 ⇒ faint")
        XCTAssertEqual(sm[3].alpha, 0.3, accuracy: 1e-9)
    }

    // §11.11 — spilled marks (LENGTH 2+, strip math only; the UI hides 2/3/4) stop at STEPS and at the next hit slot.
    func testStripSpillChoke() {
        var atEnd = EmitterRatchet(on: true, steps: 8, hits: 1, offset: 1); atEnd.countsBits = EmitterRatchet.countBit(4); atEnd.length = .two   // E(1,8) left-rotated by 1 ⇒ the hit lands on slot 7
        let strip7 = euclideousRatchetStripV2(size: CGSize(width: 200, height: 26), r: atEnd, current: -1, expanded: false)
        XCTAssertTrue(strip7.slots[7].isHit, "the single hit is at slot 7")
        XCTAssertEqual(strip7.marks.filter { $0.slot == 7 }.count, 2, "from slot 7, LENGTH 2 ×4 ⇒ cells 7,7,8,8 — the two past STEPS drop")
        var toHit = EmitterRatchet(on: true, steps: 8, hits: 4); toHit.countsBits = EmitterRatchet.countBit(4); toHit.length = .four   // E(4,8) hits 0,2,4,6
        let s = euclideousRatchetStripV2(size: CGSize(width: 240, height: 26), r: toHit, current: -1, expanded: false)
        let m0 = s.marks.filter { $0.slot == 0 }
        XCTAssertEqual(m0.count, 2, "slot 0's spill (cells 0,1,2,3) stops at the hit in cell 2")
        XCTAssertTrue(m0.contains { $0.rect.minX >= s.slots[1].rect.minX - 0.5 }, "a mark spilled into cell 1")
    }

    // §4.6 — PER HIT expanded: the strip reserves a 14 pt count row and carries each hit slot's count.
    func testStripPerHitCountRow() {
        var r = EmitterRatchet(on: true, steps: 8, hits: 8); r.perHit = true
        r = r.settingHitCount(0, 4)
        let s = euclideousRatchetStripV2(size: CGSize(width: 200, height: 40), r: r, current: -1, expanded: true)
        XCTAssertEqual(s.countRowH, 14)
        XCTAssertEqual(s.slots[0].count, 4, "slot 0's per-hit count shows under the strip")
        XCTAssertEqual(s.marks.filter { $0.slot == 0 }.count, 4, "n_d = that hit's count (4)")
    }

    // §8.4/§8.5/§6.9 — the BEND / DEPTH value cells: text + the relative drag (a 6 pt deadzone, then 10 per 10 pt / 5 per 3 pt; negative dy = up = more).
    func testBendDepthTextAndDrag() {
        XCTAssertEqual(emitterRatchetBendText(0), "EVEN")
        XCTAssertEqual(emitterRatchetBendText(40), "RUSH 40")
        XCTAssertEqual(emitterRatchetBendText(-40), "DRAG 40")
        XCTAssertEqual(emitterRatchetDepthText(60), "60%")
        XCTAssertEqual(emitterRatchetBendFromDrag(start: 0, translationHeight: -4), 0, "inside the 6 pt deadzone")
        XCTAssertEqual(emitterRatchetBendFromDrag(start: 0, translationHeight: -16), 10, "up 16 ⇒ past 6 by 10 ⇒ +10 (RUSH)")
        XCTAssertEqual(emitterRatchetBendFromDrag(start: 0, translationHeight: 16), -10, "down ⇒ DRAG")
        XCTAssertEqual(emitterRatchetBendFromDrag(start: 100, translationHeight: -50), 100, "clamped at +100")
        XCTAssertEqual(emitterRatchetDepthFromDrag(start: 50, translationHeight: -9), 55, "up 9 ⇒ past 6 by 3 ⇒ +5")
        XCTAssertEqual(emitterRatchetDepthFromDrag(start: 0, translationHeight: 60), 0, "clamped at 0")
    }

    // §11.9 — VEL shares. FADE 60 ×4: 1, 0.8, 0.6, 0.4. SWELL 60: 0.4, 0.6, 0.8, 1. FLAT: all 1.
    func testVelShares() {
        func shares(_ v: EmitterStrikeVel, depth: Int) -> [Double] { (0..<4).map { emitterStrikeVelShare(vel: v, depth: depth, k: $0, n: 4) } }
        zip(shares(.fade, depth: 60), [1, 0.8, 0.6, 0.4]).forEach { XCTAssertEqual($0, $1, accuracy: 1e-9) }
        zip(shares(.swell, depth: 60), [0.4, 0.6, 0.8, 1]).forEach { XCTAssertEqual($0, $1, accuracy: 1e-9) }
        XCTAssertEqual(shares(.flat, depth: 60), [1, 1, 1, 1])
        XCTAssertEqual(emitterStrikeVelShare(vel: .fade, depth: 60, k: 0, n: 1), 1, "n=1 ⇒ 1")
    }
}
