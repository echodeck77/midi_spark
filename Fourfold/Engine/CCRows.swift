//  CCRows.swift — CC SLOTS ferry (2026-11-12) §4/§5: the pure layout of the CC tab's three-band rows and the edit
//  page's lane picker. Foundation + CoreGraphics only (test target). Heights / type are the ferry's fixed values;
//  widths follow the real panel (the MUTE roll ferry's grid: four rows 64 tall, 6 apart, 10 below the strip, 12 side padding).

import CoreGraphics

enum EuclideousCCRowsMetrics {
    static let rows = 4, slots = 3
    static let rowH: CGFloat = 64, rowGap: CGFloat = 6, topInset: CGFloat = 10, sidePad: CGFloat = 12
    static let tileW: CGFloat = 36, tileRadius: CGFloat = 8, tokenSize: CGFloat = 28, tileGap: CGFloat = 6
    static let bandH: CGFloat = 20, bandGap: CGFloat = 2, bandRadius: CGFloat = 5
    static let chipW: CGFloat = 30, chipH: CGFloat = 16, chipRadius: CGFloat = 4, chipInset: CGFloat = 3, chipFontSize: CGFloat = 11
}

/// §4.1 — one output row's outer rect in the panel (0-based A…D).
func euclideousCCRowRect(_ i: Int, panel size: CGSize) -> CGRect {
    typealias M = EuclideousCCRowsMetrics
    let w = max(1, size.width - M.sidePad * 2)
    return CGRect(x: M.sidePad, y: M.topInset + CGFloat(i) * (M.rowH + M.rowGap), width: w, height: M.rowH)
}

/// §4.1 — within a row (origin at the row's top-left): the token tile, and the three band rects (slot a on top).
struct EuclideousCCRowLayout: Equatable {
    var tile = CGRect.zero
    var bands: [CGRect] = []     // 3, slot a…c top to bottom
}
func euclideousCCRowLayout(rowWidth w: CGFloat) -> EuclideousCCRowLayout {
    typealias M = EuclideousCCRowsMetrics
    var L = EuclideousCCRowLayout()
    L.tile = CGRect(x: 0, y: 0, width: M.tileW, height: M.rowH)
    let bandX = M.tileW + M.tileGap
    let bandW = max(1, w - bandX)
    L.bands = (0..<M.slots).map { CGRect(x: bandX, y: CGFloat($0) * (M.bandH + M.bandGap), width: bandW, height: M.bandH) }
    return L
}

/// §4.5 — the CC-number chip within a band (origin at the band's top-left).
func euclideousCCChipRect(bandSize: CGSize) -> CGRect {
    typealias M = EuclideousCCRowsMetrics
    return CGRect(x: M.chipInset, y: (bandSize.height - M.chipH) / 2, width: M.chipW, height: M.chipH)
}

// MARK: - §5.4/§5.5 the edit page's lane tab + picker

enum EuclideousCCPickerMetrics {
    static let laneTabW: CGFloat = 16, laneTabH: CGFloat = 14, laneTabRadius: CGFloat = 3, laneTabInset: CGFloat = 4, laneTabFontSize: CGFloat = 9
    static let rowGap: CGFloat = 2
}

/// §5.5 — the four lane-picker rows filling the trace frame (lanes 1…4 top to bottom, 2 pt gaps).
func euclideousCCPickerRowRects(traceSize: CGSize) -> [CGRect] {
    typealias M = EuclideousCCPickerMetrics
    let h = max(1, (traceSize.height - M.rowGap * 3) / 4)
    return (0..<4).map { CGRect(x: 0, y: CGFloat($0) * (h + M.rowGap), width: traceSize.width, height: h) }
}

// MARK: - §6 VoiceOver
private let euclideousCCOutputLetters = ["A", "B", "C", "D"]
/// §6.1: a band button, "Output A, CC 74, lane 1, on".
func euclideousCCBandAX(output o: Int, cc: Int, driverLane: Int, on: Bool) -> String {
    "Output \(euclideousCCOutputLetters[max(0, min(3, o))]), CC \(cc), lane \(driverLane), \(on ? "on" : "off")"
}
/// §6.2: the edit page's trace button, "Driver, lane 1".
func euclideousCCDriverAX(lane: Int) -> String { "Driver, lane \(lane)" }
