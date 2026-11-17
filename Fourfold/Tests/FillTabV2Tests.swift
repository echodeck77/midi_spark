//  FillTabV2Tests.swift — FILL TAB V2 (2026-11-17) §3/§4/§5/§8: the pure layer — the roll-row and control-row frames at
//  the reference and under shrink, the cell internals, the segment/stepper maths and texts, the §5 neutrality predicates,
//  and the VoiceOver strings. (§7.10's interaction wiring is the page's one-tap funnels over these setters.)

import XCTest

final class FillTabV2Tests: XCTestCase {

    // MARK: §3.1/§4.1 — the reference layout (360 × 231) is exact: 69.5 + 4 + 4×36 + 3×4.5 = 231.

    func testReferenceLayoutFrames() {
        let L = euclideousFillTabV2Layout(box: CGSize(width: 360, height: 231), loop: 8)
        XCTAssertFalse(L.shrunkRows); XCTAssertFalse(L.shrunkRoll)
        XCTAssertEqual(L.fillTile, CGRect(x: 0, y: 0, width: 52, height: 69.5))
        XCTAssertEqual(L.loopTile, CGRect(x: 317, y: 0, width: 43, height: 69.5))
        XCTAssertEqual(L.cellsStrip.minX, 55); XCTAssertEqual(L.cellsStrip.width, 259, accuracy: 1e-9)
        XCTAssertEqual(L.cells.count, 8)
        XCTAssertEqual(L.cells[0].width, (259 - 14) / 8, accuracy: 1e-9)          // ≈ 30.6
        XCTAssertEqual(L.cells[7].maxX, 314, accuracy: 1e-9)
        // row 1 starts 4 below the roll; rows 36 tall, 4.5 apart; columns (360 − 13.5) / 4 ≈ 86.6; two-col ≈ 177.6
        XCTAssertEqual(L.speed.minY, 73.5); XCTAssertEqual(L.speed.height, 36)
        XCTAssertEqual(L.colW, (360 - 13.5) / 4, accuracy: 1e-9)
        XCTAssertEqual(L.twoColW, L.colW * 2 + 4.5, accuracy: 1e-9)
        XCTAssertEqual(L.speed.width, L.twoColW, accuracy: 1e-9)
        XCTAssertEqual(L.rush.maxX, 360, accuracy: 1e-9)
        XCTAssertEqual(L.hits.minX, L.colW * 2 + 9, accuracy: 1e-9)
        XCTAssertEqual(L.land.maxX, 360, accuracy: 1e-9)
        XCTAssertEqual(L.brk.width, (L.colW - 2.5) / 2, accuracy: 1e-9)           // §4.1 ≈ 41
        XCTAssertEqual(L.swell.maxY, 231, accuracy: 1e-9)                          // the last row ends at the reference height
    }

    func testCellWidthsAtEveryLoop() {
        for (loop, w) in [(4, (259.0 - 6) / 4), (8, (259.0 - 14) / 8), (16, (259.0 - 30) / 16)] {
            let L = euclideousFillTabV2Layout(box: CGSize(width: 360, height: 231), loop: loop)
            XCTAssertEqual(L.cells.count, loop)
            XCTAssertEqual(L.cells[0].width, w, accuracy: 1e-9, "loop \(loop)")   // 63.25 / 30.625 / 14.3125
        }
    }

    // §4.1 — under 231 the rows shrink first (min 30), then the roll row (min 52); everything still draws.
    func testShortLayoutsShrinkRowsThenRoll() {
        let a = euclideousFillTabV2Layout(box: CGSize(width: 360, height: 215), loop: 8)
        XCTAssertTrue(a.shrunkRows); XCTAssertFalse(a.shrunkRoll)
        XCTAssertEqual(a.rowH, (215 - 69.5 - 4 - 13.5) / 4, accuracy: 1e-9)       // 32
        XCTAssertEqual(a.rollH, 69.5)
        let b = euclideousFillTabV2Layout(box: CGSize(width: 360, height: 196), loop: 8)
        XCTAssertTrue(b.shrunkRows); XCTAssertTrue(b.shrunkRoll)
        XCTAssertEqual(b.rowH, 30); XCTAssertEqual(b.rollH, 196 - 4 - 120 - 13.5, accuracy: 1e-9)   // 58.5
        let c = euclideousFillTabV2Layout(box: CGSize(width: 360, height: 160), loop: 8)
        XCTAssertEqual(c.rollH, 52, "the roll row never goes below 52")
        XCTAssertEqual(c.rowH, 30, "the rows never go below 30")
    }

    // MARK: §3.4 cell internals

    func testCellInternals() {
        let s = CGSize(width: 30.625, height: 69.5)
        let chip = euclideousFillV2CellChip(cellSize: s)
        XCTAssertEqual(chip, CGRect(x: 2, y: 69.5 - 15, width: 26.625, height: 12))
        let area = euclideousFillV2CellNotesArea(cellSize: s)
        XCTAssertEqual(area.minY, 3.5); XCTAssertEqual(area.maxY, chip.minY - 2, accuracy: 1e-9)
        let p = euclideousFillV2CellProgress(cellSize: s, fraction: 0.5)
        XCTAssertEqual(p.minX, 3); XCTAssertEqual(p.width, (30.625 - 6) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.height, 1.5); XCTAssertEqual(p.maxY, 69.5 - 0.5, accuracy: 1e-9)
    }

    // MARK: §4.3/§4.4 the control rows' inner frames

    func testSegAndStepperFrames() {
        let row = euclideousFillV2SegRow(tileSize: CGSize(width: 177.75, height: 36))
        XCTAssertEqual(row, CGRect(x: 4, y: 36 - 4 - 19, width: 169.75, height: 19))
        let five = euclideousFillV2SegFrames(row: row, count: 5)
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five[0].width, (169.75 - 8) / 5, accuracy: 1e-9)
        XCTAssertEqual(five[4].maxX, row.maxX, accuracy: 1e-9)
        let s = euclideousFillV2StepperFrames(row: row)
        XCTAssertEqual(s.minus.width, 20); XCTAssertEqual(s.plus.width, 20)
        XCTAssertEqual(s.value.minX, 20 + 2 + row.minX, accuracy: 1e-9)
        let r = euclideousFillV2RanksFrames(row: row)
        XCTAssertEqual(r.climb.width, 28); XCTAssertEqual(r.arch.minX, r.climb.maxX + 2, accuracy: 1e-9)
        XCTAssertEqual(r.minus.minX, r.arch.maxX + 3, accuracy: 1e-9)
        XCTAssertEqual(r.minus.width, 22); XCTAssertEqual(r.plus.maxX, row.maxX, accuracy: 1e-9)
    }

    // MARK: the segment values — §4.3 orders, writes, and §5.1 neutrality

    func testSegIndexSetAndNeutrality() {
        var l = EuclidLine()
        XCTAssertEqual(euclideousFillV2SegIndex(.speed, l), 1, "×1 — the AMEND 1 default")
        XCTAssertEqual(euclideousFillV2SegIndex(.hits, l), 1, "ALL — the AMEND 1 default")
        XCTAssertEqual(euclideousFillV2SegIndex(.notes, l), 0)
        euclideousFillV2SegSet(.speed, 4, &l); XCTAssertEqual(l.fillSpeedResolved, 4)
        euclideousFillV2SegSet(.length, 0, &l); XCTAssertEqual(l.fillLengthResolved, 2, "leading ¼ = stored 2")
        euclideousFillV2SegSet(.length, 2, &l); XCTAssertEqual(l.fillLengthResolved, 0, "trailing BAR = stored 0")
        euclideousFillV2SegSet(.order, 4, &l); XCTAssertEqual(l.fillOrderResolved, .stutter); XCTAssertNil(l.fillReverse)
        euclideousFillV2SegSet(.hits, 3, &l); XCTAssertEqual(l.fillHitsResolved, .build)
        euclideousFillV2SegSet(.notes, 2, &l); XCTAssertEqual(l.fillNotesResolved, .pedal)
        // §5.1 neutrality: SPEED ×1, ORDER FWD, HITS KEEP, NOTES RIFF; LENGTH always
        XCTAssertTrue(euclideousFillV2SegIsNeutral(.speed, index: 1)); XCTAssertFalse(euclideousFillV2SegIsNeutral(.speed, index: 3))
        XCTAssertTrue(euclideousFillV2SegIsNeutral(.length, index: 0)); XCTAssertTrue(euclideousFillV2SegIsNeutral(.length, index: 2))
        XCTAssertTrue(euclideousFillV2SegIsNeutral(.order, index: 0)); XCTAssertFalse(euclideousFillV2SegIsNeutral(.order, index: 4))
        XCTAssertTrue(euclideousFillV2SegIsNeutral(.hits, index: 0)); XCTAssertFalse(euclideousFillV2SegIsNeutral(.hits, index: 1))
        XCTAssertTrue(euclideousFillV2SegIsNeutral(.notes, index: 0)); XCTAssertFalse(euclideousFillV2SegIsNeutral(.notes, index: 1))
    }

    // MARK: the steppers — ranges, clamps, texts, defaults, §5.2 neutrality

    func testStepperValuesAndTexts() {
        var l = EuclidLine()
        euclideousFillV2StepSet(.ranks, 9, &l); XCTAssertEqual(l.fillRanksResolved, 7, "clamped, no wrap")
        euclideousFillV2StepSet(.ranks, -9, &l); XCTAssertEqual(l.fillRanksResolved, -7)
        XCTAssertEqual(euclideousFillV2StepText(.ranks, l), "\u{2212}7")
        euclideousFillV2StepSet(.swell, 3, &l); XCTAssertEqual(euclideousFillV2StepText(.swell, l), "+3")
        euclideousFillV2StepSet(.roll, 0, &l); XCTAssertEqual(euclideousFillV2StepText(.roll, l), "OFF")
        euclideousFillV2StepSet(.roll, 5, &l); XCTAssertEqual(l.fillRollResolved, 4)
        euclideousFillV2StepSet(.chance, 1, &l); XCTAssertEqual(l.fillChanceResolved, 50); XCTAssertEqual(euclideousFillV2StepText(.chance, l), "50%")
        euclideousFillV2StepSet(.chance, EuclideousFillV2Step.chance.defaultValue, &l)
        XCTAssertTrue(euclideousFillV2StepIsNeutral(.chance, l), "CHANCE 100% is the neutral value (§5.2)")
        euclideousFillV2StepSet(.ranks, 0, &l); XCTAssertTrue(euclideousFillV2StepIsNeutral(.ranks, l))
        euclideousFillV2StepSet(.ranks, 2, &l); XCTAssertFalse(euclideousFillV2StepIsNeutral(.ranks, l))
        // §5.1 — the shape pair is neutral while RANKS is 0
        euclideousFillV2StepSet(.ranks, 0, &l); XCTAssertTrue(euclideousFillV2ShapeIsNeutral(l))
        euclideousFillV2StepSet(.ranks, 3, &l); XCTAssertFalse(euclideousFillV2ShapeIsNeutral(l))
    }

    // MARK: §8 VoiceOver

    func testVoiceOverStrings() {
        XCTAssertEqual(euclideousFillV2CellAX(bar: 3, on: true, current: true, plays: true), "Fill bar 4, on, current, fill plays")
        XCTAssertEqual(euclideousFillV2CellAX(bar: 3, on: true, current: false, plays: false), "Fill bar 4, on, skipped")
        XCTAssertEqual(euclideousFillV2CellAX(bar: 0, on: false, current: false, plays: nil), "Fill bar 1, off")
        XCTAssertEqual(euclideousFillV2SegAX(.speed, index: 3), "Speed, times two")
        XCTAssertEqual(euclideousFillV2SegAX(.order, index: 4), "Order, stutter")
        XCTAssertEqual(euclideousFillV2SegAX(.notes, index: 2), "Notes, pedal")
        var l = EuclidLine(); euclideousFillV2StepSet(.ranks, 3, &l)
        XCTAssertEqual(euclideousFillV2StepAX(.ranks, l), "Fill ranks, plus three")
        XCTAssertEqual(euclideousFillV2ToggleAX("rush", on: true), "Fill rush, on")
        XCTAssertEqual(euclideousFillV2ToggleAX("break", on: false), "Fill break, off")
        XCTAssertEqual(euclideousFillV2LoopAX(8), "Fill loop, 8 bars")
    }

    // MARK: §3.7 — the prediction's cost at 16 bars (reported in the ferry's report-back; a loose ceiling here)

    func testSixteenBarPredictionCost() {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false
        l.fillLoop = 16; l.fillBars = (0..<16).map { $0 % 2 == 0 }; l.fillSpeed = 4; l.fillLength = 0; l.fillRoll = 2
        var buf = [Bool](repeating: false, count: 64); var micro = [Double](repeating: 0, count: 64)
        let n = euclideousBuildHitPatternInto(l, cells: &buf, micro: &micro)
        var cfg = EuclideousWalkLaneConfig(buf: Array(buf.prefix(n)), n: n, dir: .fwd, sub: 0.5)
        cfg.riffDir = .forward; cfg.length = 8; cfg.stride = 1; cfg.rotate = 0; cfg.every = 1; cfg.columns = 8; cfg.gate = 0.5
        let pool = [60, 62, 64, 65, 67, 69, 71]
        let t0 = Date()
        var total = 0
        for b in 0..<16 {
            total += euclideousFillRollBar(cfg: cfg, line: l, lane: 0, pool: pool, riffOct: 0, baseVel: 90,
                                           ranks: [1, 2, 3, 4, 5, 6, 7, 8], bar: b, beatsPerBar: 4, originBeat: 0).notes.count
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(ms, 50, "16 bars of a ×4 BAR fill with ROLL predicted in under 50 ms (measured: \(String(format: "%.2f", ms)) ms)")
        print("FILL TAB V2 §3.7: 16-bar prediction = \(String(format: "%.2f", ms)) ms, \(total) notes")
    }
}
