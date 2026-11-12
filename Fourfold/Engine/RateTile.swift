//  RateTile.swift — RATE ferry (2026-11-12), slice 5: the RATE tile's pure layout (§3) and the current-box / progress maths (§5).
//  The painter (EuclideousPage.rateTile) only draws these frames; this file is Foundation-only and in the test target.

import CoreGraphics

/// §3.2 — every frame of the RATE tile, in tile-local points. `showHeader` is §3.5 (dropped under 72 pt tall).
struct EuclideousRateTileLayout: Equatable {
    var showHeader = true
    var chevron = CGRect.zero, label = CGRect.zero, readout = CGRect.zero
    var freePill = CGRect.zero
    var chips: [CGRect] = []     // 4 brush chips ×½ ×1½ ×2 ×4
    var boxes: [CGRect] = []     // 8 bar boxes
}

/// §3.2/§3.5 — lay the tile out. 6 pt sides; 4 pt top; a 10 pt header (chevron + "RATE" + readout), sp4, an 18 pt chip row
/// (FREE 32 + four equal chips, sp3), sp4, then the 8 boxes (2.5 pt apart, ≥ 28 tall) with a 6 pt bottom. Under 72 pt tall the
/// header row and its sp4 are dropped. Pure, no allocation beyond the two small fixed arrays.
func euclideousRateTileLayout(box: CGSize) -> EuclideousRateTileLayout {
    var L = EuclideousRateTileLayout(showHeader: box.height >= 72)
    let sidePad: CGFloat = 6
    let x0 = sidePad, innerW = max(1, box.width - sidePad * 2)
    var y: CGFloat = 4
    if L.showHeader {
        let headerH: CGFloat = 10
        L.chevron = CGRect(x: x0 + 2, y: y + (headerH - 6.5) / 2, width: 6.5, height: 6.5)
        L.label = CGRect(x: L.chevron.maxX + 3, y: y, width: 44, height: headerH)
        let readoutW: CGFloat = 38
        L.readout = CGRect(x: box.width - sidePad - 2 - readoutW, y: y, width: readoutW, height: headerH)
        y += headerH + 4
    }
    let chipRowH: CGFloat = 18, freeW: CGFloat = 32, chipGap: CGFloat = 3
    L.freePill = CGRect(x: x0, y: y, width: freeW, height: chipRowH)
    let chipsX = L.freePill.maxX + chipGap
    let chipW = max(1, (innerW - freeW - chipGap - chipGap * 3) / 4)
    for i in 0..<4 { L.chips.append(CGRect(x: chipsX + CGFloat(i) * (chipW + chipGap), y: y, width: chipW, height: chipRowH)) }
    y += chipRowH + 4
    let boxH = max(28, box.height - 6 - y)
    let boxGap: CGFloat = 2.5
    let boxW = max(1, (innerW - boxGap * 7) / 8)
    for i in 0..<8 { L.boxes.append(CGRect(x: x0 + CGFloat(i) * (boxW + boxGap), y: y, width: boxW, height: boxH)) }
    return L
}

/// §5.1 — the current box (0…7) for the host beat the page last polled, or nil when the transport is stopped (§4.8).
func euclideousRateCurrentBox(hostBeat: Double?, beatsPerBar: Double) -> Int? {
    guard let b = hostBeat, beatsPerBar > 0 else { return nil }
    let bar = Int((b / beatsPerBar).rounded(.down))
    return ((bar % 8) + 8) % 8
}

/// §4.6 — the fraction of the current bar elapsed (0 at the bar line, → 1 at the next). The progress line reads this.
func euclideousRateBarProgress(hostBeat: Double, beatsPerBar: Double) -> Double {
    guard beatsPerBar > 0 else { return 0 }
    let r = hostBeat.truncatingRemainder(dividingBy: beatsPerBar)
    return (r < 0 ? r + beatsPerBar : r) / beatsPerBar
}

/// §4.2 — the readout: inside an active run, the run's multiplier label in the lane colour; else "×1" grey.
func euclideousRateReadoutLabel(line: EuclidLine, currentBox: Int?) -> String {
    guard line.usesRateOverride, let box = currentBox else { return "\u{00D7}1" }
    return euclideousRateMultiplierLabel(code: line.rateBarsResolved[box])
}

/// The on-screen label for a box/brush code (0 ⇒ ×1 for the readout fallback).
func euclideousRateMultiplierLabel(code: UInt8) -> String {
    switch code { case 1: return "\u{00D7}\u{00BD}"; case 2: return "\u{00D7}1\u{00BD}"; case 3: return "\u{00D7}2"; case 4: return "\u{00D7}4"; default: return "\u{00D7}1" }
}
