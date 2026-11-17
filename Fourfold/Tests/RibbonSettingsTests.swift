//  RibbonSettingsTests.swift — RIBBON SETTINGS ferry (2026-11-16), slice 2: the saved settings model (§1) — the defaults,
//  the save round-trip, the decode-tolerance (§1.2), and the PluginState resolver. The LIVE holds (§2) and the engine/UI
//  come in later slices; here the model only has to persist and default correctly.

import XCTest

final class RibbonSettingsTests: XCTestCase {

    // §1.1 defaults: SCRUB, SLIP, LATCH off, both parts on, all lanes included, no marks.
    func testDefaults() {
        let d = RibbonSettings.defaults
        XCTAssertEqual(d.touchMode, .scrub); XCTAssertEqual(d.release, .slip); XCTAssertFalse(d.latch)
        XCTAssertTrue(d.riffOn); XCTAssertTrue(d.stackOn)
        XCTAssertEqual(d.riffLanes, 0x0F); XCTAssertEqual(d.stackLanes, 0x0F)
        XCTAssertEqual(d.tuttiSteps, 0); XCTAssertEqual(d.tuttiRanks, 0)
        XCTAssertFalse(d.tuttiActive)
        for l in 0..<4 { XCTAssertTrue(d.riffLaneIncluded(l)); XCTAssertTrue(d.stackLaneIncluded(l)) }
        for s in 1...8 { XCTAssertFalse(d.stepMarked(s)); XCTAssertFalse(d.rankMarked(s)) }
        XCTAssertEqual(RibbonSettings(), .defaults)
    }

    // §3.1 inclusion + §6 marks — the pure reads the engine + UI share.
    func testInclusionAndMarks() {
        var s = RibbonSettings()
        s.stackOn = false; XCTAssertTrue(s.riffLaneIncluded(2)); XCTAssertFalse(s.stackLaneIncluded(2), "stackOn off excludes every stack lane")
        s.stackOn = true; s.stackLanes = 0b0010; XCTAssertTrue(s.stackLaneIncluded(1)); XCTAssertFalse(s.stackLaneIncluded(0))
        s.riffOn = false; for l in 0..<4 { XCTAssertFalse(s.riffLaneIncluded(l), "riffOn off excludes every riff lane") }
        s.tuttiSteps = 0b0001_0000; XCTAssertTrue(s.stepMarked(5)); XCTAssertFalse(s.stepMarked(4)); XCTAssertTrue(s.tuttiActive)
        s = RibbonSettings(); s.tuttiRanks = 0b1000_0000; XCTAssertTrue(s.rankMarked(8)); XCTAssertFalse(s.rankMarked(7)); XCTAssertTrue(s.tuttiActive)
    }

    // §1.1 save: a non-default value round-trips through JSON exactly.
    func testRoundTrip() throws {
        var s = RibbonSettings()
        s.touchMode = .tutti; s.release = .carryOn; s.latch = true; s.stackOn = false
        s.riffLanes = 0b1010; s.stackLanes = 0b0101; s.tuttiSteps = 0b0010_0100; s.tuttiRanks = 0b1000_0001
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(RibbonSettings.self, from: data), s)
    }

    // §1.2 decode-tolerant: a garbled / partial blob keeps each field's default and never throws.
    func testTolerantDecode() throws {
        let garbled = Data(#"{"touchMode":"bogus","release":42,"latch":"nope","riffLanes":"x","tuttiSteps":3}"#.utf8)
        let s = try JSONDecoder().decode(RibbonSettings.self, from: garbled)
        XCTAssertEqual(s.touchMode, .scrub); XCTAssertEqual(s.release, .slip); XCTAssertFalse(s.latch)
        XCTAssertEqual(s.riffLanes, 0x0F, "a garbled field keeps its default")
        XCTAssertEqual(s.tuttiSteps, 3, "a valid field still decodes")
        XCTAssertEqual(try JSONDecoder().decode(RibbonSettings.self, from: Data("{}".utf8)), .defaults, "an empty object is all defaults")
    }

    // §9.2 / §13.6 — the loop walk reads columns inside the span a…b, in the lane's own direction, first position at a.
    func testLoopColumn() {
        func seq(_ dir: RiffDir, _ a: Int, _ b: Int, _ n: Int) -> [Int] {
            (0..<n).map { euclideousRibbonLoopColumn(k: Int64($0), spanA: a, spanB: b, direction: dir, stride: 1, every: 1) }
        }
        XCTAssertEqual(seq(.forward, 3, 5, 5), [3, 4, 5, 3, 4], "FWD loop 3–5")
        // §9.2 keeps the lane's OWN direction = riffStepAt. This codebase's ping-pong DOUBLES the turn columns (PENDULUM-style),
        // so PING reads 3,4,5,5,4,3 — NOT the §13.6 assumption 3,4,5,4,3,4 (the reflecting style). Reported (§16.6).
        XCTAssertEqual(seq(.pingpong, 3, 5, 6), [3, 4, 5, 5, 4, 3], "PING loop 3–5 (lane's own doubled-endpoint ping-pong)")
        XCTAssertEqual(seq(.reverse, 3, 5, 4), [5, 4, 3, 5], "REV loop 3–5")
        XCTAssertEqual(euclideousRibbonLoopColumn(k: 3, spanA: 3, spanB: 6, direction: .forward, stride: 1, every: 1), 6, "dragged to 3–6, k carries on: k=3 → column 6")
        XCTAssertEqual(seq(.forward, 2, 2, 3), [2, 2, 2], "a one-column span is a static repeat")
    }

    // §6.5–6.9 / §13.4 / §13.5 — TUTTI firing: the winning trigger's rank pulls every other included hit onto it.
    private func hit(_ lane: Int, notes: Bool = false, col: Int, played: Int, written: Int, inc: Bool = true) -> EuclideousRibbonStepHit {
        EuclideousRibbonStepHit(lane: lane, isNotes: notes, column: col, playedRank: played, columnWrittenRank: written, included: inc)
    }
    func testTuttiFireMarkedStep() {
        var s = RibbonSettings(); s.tuttiSteps = 0b0001_0000   // column 5 marked
        let hits = [hit(0, col: 2, played: 3, written: 3), hit(1, col: 7, played: 5, written: 5),
                    hit(2, col: 5, played: 8, written: 8), hit(3, col: 1, played: 2, written: 2)]   // lane-2 (0-based) reads the marked column 5 (written 8) → trigger
        let r = euclideousRibbonTuttiFire(hits: hits, settings: s, rankHold: nil)
        XCTAssertEqual(r.fireRank, 8); XCTAssertEqual(r.changed, [0, 1, 3], "every other included hit plays the fire rank; the trigger (2) is unchanged")
        var ex = hits; ex[0].included = false
        XCTAssertEqual(euclideousRibbonTuttiFire(hits: ex, settings: s, rankHold: nil).changed, [1, 3], "an excluded part is untouched")
        XCTAssertEqual(euclideousRibbonTuttiFire(hits: hits, settings: s, rankHold: 4).fireRank, 0, "§6.9 a rank hold beats TUTTI")
        XCTAssertTrue(euclideousRibbonTuttiFire(hits: hits, settings: s, rankHold: 4).changed.isEmpty)
        XCTAssertEqual(euclideousRibbonTuttiFire(hits: hits, settings: RibbonSettings(), rankHold: nil).changed, [], "no marks ⇒ nothing fires")
    }
    func testTuttiFireMarkedRankAndPriority() {
        var s = RibbonSettings(); s.tuttiRanks = 0b0000_0100   // rank 3 marked
        let hits = [hit(0, col: 1, played: 5, written: 5), hit(1, notes: true, col: 4, played: 3, written: 2), hit(2, col: 2, played: 7, written: 7)]
        let r = euclideousRibbonTuttiFire(hits: hits, settings: s, rankHold: nil)
        XCTAssertEqual(r.fireRank, 3); XCTAssertEqual(r.changed, [0, 2], "lane-1's stack plays marked rank 3 → the others play 3")
        // two triggers: lane 1 (0-based) via a marked column (written 6), lane 3 via marked rank 3 → the lower lane wins (6).
        var s2 = RibbonSettings(); s2.tuttiSteps = 0b0000_0010; s2.tuttiRanks = 0b0000_0100
        let two = [hit(1, col: 2, played: 6, written: 6), hit(3, col: 5, played: 3, written: 3), hit(0, col: 7, played: 4, written: 4)]
        let r2 = euclideousRibbonTuttiFire(hits: two, settings: s2, rankHold: nil)
        XCTAssertEqual(r2.fireRank, 6, "the lower-numbered lane's trigger wins"); XCTAssertEqual(r2.changed, [2], "only the non-trigger changes")
    }

    // §10.3 — the alloc-free render-thread sibling `euclideousRibbonTuttiFireSlots` must AGREE with `euclideousRibbonTuttiFire` on random steps.
    func testTuttiFireSlotsAgreesWithTheSetVersion() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<400 {
            var s = RibbonSettings()
            s.tuttiSteps = UInt8.random(in: 0...255, using: &rng); s.tuttiRanks = UInt8.random(in: 0...255, using: &rng)
            let rankHold: Int? = Bool.random(using: &rng) ? Int.random(in: 1...8, using: &rng) : nil
            // up to 8 slots (lane·2 + part); build both a [hit] list (for the Set fn) and the parallel fixed arrays (for the slots fn).
            var hits: [EuclideousRibbonStepHit] = []
            var present: UInt16 = 0, included: UInt16 = 0
            var col = [Int](repeating: 0, count: 8), played = [Int](repeating: 0, count: 8), written = [Int](repeating: 0, count: 8)
            for slot in 0..<8 where Bool.random(using: &rng) {
                let lane = slot / 2, isNotes = slot % 2 == 1
                let c = Int.random(in: 0...8, using: &rng), pr = Int.random(in: 0...8, using: &rng), wr = Int.random(in: 0...8, using: &rng)
                let inc = Bool.random(using: &rng)
                present |= UInt16(1) << UInt16(slot); if inc { included |= UInt16(1) << UInt16(slot) }
                col[slot] = c; played[slot] = pr; written[slot] = wr
                hits.append(EuclideousRibbonStepHit(lane: lane, isNotes: isNotes, column: c, playedRank: pr, columnWrittenRank: wr, included: inc))
            }
            let setR = euclideousRibbonTuttiFire(hits: hits, settings: s, rankHold: rankHold)
            let slotR = euclideousRibbonTuttiFireSlots(present: present, included: included, column: col, played: played, written: written, settings: s, rankHold: rankHold)
            XCTAssertEqual(setR.fireRank, slotR.fireRank, "fire rank agrees")
            // the Set fn indexes into the compacted `hits`; map its changed indices back to slots to compare the masks.
            var expectMask: UInt16 = 0
            var hi = 0
            for slot in 0..<8 where (present >> UInt16(slot)) & 1 != 0 {
                if setR.changed.contains(hi) { expectMask |= UInt16(1) << UInt16(slot) }
                hi += 1
            }
            XCTAssertEqual(slotR.changedMask, expectMask, "changed set agrees (steps \(s.tuttiSteps)/\(s.tuttiRanks), hold \(String(describing: rankHold)))")
        }
    }

    // §7.2 / §7.3 / §13.8 / §13.9 — CONTINUE: after a hold ends, the lane reads value(o + d) so the next hit follows the last.
    func testContinueOffset() {
        // §13.8 FWD LEN 8 (column = (n mod 8)+1): column 6 held, next hit (ordinal 0) must read 7 ⇒ d s.t. walk(0+d-1)=6.
        let fwd: (Int64) -> Int = { Int(($0 % 8 + 8) % 8) + 1 }
        let d = euclideousRibbonContinueOffset(nextOrdinal: 0, last: 6, currentOffset: 0, period: 8, valueAt: fwd)
        XCTAssertEqual(fwd(0 + Int64(d)), 7, "the next hit reads column 7, continuing from 6")
        // a column the walk never visits ⇒ the offset is kept.
        XCTAssertEqual(euclideousRibbonContinueOffset(nextOrdinal: 0, last: 99, currentOffset: 4, period: 8, valueAt: fwd), 4, "last not in the period ⇒ keep the offset")
        // §13.9 PLAY AS UP over ranks 1,3,5,7: rank 5 held, the next stack hit plays 7.
        let up: (Int64) -> Int = { [1, 3, 5, 7][Int(($0 % 4 + 4) % 4)] }
        let ds = euclideousRibbonContinueOffset(nextOrdinal: 0, last: 5, currentOffset: 0, period: 4, valueAt: up)
        XCTAssertEqual(up(0 + Int64(ds)), 7, "the next stack hit plays 7, continuing from 5")
    }

    // §4.1 / §5.2 — the settings layout: the button fits (≥ 30×30) at every layout, the rows are ordered and inside the box.
    func testSettingsLayout() {
        for box in [CGSize(width: 380.67, height: 301), CGSize(width: 387, height: 301.67), CGSize(width: 300, height: 260), CGSize(width: 260, height: 240)] {
            let L = euclideousRibbonSettingsLayout(box: box)
            XCTAssertTrue(L.buttonFits, "§4.1 the button is ≥ 30×30 at \(box)")
            XCTAssertGreaterThanOrEqual(L.button.width, 30); XCTAssertGreaterThanOrEqual(L.button.height, 30)
            XCTAssertEqual(L.button.minX, EuclideousRiffPanelMetrics.padding, accuracy: 0.001, "§4.1 x = padding")
            // §5.2 top-to-bottom order: RIBBONS, TOUCH, RELEASE, LATCH, PARTS, RIFF, STACK.
            let ys = [L.ribbonsHeaderY, L.touchY, L.releaseY, L.latchY, L.partsHeaderY, L.riffY, L.stackY]
            for i in 1..<ys.count { XCTAssertLessThan(ys[i - 1], ys[i], "rows are ordered at \(box)") }
            // the 9pt gap before PARTS is larger than the plain 4pt row gap.
            XCTAssertGreaterThan(L.partsHeaderY - (L.latchY + L.rowH), (L.touchY - (L.ribbonsHeaderY + L.headerH)) - 0.001, "§5.2 the PARTS header gap is the wider one")
            XCTAssertLessThanOrEqual(L.contentBottom, box.height, "the content fits in the box at \(box)")
            XCTAssertEqual(L.controlsX, euclideousRiffPanelLayout(box: box).firstColumnX, accuracy: 0.001, "controls start at column 0")
        }
    }

    // §1.2 PluginState: nil ⇒ the defaults; a set value is kept; and an old document (no key) resolves to the defaults.
    func testPluginStateResolver() throws {
        var ps = PluginState(machines: [], scenes: [])
        XCTAssertNil(ps.ribbonSettings); XCTAssertEqual(ps.ribbonSettingsResolved, .defaults)
        var s = RibbonSettings(); s.touchMode = .loop; ps.ribbonSettings = s
        XCTAssertEqual(ps.ribbonSettingsResolved, s)
        // a document encoded WITHOUT ribbonSettings decodes with nil ⇒ defaults
        var old = PluginState(machines: [], scenes: []); old.ribbonSettings = nil
        let data = try JSONEncoder().encode(old)
        XCTAssertEqual(try JSONDecoder().decode(PluginState.self, from: data).ribbonSettingsResolved, .defaults)
    }
}
