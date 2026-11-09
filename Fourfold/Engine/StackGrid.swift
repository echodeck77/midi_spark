//  StackGrid.swift — STACK GRID ferry (2026-11-08): the riff grid panel's second tab. Four columns (one per Euclid lane, in lane-card order) by eleven rows — TOP, TOP−1, TOP−2, then ranks 8 … 1 — of toggle cells that read and write the SAME lit order
//  (`EuclidLine.litOrderResolved`, `euclideousToggleLitPosition`) the NOTES tab's keys do: there is no state of the grid's own. Foundation only, on purpose (the macOS test target compiles this file directly): which stored position a cell stands for, whether
//  it is on, what it writes, which note it names and where every frame goes are decided — and tested — here; the views paint these and nothing else.

import Foundation

// MARK: - the rows

/// One row of the grid. `.rank(r)` is the lane's pool rank r (1 … 8, the same ranks the NOTES keys and the riff grid's label column name); `.top` is the NOTES tab's TOP key (the highest received note, however many are held); `.topMinus1` and
/// `.topMinus2` are the second and third highest received notes.
enum EuclideousStackRow: Equatable {
    case top, topMinus1, topMinus2
    case rank(Int)

    /// The axis label: "TOP", "TOP−1", "TOP−2", "8" … "1".
    var label: String {
        switch self { case .top: return "TOP"; case .topMinus1: return "TOP\u{2212}1"; case .topMinus2: return "TOP\u{2212}2"; case .rank(let r): return String(r) }
    }
    /// How far below the highest received note a TOP row sits (0, 1, 2); nil for a rank row.
    var belowTop: Int? {
        switch self { case .top: return 0; case .topMinus1: return 1; case .topMinus2: return 2; case .rank: return nil }
    }
    /// VoiceOver: "top", "top minus 1", "top minus 2", "rank 3".
    var spoken: String {
        switch self { case .top: return "top"; case .topMinus1: return "top minus 1"; case .topMinus2: return "top minus 2"; case .rank(let r): return "rank \(r)" }
    }
}
/// Top to bottom: ranks 8 down to 1. (TOP / TOP−1 / TOP−2 were removed 2026-11-09 — Paul: the stack shows only ranks; the `.top` / `.topMinus1` / `.topMinus2` cases and their helpers stay compiled but are no longer in the grid.)
let euclideousStackGridRows: [EuclideousStackRow] = (1...8).reversed().map { EuclideousStackRow.rank($0) }

// MARK: - what a cell stands for

extension EuclideousStackRow {
    /// The lit-order position this cell reads and writes (0-7 = ranks 1-8, 9 = TOP — the NOTES keys' own numbering), for a lane whose pool holds `poolCount` received notes. A rank row is its rank; TOP is the TOP key; TOP−1 and TOP−2 are the pool ranks
    /// n − 1 and n − 2 — nil (no cell can be lit or written) when the pool has no such rank, or when it lies beyond rank 8 (the selection holds ranks 1-8 and TOP only). TOP 2, the NOTES tab's pair key, has no row of its own.
    func position(poolCount n: Int) -> Int? {
        switch self {
        case .rank(let r): return (1...8).contains(r) ? r - 1 : nil
        case .top: return EuclideousLitOrder.topPosition
        case .topMinus1, .topMinus2:
            let rank = n - (belowTop ?? 0)
            return (1...8).contains(rank) ? rank - 1 : nil
        }
    }
    /// The raw MIDI note this cell names for a lane's pool (nil: nothing to name — the cell shows an en dash). A rank row names the pool's rank as the NOTES keys do (past the received notes it is an octave copy); the TOP rows name the highest,
    /// second-highest and third-highest received notes.
    func note(pool: EuclideousLanePoolNotes) -> Int? {
        let sorted = pool.notes.sorted()
        switch self {
        case .rank(let r):
            let extended = euclideousGlobalPoolExtended(sortedRaw: sorted.map { Int($0) })
            return r >= 1 && r <= extended.count ? extended[r - 1] : nil
        case .top:       return pool.count >= 1 ? Int(pool.top) : nil
        case .topMinus1: return pool.count >= 2 ? Int(pool.top2) : nil
        case .topMinus2: return pool.count >= 3 && sorted.count >= 3 ? Int(sorted[sorted.count - 3]) : nil
        }
    }
}

/// Is this cell on: the lane's lit order holds the position the cell stands for.
func euclideousStackCellIsOn(_ line: EuclidLine, row: EuclideousStackRow, poolCount: Int) -> Bool {
    guard let p = row.position(poolCount: poolCount) else { return false }
    return line.litOrderResolved.contains(p)
}
/// A tap on a cell: the NOTES tab's own action on the position the cell stands for (so a tap on an off notes layer also turns it on, exactly as a NOTES key does). A cell with no position writes nothing. Returns whether it wrote.
@discardableResult
func euclideousStackCellToggle(_ line: inout EuclidLine, row: EuclideousStackRow, poolCount: Int) -> Bool {
    guard let p = row.position(poolCount: poolCount) else { return false }
    euclideousToggleLitPosition(&line, position: p)
    return true
}

// MARK: - the frames

/// The grid inside the riff panel's box (`euclideousRiffPanelLayout`'s own chrome — the 8 pt padding, the switch row, the 6 pt under it): the lane column headers, the axis, 11 rows of 4 cells. Panel coordinates, (0,0) the panel's top-left.
struct EuclideousStackGridLayout: Equatable {
    var box: CGSize
    var labelW: CGFloat, tabRowH: CGFloat
    var headerH: CGFloat, headerGap: CGFloat
    var rowH: CGFloat, rowGap: CGFloat, colGap: CGFloat, colW: CGFloat
    /// Where the lane column headers start (y) and where the first row starts.
    var headerTop: CGFloat, rowsTop: CGFloat
    /// The first column's left edge: after the axis and its gap.
    var colsLeft: CGFloat
    var rowCount: Int { euclideousStackGridRows.count }
    func axis(_ row: Int) -> CGRect { CGRect(x: EuclideousRiffPanelMetrics.padding, y: rowsTop + CGFloat(row) * (rowH + rowGap), width: labelW, height: rowH) }
    func header(_ lane: Int) -> CGRect { CGRect(x: colsLeft + CGFloat(lane) * (colW + colGap), y: headerTop, width: colW, height: headerH) }
    func cell(row: Int, lane: Int) -> CGRect { CGRect(x: colsLeft + CGFloat(lane) * (colW + colGap), y: rowsTop + CGFloat(row) * (rowH + rowGap), width: colW, height: rowH) }
    /// The note name's size in a cell: 55 % of the row, 7 … 11 pt, to the half point.
    var cellFontSize: CGFloat { max(7, min(11, (rowH * 0.55 * 2).rounded() / 2)) }
    var headerFontSize: CGFloat { max(7, min(10, (headerH * 0.6 * 2).rounded() / 2)) }
    /// Height the panel's rows would need to reach `minRowH` — a box under this is drawn at the formula's values (nothing shrinks the rows below their share).
    static let minRowH: CGFloat = 14
    var belowFloor: Bool { rowH < Self.minRowH }
}
func euclideousStackGridLayout(box: CGSize) -> EuclideousStackGridLayout {
    typealias M = EuclideousRiffPanelMetrics
    let base = euclideousRiffPanelLayout(box: box)   // the label column's width and the switch row's height: the same fair-share rules as the riff grid, so the axis lines up with the riff grid's label column
    let headerH: CGFloat = 16, headerGap: CGFloat = 4, rowGap: CGFloat = 3, colGap: CGFloat = M.colGap
    let headerTop = M.padding + base.tabRowH + M.tabToGrid
    let rowsTop = headerTop + headerH + headerGap
    let rows = CGFloat(euclideousStackGridRows.count)
    let avail = box.height - rowsTop - M.padding
    let rowH = max(1, (avail - rowGap * (rows - 1)) / rows)
    let colsLeft = M.padding + base.labelW + M.labelGap
    let colW = max(1, (box.width - M.padding - colsLeft - colGap * 3) / 4)
    return EuclideousStackGridLayout(box: box, labelW: base.labelW, tabRowH: base.tabRowH, headerH: headerH, headerGap: headerGap, rowH: rowH, rowGap: rowGap, colGap: colGap, colW: colW,
                                     headerTop: headerTop, rowsTop: rowsTop, colsLeft: colsLeft)
}

// MARK: - the panel's header switch

/// The riff panel's two views, in the header switch. RIFF is the default; the choice is UI state — never saved, never an undo step.
enum EuclideousRiffPanelTab: Int, CaseIterable, Equatable {
    case riff = 0, stack = 1
    static let opening: EuclideousRiffPanelTab = .riff
    var label: String { self == .riff ? "RIFF" : "STACK" }
    var spoken: String { self == .riff ? "Riff" : "Stack" }
}

// MARK: - the axis

/// The axis chip for a row: a rank row is the chip's own rank-number look (the corner-less number in the label's type, as an empty pool draws every rank), a TOP row the chip's TOP label with the suffix — the same box as the NOTES keys and the riff grid's labels.
func euclideousStackAxisSpec(_ row: EuclideousStackRow) -> EuclideousRankChipSpec {
    switch row {
    case .rank(let r): return EuclideousRankChipSpec(rank: r, topKind: 0, received: true, lit: false, empty: true, name: String(r), cornerNumber: false)
    case .top:         return EuclideousRankChipSpec(rank: 0, topKind: 2, received: true, lit: false, empty: false, name: "", cornerNumber: false)
    case .topMinus1:   return EuclideousRankChipSpec(rank: 0, topKind: 3, received: true, lit: false, empty: false, name: "", cornerNumber: false)
    case .topMinus2:   return EuclideousRankChipSpec(rank: 0, topKind: 4, received: true, lit: false, empty: false, name: "", cornerNumber: false)
    }
}
