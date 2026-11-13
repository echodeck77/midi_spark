//  CCRows.swift — CC SLOTS ferry (2026-11-12) §4/§5: the pure layout of the CC tab's rows and the edit page's lane
//  picker. Foundation + CoreGraphics only (test target). WIDENED 2026-11-13 (Paul): FOUR slots per emitter, laid
//  SIDE BY SIDE across the row (not stacked), each a BIG CC number over its own trace. Rows fill the panel height;
//  widths follow the real panel (12 pt side padding; token tile 36 wide, 6 gap, then the four cells 6 apart).

import CoreGraphics

enum EuclideousCCRowsMetrics {
    static let rows = 4, slots = 4
    static let rowGap: CGFloat = 8, topInset: CGFloat = 10, sidePad: CGFloat = 12, minRowH: CGFloat = 54
    static let tileW: CGFloat = 36, tileRadius: CGFloat = 8, tokenSize: CGFloat = 28, tileGap: CGFloat = 6
    static let cellGap: CGFloat = 6, cellRadius: CGFloat = 6
    // the big number sits in the top `numberHeightFraction` of a cell; the trace fills below it.
    static let numberHeightFraction: CGFloat = 0.5, numberTopPad: CGFloat = 2, traceTopGap: CGFloat = 1
    static let numberMinFont: CGFloat = 14, numberMaxFont: CGFloat = 30
}

/// §4.1 — one output row's outer rect in the panel (0-based A…D). The four rows fill the panel height (so the numbers get the most room).
func euclideousCCRowRect(_ i: Int, panel size: CGSize) -> CGRect {
    typealias M = EuclideousCCRowsMetrics
    let w = max(1, size.width - M.sidePad * 2)
    let avail = max(1, size.height - M.topInset * 2 - M.rowGap * CGFloat(M.rows - 1))
    let rowH = max(M.minRowH, avail / CGFloat(M.rows))
    return CGRect(x: M.sidePad, y: M.topInset + CGFloat(i) * (rowH + M.rowGap), width: w, height: rowH)
}

/// §4.1 — within a row (origin at the row's top-left): the token tile (left, full height), and the four cell rects (slots a…d, left→right).
struct EuclideousCCRowLayout: Equatable {
    var tile = CGRect.zero
    var cells: [CGRect] = []     // 4, slot a…d left to right
}
func euclideousCCRowLayout(rowWidth w: CGFloat, rowHeight h: CGFloat) -> EuclideousCCRowLayout {
    typealias M = EuclideousCCRowsMetrics
    var L = EuclideousCCRowLayout()
    L.tile = CGRect(x: 0, y: 0, width: M.tileW, height: h)
    let x0 = M.tileW + M.tileGap
    let total = max(1, w - x0)
    let cellW = max(1, (total - M.cellGap * CGFloat(M.slots - 1)) / CGFloat(M.slots))
    L.cells = (0..<M.slots).map { CGRect(x: x0 + CGFloat($0) * (cellW + M.cellGap), y: 0, width: cellW, height: h) }
    return L
}

/// §4.5 — within a cell (origin at the cell's top-left): the big CC number (top) and the trace (below).
func euclideousCCCellSplit(cellSize sz: CGSize) -> (number: CGRect, trace: CGRect) {
    typealias M = EuclideousCCRowsMetrics
    let numH = max(16, (sz.height * M.numberHeightFraction).rounded())
    let number = CGRect(x: 0, y: M.numberTopPad, width: sz.width, height: max(1, numH - M.numberTopPad))
    let traceY = numH + M.traceTopGap
    return (number, CGRect(x: 0, y: traceY, width: sz.width, height: max(1, sz.height - traceY)))
}

/// §4.5 — the big number's font size, fitting a 3-digit CC number ("119") in the cell (heavy monospaced ≈ 0.62 em per glyph), capped by the number band's height.
func euclideousCCNumberFontSize(cellSize sz: CGSize) -> CGFloat {
    typealias M = EuclideousCCRowsMetrics
    let byWidth = (sz.width - 6) / (3 * 0.62)
    let byHeight = sz.height * M.numberHeightFraction * 0.82
    return max(M.numberMinFont, min(M.numberMaxFont, min(byWidth, byHeight).rounded()))
}

// MARK: - §5.4/§5.5 the edit page's lane tab + picker

enum EuclideousCCPickerMetrics {
    static let laneTabW: CGFloat = 24, laneTabH: CGFloat = 20, laneTabRadius: CGFloat = 4, laneTabInset: CGFloat = 6, laneTabFontSize: CGFloat = 13
    static let gap: CGFloat = 8, cellRadius: CGFloat = 10, stripMaxH: CGFloat = 36
}

/// §5.5 (rebuilt 2026-11-13) — the lane picker FILLS the panel body as FOUR stacked, FULL-WIDTH rows (the Euclid lanes as the
/// user knows them: horizontal step strips), lanes 1…4 top to bottom, `gap` pt apart. Returns the four row rects in `size`.
func euclideousCCPickerRows(size: CGSize) -> [CGRect] {
    typealias M = EuclideousCCPickerMetrics
    let h = max(1, (size.height - M.gap * 3) / 4)
    return (0..<4).map { CGRect(x: 0, y: CGFloat($0) * (h + M.gap), width: size.width, height: h) }
}

// MARK: - §6 VoiceOver
private let euclideousCCOutputLetters = ["A", "B", "C", "D"]
/// §6.1: a band button, "Output A, CC 74, lane 1, on".
func euclideousCCBandAX(output o: Int, cc: Int, driverLane: Int, on: Bool) -> String {
    "Output \(euclideousCCOutputLetters[max(0, min(3, o))]), CC \(cc), lane \(driverLane), \(on ? "on" : "off")"
}
/// §6.2: the edit page's trace button, "Driver, lane 1".
func euclideousCCDriverAX(lane: Int) -> String { "Driver, lane \(lane)" }
