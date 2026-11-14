//  AltCard.swift — ALT ferry (2026-11-14) §5: the ALT tab's lane-card layout, pure (Foundation + CoreGraphics) so `AltCardLayoutTests` reads the exact frames the view draws. All rects are in the body's coordinate space (x 0 = the body's leading edge, y 0 = its top). BW = the body width (≈ 361), B = its height (≈ 233).

import CoreGraphics

/// §5.4 — one band's inner frames (RIFF or STACK), in body coordinates. The part tile at the leading edge, then a 4-column grid (OUT pill · tokens · OCT pill · OCT boxes over VEL pill · VEL slider · GATE pill · GATE slider).
struct EuclideousAltBandFrames: Equatable {
    var panel: CGRect            // the grouped panel (the band's whole rect)
    var partTile: CGRect         // 35 wide, full inner height
    var outPill: CGRect, tokens: CGRect, octPill: CGRect, octBoxes: CGRect      // row 1
    var velPill: CGRect, velSlider: CGRect, gatePill: CGRect, gateSlider: CGRect // row 2
}
struct EuclideousAltCardLayout: Equatable {
    /// §5.1's fallback ladder: the full rows, then the two bands shrink equally to a 75 floor; `cantFit` if even that is too short.
    enum Case: Equatable { case full, bandsShrunk, cantFit }
    var size: CGSize
    var unitPanel: CGRect
    var unitSegments: [CGRect]   // 4 equal UNIT segments (STEP · HIT · BAR · PASS), 186 wide together
    var mainStepper: CGRect, altStepper: CGRect
    var cycleStrip: CGRect       // the strip's rect; cells are laid out by `euclideousAltCycleCells`
    var riff: EuclideousAltBandFrames
    var stack: EuclideousAltBandFrames
    var appliedCase: Case
}

enum EuclideousAltCardMetrics {
    static let unitRowH: CGFloat = 42, gap: CGFloat = 5, cycleH: CGFloat = 13, bandH: CGFloat = 83, bandFloor: CGFloat = 75
    static let panelInset: CGFloat = 4, unitGroupW: CGFloat = 186
    static let pillW: CGFloat = 31, pillH: CGFloat = 22, partTileW: CGFloat = 35, tokensW: CGFloat = 118, octPillW: CGFloat = 31
    static let colGap: CGFloat = 4, rowGap: CGFloat = 4, row1H: CGFloat = 35, row2H: CGFloat = 31, controlH: CGFloat = 31
    /// §5.1 total of the full layout.
    static var fullTotal: CGFloat { unitRowH + gap + cycleH + gap + bandH + gap + bandH }   // = 236
}

func euclideousAltCardLayout(size: CGSize) -> EuclideousAltCardLayout {
    typealias M = EuclideousAltCardMetrics
    let BW = max(1, size.width), B = size.height
    // §5.1: shrink the two bands equally from the shortfall, down to the 75 floor; report when even that doesn't fit.
    let shortfall = max(0, M.fullTotal - B)
    let bandH = max(M.bandFloor, M.bandH - shortfall / 2)
    let applied: EuclideousAltCardLayout.Case = shortfall <= 1e-9 ? .full : (M.bandH - shortfall / 2 >= M.bandFloor - 1e-9 ? .bandsShrunk : .cantFit)
    // rows, top to bottom (§5.1 order). The unit row and cycle strip keep their heights; spare space (if B > the needed total) falls at the bottom.
    let unitPanel = CGRect(x: 0, y: 0, width: BW, height: M.unitRowH)
    let cycleY = M.unitRowH + M.gap
    let cycleStrip = CGRect(x: 0, y: cycleY, width: BW, height: M.cycleH)
    let riffY = cycleY + M.cycleH + M.gap
    let stackY = riffY + bandH + M.gap
    // §5.2 the UNIT row's inner content: the 4-segment UNIT group (186), then MAIN + ALT steppers sharing the remaining inner width equally, all `gap` (5) apart, inside the 4-inset panel.
    let uInnerX = M.panelInset, uInnerY = M.panelInset, uInnerH = M.unitRowH - 2 * M.panelInset, uInnerW = BW - 2 * M.panelInset
    let segTotalW = M.unitGroupW, segW = (segTotalW - 2 * 3 - 3 * 3) / 4   // the HIT|STEP group's 3 pt container padding (each side) + 3 pt inter-segment gaps (4 segments)
    let unitSegments = (0..<4).map { CGRect(x: uInnerX + 3 + CGFloat($0) * (segW + 3), y: uInnerY + (uInnerH - 22) / 2, width: segW, height: 22) }   // the group's own 3 pt inset; segments 22 tall, centred
    let stepperAreaX = uInnerX + segTotalW + M.gap
    let stepperAreaW = max(1, uInnerW - segTotalW - M.gap)
    let stepperW = (stepperAreaW - M.gap) / 2
    let mainStepper = CGRect(x: stepperAreaX, y: uInnerY, width: stepperW, height: uInnerH)
    let altStepper = CGRect(x: stepperAreaX + stepperW + M.gap, y: uInnerY, width: stepperW, height: uInnerH)
    // §5.4 one band
    func band(_ y: CGFloat) -> EuclideousAltBandFrames {
        let panel = CGRect(x: 0, y: y, width: BW, height: bandH)
        let ix = M.panelInset, iy = y + M.panelInset, iw = BW - 2 * M.panelInset, ih = bandH - 2 * M.panelInset
        let partTile = CGRect(x: ix, y: iy, width: M.partTileW, height: ih)
        let gx = ix + M.partTileW + M.gap                  // the grid starts `gap` after the tile
        let c0 = gx, c1 = c0 + M.pillW + M.colGap, c2 = c1 + M.tokensW + M.colGap, c3 = c2 + M.octPillW + M.colGap
        let col3W = max(1, ix + iw - c3)
        // §5.4 two rows (35 then 31, 4 apart), centred vertically; if they don't fit (a shrunk band), scale them toward the §5.1 floor (31/28, gap 5.5).
        let fullRows = M.row1H + M.rowGap + M.row2H       // 70
        let r1H: CGFloat, r2H: CGFloat, rGap: CGFloat
        if ih >= fullRows - 1e-9 { r1H = M.row1H; r2H = M.row2H; rGap = M.rowGap }
        else { rGap = 5.5; let avail = max(1, ih - rGap); r1H = avail * M.row1H / (M.row1H + M.row2H); r2H = avail * M.row2H / (M.row1H + M.row2H) }
        let rowsTop = iy + max(0, (ih - (r1H + rGap + r2H)) / 2)
        let r2y = rowsTop + r1H + rGap
        func pill(_ x: CGFloat, _ rowY: CGFloat, _ rowH: CGFloat, w: CGFloat = M.pillW) -> CGRect { CGRect(x: x, y: rowY + (rowH - M.pillH) / 2, width: w, height: M.pillH) }
        func ctrl(_ x: CGFloat, _ rowY: CGFloat, _ rowH: CGFloat, w: CGFloat, h: CGFloat = M.controlH) -> CGRect { CGRect(x: x, y: rowY + (rowH - h) / 2, width: w, height: h) }
        return EuclideousAltBandFrames(
            panel: panel, partTile: partTile,
            outPill: pill(c0, rowsTop, r1H), tokens: ctrl(c1, rowsTop, r1H, w: M.tokensW, h: r1H), octPill: pill(c2, rowsTop, r1H), octBoxes: ctrl(c3, rowsTop, r1H, w: col3W),
            velPill: pill(c0, r2y, r2H), velSlider: ctrl(c1, r2y, r2H, w: M.tokensW), gatePill: pill(c2, r2y, r2H), gateSlider: ctrl(c3, r2y, r2H, w: col3W))
    }
    return EuclideousAltCardLayout(size: size, unitPanel: unitPanel, unitSegments: unitSegments, mainStepper: mainStepper, altStepper: altStepper,
                                   cycleStrip: cycleStrip, riff: band(riffY), stack: band(stackY), appliedCase: applied)
}

/// §5.3 — the cycle strip's cells: L = main + alt cells across `strip.width`, 3 pt apart, equal, in the strip's own coordinates (x relative to `strip.minX`).
func euclideousAltCycleCells(main: Int, alt: Int, strip: CGRect) -> [CGRect] {
    let m = max(1, main), a = max(1, alt), L = m + a
    let gap: CGFloat = 3
    let w = max(1, (strip.width - CGFloat(L - 1) * gap) / CGFloat(L))
    return (0..<L).map { CGRect(x: strip.minX + CGFloat($0) * (w + gap), y: strip.minY, width: w, height: strip.height) }
}
