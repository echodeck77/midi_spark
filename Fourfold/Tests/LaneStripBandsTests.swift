//  LaneStripBandsTests.swift — LANE STRIP BANDS ferry (2026-11-12), slice 2: the pure band/frame/colour/outline/cell
//  functions (§8), tested at both the real top-row height T 44 (Paul's choice) and the spec's reference T 78, so the
//  ratio formulas are pinned either way. §10 tests 1, 3, 6, 9 + the CC source helper.

import XCTest
import CoreGraphics

final class LaneStripBandsTests: XCTestCase {

    // PLAY BUTTONS RAIL+NOTE §3.1 — band heights (ratio 0.2; each ON part reserves rail 1.5 + gap 1 + band hH + gap 1):
    // the real T 44 and the spec's reference T 78, both parts on.
    func testBandHeights() {
        let railH = LaneStripBandMetrics.railH
        let a = laneStripBandHeights(T: 78)
        XCTAssertEqual(a.hH, 16); XCTAssertEqual(a.hC, 38); XCTAssertEqual(a.gap, 1)         // COMPACT+STRIP §4.3 rail 2: round(78·0.2)=16; 78 − 2·(2+1+16+1) = 38
        let b = laneStripBandHeights(T: 44)
        XCTAssertEqual(b.hH, 9); XCTAssertEqual(b.hC, 18); XCTAssertEqual(b.gap, 1)          // round(44·0.2)=9;  44 − 2·(2+1+9+1) = 18
        // with both parts on, 2 rails + 2 bands + 4 gaps + the cells fill T exactly, and hH never drops below the 8 pt floor
        for T in stride(from: CGFloat(30), through: 90, by: 1) {
            let h = laneStripBandHeights(T: T)
            XCTAssertEqual(2 * railH + 2 * h.hH + 4 * h.gap + h.hC, T, accuracy: 0.001, "bands + rails + gaps fill T at \(T)")
            XCTAssertGreaterThanOrEqual(h.hH, 8, "§B2.1 floor at \(T)")
        }
    }

    // PLAY BUTTONS RAIL+NOTE §3.1/§3.2/§3.3 — the per-part collapse: an OFF part reserves nothing (cells extend); hC grows.
    func testPartAwareCollapseAndBandPositions() {
        let railH = LaneStripBandMetrics.railH, reserve: CGFloat = railH + 1 + 9 + 1   // COMPACT+STRIP §4.3 rail 2 → 13 per on part
        // §3.2: both on hH 9 / hC 18; riff only hC 31; both off hC 44.
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 1, stackFrac: 1).hC, 18)
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 1, stackFrac: 0).hC, 44 - reserve)   // 31
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 0, stackFrac: 1).hC, 44 - reserve)   // 31
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 0, stackFrac: 0).hC, 44)
        XCTAssertGreaterThanOrEqual(laneStripBandHeights(T: 44).hC, 16, "§3.2: both-on hC (18) is not under 16")
        // band positions (both on): rail+gap in from each edge; the cells after the full top reserve.
        let xs: [CGFloat] = [0, 20, 40]
        let both = laneStripBandFrames(xs: xs, columnW: 18, T: 44, riffFrac: 1, stackFrac: 1)
        XCTAssertEqual(both.headerY, railH + 1, accuracy: 0.001)                 // 3
        XCTAssertEqual(both.cellsY, reserve, accuracy: 0.001)                    // 13
        XCTAssertEqual(both.footerY, 44 - railH - 1 - 9, accuracy: 0.001)        // 32
        XCTAssertEqual(both.cells[0].minY, 13, accuracy: 0.001); XCTAssertEqual(both.cells[0].height, 18, accuracy: 0.001)
        // riff OFF: no top reserve — the cells extend to the top edge; hC grows.
        let stackOnly = laneStripBandFrames(xs: xs, columnW: 18, T: 44, riffFrac: 0, stackFrac: 1)
        XCTAssertEqual(stackOnly.cellsY, 0, accuracy: 0.001)
        XCTAssertEqual(stackOnly.cells[0].height, 44 - reserve, accuracy: 0.001)   // 31, taller
        // a mid-collapse fraction interpolates the reserve (the ease, §3.4).
        XCTAssertEqual(laneStripBandFrames(xs: xs, columnW: 18, T: 44, riffFrac: 0.5, stackFrac: 1).cellsY, reserve / 2, accuracy: 0.001)
    }

    // §B7.2 — the chip fills its cell's x/width at the band's full height (no shrink, no 30-cap); the 7 pt label fit.
    func testChipFillsItsBand() {
        let b = laneStripBandHeights(T: 44)
        let slot = CGRect(x: 12, y: 0, width: 18, height: b.hH)
        XCTAssertEqual(laneStripChipFrame(slot: slot), slot, "§B2.2: the chip IS its slot — fills the band")
        XCTAssertEqual(laneStripChipFrame(slot: CGRect(x: 0, y: 0, width: 50, height: b.hH)).width, 50, "§B2.2: no 30-cap")
        XCTAssertEqual(laneStripChipLabelSize(steps: 16), 8, "COMPACT+STRIP §4.4: a flat 8 pt label")
        XCTAssertTrue(laneStripChipLabelFits("16", chipWidth: 16, size: 7))                  // 16 ≥ 2·0.6·7 + 2 = 10.4
        XCTAssertFalse(laneStripChipLabelFits("16", chipWidth: 8, size: 7), "hidden under the label width + 2")
    }

    // §B7.3 — a sounding chip is 100 % with an inner #F2F4F7 stroke; resting 78 %; the old outside ring is gone.
    func testSoundingChipMetrics() {
        XCTAssertEqual(LaneStripBandMetrics.chipRestOpacity, 0.78)
        XCTAssertEqual(LaneStripBandMetrics.soundStroke, EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7))
        XCTAssertEqual(LaneStripBandMetrics.chipRadius, 3)   // COMPACT+STRIP §4.4 (was 2)
    }

    // §B7.7 — the button type at the REAL T 44 (the amendment's "name 9" holds only at its scaled 41).
    func testButtonTypeAtT44() {
        let t = euclideousPartPlayType(height: 44, isNotes: false)   // COMPACT+STRIP §4.2: fixed sizes
        XCTAssertEqual(t.nameSize, 10); XCTAssertEqual(t.playSize, 7); XCTAssertEqual(t.lineGap, 3)
    }

    // §10.1 — the top-row frames: w, tiles span T, the bridges sit in their own row only, the chip slots equal the cells.
    func testTopRowFramesAndChipSlotsMatchCells() {
        let T: CGFloat = 44, g: CGFloat = 4, content = CGSize(width: 360, height: 44)
        let nameW: CGFloat = 30                                                              // a measured "STACK" width
        for steps in [8, 12, 16] {
            let f = laneTopRowFrames(T: T, content: content, g: g, stackNameWidth: nameW, steps: steps)
            XCTAssertEqual(f.w, (nameW + 8).rounded(.up), "w = ceil(STACK + 8)")             // §1.3
            XCTAssertEqual(f.leadTile.height, T); XCTAssertEqual(f.trailTile.height, T)      // §1.5 both span T
            XCTAssertEqual(f.leadTile.minX, 0); XCTAssertEqual(f.trailTile.maxX, content.width, accuracy: 0.01)
            // PLAY BUTTONS RAIL+NOTE §3.1: the bands sit rail + gap in from each edge; the bridges sit in their band's row.
            let railH = LaneStripBandMetrics.railH
            XCTAssertEqual(f.headerBridge, CGRect(x: f.leadTile.maxX, y: railH + f.gap, width: g, height: f.hH))
            XCTAssertEqual(f.footerBridge, CGRect(x: f.strip.maxX, y: T - railH - f.gap - f.hH, width: g, height: f.hH))
            // the strip bands
            XCTAssertEqual(f.header.minY, railH + f.gap); XCTAssertEqual(f.header.height, f.hH)
            XCTAssertEqual(f.cells.minY, railH + f.gap + f.hH + f.gap); XCTAssertEqual(f.cells.height, f.hC)
            XCTAssertEqual(f.footer.minY, T - railH - f.gap - f.hH); XCTAssertEqual(f.footer.height, f.hH)
            // §1.6: every step's header slot and footer slot share the cell's x and width
            XCTAssertEqual(f.columnXs.count, steps)
            for i in 0..<steps {
                XCTAssertEqual(f.headerSlot(i).minX, f.cell(i).minX, accuracy: 0.001)
                XCTAssertEqual(f.headerSlot(i).width, f.cell(i).width, accuracy: 0.001)
                XCTAssertEqual(f.footerSlot(i).minX, f.cell(i).minX, accuracy: 0.001)
                XCTAssertEqual(f.footerSlot(i).width, f.cell(i).width, accuracy: 0.001)
                XCTAssertEqual(f.cell(i).height, f.hC)
            }
            // the cells never run under the buttons
            XCTAssertGreaterThanOrEqual(f.cell(0).minX, f.leadTile.maxX)
            XCTAssertLessThanOrEqual(f.cell(steps - 1).maxX, f.trailTile.minX + 0.001)
        }
    }

    // (STACK RANKS GREY ferry 2026-11-15 §1: the lane-hued `stackChipColour` is retired for the neutral grey `stackRankColour`;
    //  its ramp / ink / built-once test moved to StackGreyTests §8.1–3.)

    // §B4 / §B7.4 — rank BARS: inset riff 2 / stack 4 (narrow 1 / 3); bar h = max(1, slot−0.5); stack inside the riff; rank 8 above 1; outline only at slot ≥ 4.
    func testRankMarksInsetsAndOrder() {
        let cell = CGRect(x: 20, y: 0, width: 24, height: 19)                                // hC 19 (T 44, both on) → slot 1.75 < 4 → filled bars
        let riff6 = rankSlotRect(cell: cell, hC: 19, rank: 6, part: .riff)
        let stack6 = rankSlotRect(cell: cell, hC: 19, rank: 6, part: .stack)
        XCTAssertTrue(riff6.filled, "at hC 19 the slot is 1.75 < 4 → a filled bar")
        XCTAssertEqual(riff6.rect.minX, cell.minX + 2); XCTAssertEqual(stack6.rect.minX, cell.minX + 4)   // §B4.2 insets
        XCTAssertEqual(riff6.rect.height, max(1, 1.75 - 0.5), accuracy: 0.001, "§B4.2 bar h = max(1, slot − 0.5) = 1.25")
        XCTAssertGreaterThan(stack6.rect.minX, riff6.rect.minX, "the stack bar is inside the riff's (drawn over it, riff shows at both ends)")
        XCTAssertLessThan(stack6.rect.maxX, riff6.rect.maxX)
        XCTAssertLessThan(rankSlotRect(cell: cell, hC: 19, rank: 8, part: .riff).rect.midY, rankSlotRect(cell: cell, hC: 19, rank: 1, part: .riff).rect.midY)   // rank 8 above rank 1
        // §3.5 / §B4.1: a bar's height scales with hC, so it stays PROPORTIONAL as the cells grow when the other part is off.
        let tall = rankSlotRect(cell: CGRect(x: 20, y: 0, width: 24, height: 31), hC: 31.5, rank: 6, part: .riff)   // riff only → hC 31.5
        XCTAssertGreaterThan(tall.rect.height, riff6.rect.height, "§3.5: the bar grows with the taller cells")
        // §B4.3: a cell under 12 wide tightens the insets to riff 1 / stack 3
        let narrow = CGRect(x: 0, y: 0, width: 10, height: 19)
        XCTAssertEqual(rankSlotRect(cell: narrow, hC: 19, rank: 6, part: .riff).rect.minX, narrow.minX + 1)
        XCTAssertEqual(rankSlotRect(cell: narrow, hC: 19, rank: 6, part: .stack).rect.minX, narrow.minX + 3)
        // §B4.4: only where the slot is ≥ 4 (the spec's reference T 78, both on → hC 39 → slot 4.25) is it a stroked OUTLINE, not a bar
        XCTAssertFalse(rankSlotRect(cell: CGRect(x: 0, y: 0, width: 24, height: 39), hC: 39, rank: 6, part: .riff).filled)
    }

    // §10.9 — a hit cell is lane100 @ 30 % (45 % at the playhead) with the bar; no cell is ever 100 % or glows.
    func testCellLooks() {
        // LANE STRIP CLARITY §5: a hit fills the opaque even hit colour (looked up by lane + playhead), not lane100 at an alpha.
        XCTAssertEqual(stripCellLook(isHit: true, isPlayhead: false), LaneCellLook(fill: .hit(atPlayhead: false), bar: true))
        XCTAssertEqual(stripCellLook(isHit: true, isPlayhead: true), LaneCellLook(fill: .hit(atPlayhead: true), bar: true))
        XCTAssertEqual(stripCellLook(isHit: false, isPlayhead: false), LaneCellLook(fill: .step, bar: false))
        XCTAssertEqual(stripCellLook(isHit: false, isPlayhead: true), LaneCellLook(fill: .playheadStep, bar: false))
        // (CLARITY §5: the hit fill is opaque by design now — the old below-100 % alpha check is superseded by the §8.8 contrast test.)
    }

    // §3.3/§3.4/§4.4/§4.6 — the sounding held sets: rings/outlines map a note's onset to its step; outs==0 is excluded.
    func testSounding() {
        func note(_ on: Double, end: Double?, rank: Int, outs: UInt8 = 1) -> NoteRollNote {
            NoteRollNote(onBeat: on, endBeat: end, pitch: 60, velocity: 100, outs: outs, rank: UInt8(rank))
        }
        let step: (Double) -> Int = { Int($0) }                                   // onset beat == step index, for the test
        let riff = [note(2, end: nil, rank: 4), note(9, end: 9.1, rank: 1)]        // step 2 held (sounds); step 9 ended before now
        let stack = [note(3, end: nil, rank: 5), note(3, end: nil, rank: 2),       // step 3: a two-voice chord, both sounding
                     note(1, end: 1.5, rank: 7),                                   // step 1: played earlier this pass, now silent
                     note(5, end: nil, rank: 6, outs: 0)]                          // step 5: routed nowhere → ignored
        let s = laneStripSounding(riffHeld: riff, stackHeld: stack, n: 8, now: 4.0, passBeats: 8.0, stepOf: step, hitSteps: [1, 2, 3, 5])
        XCTAssertTrue(s.riffRing[2])
        XCTAssertEqual(s.riffRing.filter { $0 }.count, 1, "only the held riff note at step 2 rings (the one at beat 9 is in the future)")
        XCTAssertEqual(s.stackChip[3], 2, "the footer chip is the LOWEST rank played on the step")
        XCTAssertTrue(s.stackRing[3]); XCTAssertEqual(Set(s.stackOutline[3]), [2, 5], "one outline per sounding voice")
        XCTAssertEqual(s.stackChip[1], 7, "a hit played this pass keeps its chip after its note-off")
        XCTAssertFalse(s.stackRing[1]); XCTAssertTrue(s.stackOutline[1].isEmpty, "but no ring or outline once silent")
        XCTAssertNil(s.stackChip[5], "a note routed nowhere (outs 0) is ignored")
    }

    // §B7.1 / §B1 — every footer chip and rank mark sits on its OWN hit's step, snapped from one shared fn — even
    // when the onset maps one step early (the old floor bug) or lands late (a long gate, TIE, ratchet, delayed pool).
    func testSlotsSitOnTheirHitStep() {
        func note(_ on: Double, rank: Int) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: nil, pitch: 60, velocity: 100, outs: 1, rank: UInt8(rank)) }
        let hits = [0, 4, 8, 12, 15]                                   // a 16-step lane hitting (1-based) 1, 5, 9, 13, 16
        let oneEarly: (Double) -> Int = { max(0, Int($0) - 1) }        // reproduce the floored-comet "one step early"
        let stack = hits.map { note(Double($0), rank: 3) }
        let s = laneStripSounding(riffHeld: [], stackHeld: stack, n: 16, now: 20.0, passBeats: 16.0, stepOf: oneEarly, hitSteps: hits)
        for h in hits { XCTAssertEqual(s.stackChip[h], 3, "footer chip snaps onto hit \(h), not one early") }
        for i in 0..<16 where !hits.contains(i) { XCTAssertNil(s.stackChip[i], "no chip on the non-hit step \(i)") }
        // §B1.3: a late note (onset drifts toward step 5) still belongs to its hit's step (4).
        let late = laneStripSounding(riffHeld: [], stackHeld: [note(4.6, rank: 2)], n: 16, now: 20.0, passBeats: 16.0, stepOf: { Int($0.rounded()) }, hitSteps: hits)
        XCTAssertEqual(late.stackChip[4], 2, "a late/ratcheted/delayed note stays in its hit's (4) slot")
        XCTAssertNil(late.stackChip[5], "not on the step its onset drifted to")
    }

    func testGapStackLandsOnItsOwnStepNotTheNearestHit() {   // STACK WHEN ferry §6.1
        func note(_ on: Double, rank: Int) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: nil, pitch: 60, velocity: 100, outs: 1, rank: UInt8(rank)) }
        let hits = [0, 2, 4, 5, 7]                       // the example lane; gaps on 1, 3, 6
        let gap = note(1.0, rank: 3)                     // a stack note on gap step 1
        let step: (Double) -> Int = { Int($0.rounded()) }
        // GAP off (stackSteps nil): the stack still snaps to the nearest hit (0), never the gap step — the old behaviour, unchanged
        let off = laneStripSounding(riffHeld: [], stackHeld: [gap], n: 8, now: 2.0, passBeats: 8.0, stepOf: step, hitSteps: hits)
        XCTAssertNil(off.stackChip[1], "GAP off: the gap step has no chip (snapped to a hit)")
        XCTAssertEqual(off.stackChip[0], 3, "GAP off: snapped onto hit 0")
        // GAP on (every step allowed): the gap stack draws under its OWN step 1
        let on = laneStripSounding(riffHeld: [], stackHeld: [gap], n: 8, now: 2.0, passBeats: 8.0, stepOf: step, hitSteps: hits, stackSteps: Array(0..<8))
        XCTAssertEqual(on.stackChip[1], 3, "GAP on: the gap stack is drawn under its own gap step (1)")
    }

    // PLAY BUTTONS RAIL+NOTE §4.3/§4.5/§4.6 — the chip the tile shows in place of PLAY: the most-recent note-on's hit chip
    // (riff) + that hit's ranks (stack split); sounding while held; nil before the first note-on (⇒ PLAY).
    func testPartNoteChip() {
        func note(_ on: Double, end: Double? = nil, rank: Int, outs: UInt8 = 1) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: end, pitch: 60, velocity: 100, outs: outs, rank: UInt8(rank)) }
        let hits: [EuclideousStripHit] = [EuclideousStripHit(kind: .rhythmRest),
                                          EuclideousStripHit(kind: .hit, chip: EuclideousStripChip(rank: 6, column: 3, hollow: false, grey: false), column: 3),
                                          EuclideousStripHit(kind: .rhythmRest),
                                          EuclideousStripHit(kind: .hit, chip: EuclideousStripChip(rank: 4, column: 1, hollow: false, grey: false), column: 1)]
        let hitSteps = [1, 3], step: (Double) -> Int = { Int($0) }
        XCTAssertNil(euclideousPartNoteChip(held: [], hits: hits, stepOf: step, hitSteps: hitSteps, now: 10), "§4.6 no note-on → PLAY")
        let a = euclideousPartNoteChip(held: [note(1, rank: 6), note(3, rank: 4)], hits: hits, stepOf: step, hitSteps: hitSteps, now: 3.5)
        XCTAssertEqual(a?.chip, EuclideousStripChip(rank: 4, column: 1, hollow: false, grey: false), "§4.5 the newest note-on's hit chip")
        XCTAssertEqual(a?.ranks, [4]); XCTAssertEqual(a?.sounding, true)
        let chord = euclideousPartNoteChip(held: [note(3, rank: 5), note(3, rank: 2)], hits: hits, stepOf: step, hitSteps: hitSteps, now: 3.5)
        XCTAssertEqual(chord?.ranks, [2, 5], "§4.3 every voice on the hit, ascending"); XCTAssertEqual(chord?.chip?.column, 1)
        let ended = euclideousPartNoteChip(held: [note(3, end: 3.2, rank: 4)], hits: hits, stepOf: step, hitSteps: hitSteps, now: 3.5)
        XCTAssertEqual(ended?.chip?.column, 1); XCTAssertEqual(ended?.sounding, false, "§4.4 persists after note-off, sounding false (drawn at 78 %)")
        XCTAssertNil(euclideousPartNoteChip(held: [note(3, rank: 4, outs: 0)], hits: hits, stepOf: step, hitSteps: hitSteps, now: 3.5), "routed nowhere (outs 0) → ignored")
    }

    // PLAY BUTTONS RAIL+NOTE §5 — the predicted-stack-ranks guards (the real prediction's engine match is in StackGridLiveTests):
    // notes layer off / empty pool / no walk config / a POLY lane all return empty ⇒ the #2B2D33 placeholder.
    func testStripStackRanksGuards() {
        let hits: [EuclideousStripHit] = [EuclideousStripHit(kind: .hit, column: 1, tick: 0)]
        var line = EuclidLine(noteSel: .all)
        XCTAssertEqual(euclideousStripStackRanks(line: line, pool: [60, 64, 67], cfg: nil, hits: hits, lapStartTick: 0, lane: 0, ranks: [1], poly: nil), [[]], "notes layer off → empty")
        line.notesOn = true; line.litNotes = 0b0000_0001
        XCTAssertEqual(euclideousStripStackRanks(line: line, pool: [60], cfg: nil, hits: hits, lapStartTick: 0, lane: 0, ranks: [1], poly: nil), [[]], "no walk config → empty")
        XCTAssertEqual(euclideousStripStackRanks(line: line, pool: [], cfg: nil, hits: hits, lapStartTick: 0, lane: 0, ranks: [1], poly: nil), [[]], "empty pool → empty")
    }

    // §5.3/§5.4 — the CC trace maps the emitter's bar curve onto the steps: value→y (127 top, 0 above the bar), beat→x.
    func testCCStripTrace() {
        let cellXs: [CGFloat] = [0, 20, 40, 60]                                    // 4 steps, pitch 20
        let cells = CGRect(x: 0, y: 10, width: 80, height: 20)                     // value 0 → y 27 (maxY − bar 3), value 127 → y 10 (top)
        let t = laneCCStripTrace(dots: [CGPoint(x: 1.0, y: 127), CGPoint(x: 3.0, y: 0)], sub: 1.0, barBeats: 4.0,
                                 cellXs: cellXs, columnW: 18, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4,
                                 playheadStepFloat: 2.0, playheadValue: 64, value: { _ in 64.0 })
        XCTAssertFalse(t.line.isEmpty)
        let yFor64 = cells.minY + (1 - 64.0 / 127) * (cells.height - 3)
        for p in t.line { XCTAssertEqual(p.y, yFor64, accuracy: 0.5) }             // a constant value is a flat line
        XCTAssertEqual(t.line.first!.x, 0, accuracy: 0.01)
        XCTAssertEqual(t.dots.first!.x, 20, accuracy: 0.5); XCTAssertEqual(t.dots.first!.y, cells.minY, accuracy: 0.5)   // hit at step 1, value 127 → top
        XCTAssertEqual(t.dots.last!.x, 60, accuracy: 0.5); XCTAssertEqual(t.dots.last!.y, cells.maxY - 3, accuracy: 0.5) // hit at step 3, value 0 → above the bar
        XCTAssertEqual(t.playhead!.x, 40, accuracy: 0.5)                           // stepFloat 2 → cell 2's left edge
        XCTAssertNil(laneCCStripTrace(dots: [], sub: 1, barBeats: 4, cellXs: cellXs, columnW: 18, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4, value: { _ in nil }).playhead)
    }

    // CC DIRECTION (2026-11-12) — the trace + dots run through euclidCometPos, so they follow the direction-aware playhead:
    // FWD byte-identical; BKW mirrored; ping-pong over the full 2n cycle.
    func testCCStripTraceRespectsDirection() {
        let cellXs: [CGFloat] = [0, 20, 40, 60]                                    // 4 steps, pitch 20, width 80
        let cells = CGRect(x: 0, y: 10, width: 80, height: 20)
        func tr(_ dir: EuclidDir, dots: [CGPoint] = []) -> LaneCCStripTrace {
            laneCCStripTrace(dots: dots, sub: 1.0, barBeats: 4.0, cellXs: cellXs, columnW: 20, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4, dir: dir, value: { $0 * 10 })
        }
        // a hit at beat 1: FWD sits at cell 1 (x 20); BKW where the playhead is at beat 1 — euclidCometPos(1,.bkw)=3 → x 60
        XCTAssertEqual(tr(.fwd, dots: [CGPoint(x: 1, y: 100)]).dots.first!.x, 20, accuracy: 0.5)
        XCTAssertEqual(tr(.bkw, dots: [CGPoint(x: 1, y: 100)]).dots.first!.x, 60, accuracy: 0.5)
        // FWD is byte-identical to the default (no dir)
        let def = laneCCStripTrace(dots: [], sub: 1.0, barBeats: 4.0, cellXs: cellXs, columnW: 20, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4, value: { $0 * 10 })
        XCTAssertEqual(tr(.fwd).line, def.line)
        // BKW: the same per-sample y as FWD, mirrored in x (the FWD and BKW x's sum to the full width)
        let fwd = tr(.fwd).line, bkw = tr(.bkw).line
        XCTAssertEqual(fwd.count, bkw.count)
        for j in 0..<fwd.count {
            XCTAssertEqual(fwd[j].y, bkw[j].y, accuracy: 0.01)
            XCTAssertEqual(fwd[j].x + bkw[j].x, 80, accuracy: 0.5, "the BKW curve is the FWD curve mirrored in x")
        }
        XCTAssertGreaterThan(tr(.pingpong).line.count, fwd.count, "ping-pong samples the full 2n cycle")
    }

    // §5.1 — the CC source: first routed-and-CC-on in A–D order; none → nil.
    func testCCSourceEmitter() {
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b0110, ccOn: 0b0100), 2)                 // routes to B,C; CC on C → C
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1111, ccOn: 0b1111), 0)                 // first wins → A
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1010, ccOn: 0b1010), 1)                 // routes to B,D; both CC on → B
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0001, ccOn: 0b0000))                      // routed, but CC off → none
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0000, ccOn: 0b1111))                      // routed nowhere → none
    }
}
