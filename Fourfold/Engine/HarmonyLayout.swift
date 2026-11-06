//  HarmonyLayout.swift — INPUTS + HARMONY ferry (2026-11-06) §4–§5: the HARMONY page's frames, in page coordinates. Foundation + CoreGraphics only, so the macOS target pins every number the views draw (test 12).
//  `block` is the four lane cards' union (769.33 × 610 landscape / 782 × 611.33 portrait at the 1190 reference — the ferry's 756 × 606 is the chords-page ferry's wrong figure; source wins). Content is `block` inset by 16.
//  Every frame below is CONTENT-relative unless it says "column-relative".

import Foundation
import CoreGraphics

enum EuclideousHarmonyMetrics {
    static let padding: CGFloat = 16                 // 4.1
    static let titleH: CGFloat = 36                  // 5.1
    static let rootGapAbove: CGFloat = 12            // 5.2
    static let rootH: CGFloat = 52
    static let rootKeyGap: CGFloat = 4
    static let rootRadius: CGFloat = 7
    static let scaleGapAbove: CGFloat = 4            // 5.3
    static let scaleH: CGFloat = 30
    static let scaleChipGap: CGFloat = 3
    static let scaleChipMinW: CGFloat = 44           // narrower than this ⇒ two rows
    static let scaleRadius: CGFloat = 6
    static let chordsGapAbove: CGFloat = 22          // 5.4
    static let chordsHeadingH: CGFloat = 24
    static let columnsGapAbove: CGFloat = 8          // 5.5
    static let columnGap: CGFloat = 16
    static let gridTitleH: CGFloat = 26              // 5.6
    static let stripGapAbove: CGFloat = 8            // 5.5 title → strip
    static let stripH: CGFloat = 12                  // 5.7
    static let gridGapAbove: CGFloat = 4             // 5.5 strip → grid
    static let gridLabelW: CGFloat = 32              // 5.8
    static let labelGap: CGFloat = 4
    static let cellGap: CGFloat = 3
    static let rowGap: CGFloat = 3
    static let restExtra: CGFloat = 5                // "REST with 5 extra above it" — read as 5 pt of extra gap above the REST row (flagged in the report)
    static let bandGapAbove: CGFloat = 16            // 5.10
    static let bandH: CGFloat = 36
    static let popoverTopOffset: CGFloat = 6         // 5.9: 6 below the title row
    static let popoverPad: CGFloat = 10
    static let popoverRowGap: CGFloat = 8
    static let popoverLabelW: CGFloat = 58
    static let popoverRowH: CGFloat = 26             // the ADVANCE / RESTART rows' own height (chords page 5.3 / 5.4)
    static let pickKeyH: CGFloat = 52                // 5.11 the existing PICK editor's key height
    static let pickStepperW: CGFloat = 84
    static let pickPopoverGapBelow: CGFloat = 6      // 5.11: its bottom 6 above the PICK strip
    static let closeSize: CGFloat = 28, closeTarget: CGFloat = 44
    static let diatonicRows = 12                     // CHORDS shows rows 0…11 (7 diatonic, 4 borrowed, REST)
    static let colourRows = 6                        // COLOUR shows the six colour rows (12…17)
}

/// What the grids show (UI state, 1.6).
enum EuclideousHarmonyRows: Int, CaseIterable { case chords = 0, colour = 1
    var label: String { self == .chords ? "CHORDS" : "COLOUR" }
    var spoken: String { self == .chords ? "Chord rows" : "Colour rows" }
    /// The first grid row index (in the 18-row model) this mode draws, and how many it draws.
    var firstRow: Int { self == .chords ? 0 : 12 }
    var rowCount: Int { self == .chords ? EuclideousHarmonyMetrics.diatonicRows : EuclideousHarmonyMetrics.colourRows }
}

struct EuclideousHarmonyLayout: Equatable {
    var block: CGSize
    var content: CGRect                      // block inset by 16 (page coordinates)
    var titleRow: CGRect                     // content-relative
    var closeTarget: CGRect                  // 44 × 44 centred on the 28 × 28 button, trailing edge of the title row
    var rootRow: CGRect
    var rootKeyW: CGFloat
    var scaleRows: [CGRect]                  // one row, or two when a chip would be narrower than 44
    var scaleChipW: CGFloat
    var scalePerRow: Int
    var chordsHeading: CGRect
    var columnW: CGFloat
    var column0: CGRect, column1: CGRect     // content-relative; both the same height
    var gridH: CGFloat                       // column-relative grid height
    var pickStrip: CGRect, midiStrip: CGRect // the bottom band, content-relative
    // column-relative ys
    var gridTitleY: CGFloat { 0 }
    var stripY: CGFloat { EuclideousHarmonyMetrics.gridTitleH + EuclideousHarmonyMetrics.stripGapAbove }
    var gridY: CGFloat { stripY + EuclideousHarmonyMetrics.stripH + EuclideousHarmonyMetrics.gridGapAbove }

    /// Row height for a mode: the grid's height split equally among the mode's rows after the row gaps (and, in CHORDS, the extra above REST).
    func rowH(_ rows: EuclideousHarmonyRows) -> CGFloat {
        let m = EuclideousHarmonyMetrics.self
        let n = CGFloat(rows.rowCount)
        let gaps = (n - 1) * m.rowGap + (rows == .chords ? m.restExtra : 0)
        return max(0, (gridH - gaps) / n)
    }
    /// The top of the `position`-th row of a mode (0 = the first drawn); in CHORDS REST (position 11) carries `restExtra` more above it.
    func rowTop(_ rows: EuclideousHarmonyRows, position p: Int) -> CGFloat {
        let m = EuclideousHarmonyMetrics.self
        return CGFloat(p) * (rowH(rows) + m.rowGap) + (rows == .chords && p >= m.diatonicRows - 1 ? m.restExtra : 0)
    }
    /// A grid's cell width for `steps` columns (c = max(8, STEPS)): 37.96 at 8 and 17.48 at 16 at the landscape reference.
    func cellW(steps: Int) -> CGFloat {
        let m = EuclideousHarmonyMetrics.self
        let c = CGFloat(max(8, min(16, steps)))
        return max(0, (columnW - m.gridLabelW - m.labelGap - (c - 1) * m.cellGap) / c)
    }
    func columnLeft(steps: Int, _ col: Int) -> CGFloat {
        let m = EuclideousHarmonyMetrics.self
        return m.gridLabelW + m.labelGap + CGFloat(col) * (cellW(steps: steps) + m.cellGap)
    }
    /// 5.9: a pill's popover — the column's width, its top 6 below the title row (content-relative), `popoverHeight` tall.
    func pillPopover(set: Int) -> CGRect {
        let m = EuclideousHarmonyMetrics.self
        let col = set == 0 ? column0 : column1
        return CGRect(x: col.minX, y: col.minY + m.gridTitleH + m.popoverTopOffset, width: col.width, height: euclideousHarmonyPopoverHeight)
    }
    /// 5.11: the PICK editor's popover — the PICK strip's width, its bottom 6 above the strip.
    var pickPopover: CGRect {
        let m = EuclideousHarmonyMetrics.self
        return CGRect(x: pickStrip.minX, y: pickStrip.minY - m.pickPopoverGapBelow - euclideousHarmonyPickPopoverHeight, width: pickStrip.width, height: euclideousHarmonyPickPopoverHeight)
    }
}

/// 5.9: padding 10 + the ADVANCE row + 8 + the RESTART row + padding 10.
let euclideousHarmonyPopoverHeight: CGFloat = 2 * EuclideousHarmonyMetrics.popoverPad + 2 * EuclideousHarmonyMetrics.popoverRowH + EuclideousHarmonyMetrics.popoverRowGap
/// 5.11: padding 10 + the key row (52) + padding 10.
let euclideousHarmonyPickPopoverHeight: CGFloat = 2 * EuclideousHarmonyMetrics.popoverPad + EuclideousHarmonyMetrics.pickKeyH

/// §4.3 / §5: the page in the lane-cards block. `scaleCount` is `ScaleType.allCases.count` (13).
func euclideousHarmonyLayout(block: CGSize, scaleCount: Int = 13) -> EuclideousHarmonyLayout {
    let m = EuclideousHarmonyMetrics.self
    let content = CGRect(x: m.padding, y: m.padding, width: max(0, block.width - 2 * m.padding), height: max(0, block.height - 2 * m.padding))
    let w = content.width
    var y: CGFloat = 0
    let titleRow = CGRect(x: 0, y: y, width: w, height: m.titleH)
    let closeTarget = CGRect(x: w - m.closeTarget, y: y + (m.titleH - m.closeTarget) / 2, width: m.closeTarget, height: m.closeTarget)
    y += m.titleH + m.rootGapAbove
    let rootRow = CGRect(x: 0, y: y, width: w, height: m.rootH)
    let rootKeyW = max(0, (w - 11 * m.rootKeyGap) / 12)
    y += m.rootH + m.scaleGapAbove
    // 5.3: one row; narrower than 44 per chip ⇒ two rows of equal-width chips (the first row takes the odd one)
    let n = max(1, scaleCount)
    let oneRowW = max(0, (w - CGFloat(n - 1) * m.scaleChipGap) / CGFloat(n))
    let wrapped = oneRowW < m.scaleChipMinW && n > 1
    let perRow = wrapped ? (n + 1) / 2 : n
    let chipW = wrapped ? max(0, (w - CGFloat(perRow - 1) * m.scaleChipGap) / CGFloat(perRow)) : oneRowW
    var scaleRows: [CGRect] = []
    for r in 0..<(wrapped ? 2 : 1) { scaleRows.append(CGRect(x: 0, y: y + CGFloat(r) * (m.scaleH + m.scaleChipGap), width: w, height: m.scaleH)) }
    y += CGFloat(scaleRows.count) * m.scaleH + CGFloat(scaleRows.count - 1) * m.scaleChipGap + m.chordsGapAbove
    let chordsHeading = CGRect(x: 0, y: y, width: w, height: m.chordsHeadingH)
    y += m.chordsHeadingH + m.columnsGapAbove
    let colTop = y
    let bandY = max(colTop, content.height - m.bandH)
    let colBottom = max(colTop, bandY - m.bandGapAbove)
    let colH = colBottom - colTop
    let colW = max(0, (w - m.columnGap) / 2)
    let column0 = CGRect(x: 0, y: colTop, width: colW, height: colH)
    let column1 = CGRect(x: colW + m.columnGap, y: colTop, width: colW, height: colH)
    let gridH = max(0, colH - (m.gridTitleH + m.stripGapAbove + m.stripH + m.gridGapAbove))
    let pickStrip = CGRect(x: 0, y: bandY, width: colW, height: m.bandH)
    let midiStrip = CGRect(x: colW + m.columnGap, y: bandY, width: colW, height: m.bandH)
    return EuclideousHarmonyLayout(block: block, content: content, titleRow: titleRow, closeTarget: closeTarget, rootRow: rootRow, rootKeyW: rootKeyW,
                                   scaleRows: scaleRows, scaleChipW: chipW, scalePerRow: perRow, chordsHeading: chordsHeading, columnW: colW,
                                   column0: column0, column1: column1, gridH: gridH, pickStrip: pickStrip, midiStrip: midiStrip)
}

// MARK: - the pill's popover rows (5.9)

/// The ADVANCE and RESTART rows' widths inside a popover of inner width `innerW`: the chords page's own chips (36 × 26 unit chips, 25 × 26 rate chips 2 apart, 18 pt lane squares 4 apart, a 36 × 26 every chip, a 34 pt switch) with the
/// 58 pt label column. At the reference the natural widths (TIME 344, RESTART 342) are 3.3 / 1.3 pt over the 340.67 pt inner width, so the rate chips and the lane squares give that up — the rest is exactly as the chords page drew it.
struct EuclideousHarmonyPopoverRows: Equatable {
    var innerW: CGFloat
    var labelW: CGFloat
    var unitChipW: CGFloat
    var rateChipW: CGFloat
    var squareW: CGFloat
    var everyW: CGFloat
    var switchW: CGFloat
    /// The rows' natural widths, before any chip gave up width (what the chords page ferry's layout drew in its 360.67 pt column was 342 / 342).
    var naturalAdvanceTime: CGFloat, naturalAdvanceCounted: CGFloat, naturalRestart: CGFloat
    var advanceTimeW: CGFloat { labelW + 4 + 3 * unitChipW + 2 * 4 + 6 + 6 * rateChipW + 5 * 2 }
    var restartW: CGFloat { labelW + 4 + 3 * unitChipW + 2 * 4 + 6 + 4 * squareW + 3 * 4 + 4 + everyW + switchW }
}
func euclideousHarmonyPopoverRows(innerW: CGFloat) -> EuclideousHarmonyPopoverRows {
    let m = EuclideousHarmonyMetrics.self
    let label = m.popoverLabelW, unit: CGFloat = 36, every: CGFloat = 36, sw: CGFloat = 34, rate: CGFloat = 25, square: CGFloat = 18
    let head = label + 4 + (3 * unit + 2 * 4) + 6
    let natTime = head + 6 * rate + 5 * 2
    let natCounted = head + (4 * square + 3 * 4) + 4 + every
    let natRestart = head + (4 * square + 3 * 4) + 4 + every + sw
    let rateW = max(18, min(rate, (innerW - head - 5 * 2) / 6))
    let squareW = max(14, min(square, (innerW - head - 3 * 4 - 4 - every - sw) / 4))
    return EuclideousHarmonyPopoverRows(innerW: innerW, labelW: label, unitChipW: unit, rateChipW: rateW, squareW: squareW, everyW: every, switchW: sw,
                                        naturalAdvanceTime: natTime, naturalAdvanceCounted: natCounted, naturalRestart: natRestart)
}

// MARK: - the pill's widest case (5.6)

/// An estimate of the summary pill's width: 8.5 pt heavy monospaced is ≈ 0.6 em a character plus the 0.06 em tracking, the items 6 apart, padding 10 / 8, 8 × 8 squares, the 1 × 10 divider, the 9 pt glyph and the 10 pt chevron.
func euclideousHarmonyPillEstimatedWidth(_ pill: HarmonyPill) -> CGFloat {
    let charW: CGFloat = 8.5 * 0.66
    func text(_ s: String) -> CGFloat { CGFloat(s.count) * charW }
    var items: [CGFloat] = [text(pill.advanceUnit)]
    if pill.advanceLane != nil { items.append(8) }
    items.append(text(pill.advanceValue))
    if let r = pill.restart {
        items.append(contentsOf: [1, 9, text(r.unit)])
        if r.lane != nil { items.append(8) }
        items.append(text(r.value))
    }
    items.append(10)
    return 10 + 8 + items.reduce(0, +) + CGFloat(items.count - 1) * 6
}
