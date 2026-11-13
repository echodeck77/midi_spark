//  FillBlock.swift — FILL ferry (2026-11-13) §3/§4/§6/§8: the FILL block's pure layout, its tiles' text, the
//  value fields' positions / steps / drag, and the VoiceOver strings. Foundation + CoreGraphics only (test target).
//
//  The block fills the frame the RATE tile had (the lane card's lower-right ~171.84 × 80 landscape / 175 × 80
//  portrait); the LEFT half (the division grid + the note-value column ♩ ♩. ♩3) and the divider are unchanged.
//  Three rows aligned with the note-value column's three cells: the 8 bar tiles, then FILL·SPEED·LENGTH·REVERSE,
//  then RANKS (double width) · SWELL · BREAK. No box/ring/radius of its own — eight separate tiles on the card.

import CoreGraphics

// MARK: - §3 layout

struct EuclideousFillBlockLayout: Equatable {
    var barTiles: [CGRect] = []     // §3.3 row 1: eight bar tiles
    var fill = CGRect.zero          // §3.4 row 2, col 1
    var speed = CGRect.zero         //            col 2
    var length = CGRect.zero        //            col 3
    var reverse = CGRect.zero       //            col 4
    var ranks = CGRect.zero         // §3.5 row 3, cols 1–2 (one tile across both + the gap)
    var swell = CGRect.zero         //            col 3
    var brk = CGRect.zero           //            col 4
    var radius: CGFloat = 6         // §3.6 the note-value cells' radius
    var rowH: CGFloat = 0
}

/// §3.2/§3.3: three rows at the note-value column's y/height (rowH = (H − 2·gap)/3 = 24.67 at 80, gap 3 — the
/// SOURCE value, NOT the spec's "~29 / 4.5"); row 1 eight bar tiles 2.5 apart; rows 2–3 four columns `gridGap`(3) apart.
func euclideousFillBlockLayout(box: CGSize) -> EuclideousFillBlockLayout {
    var L = EuclideousFillBlockLayout()
    let rowGap: CGFloat = 3        // = the note-value column's gridGap (patternRateHalf)
    let colGap: CGFloat = 3        // = the division grid's column gap (SOURCE; the spec's 4.5 is wrong)
    let barGap: CGFloat = 2.5      // §3.3
    let rowH = max(1, (box.height - rowGap * 2) / 3)
    L.rowH = rowH
    func rowY(_ i: Int) -> CGFloat { CGFloat(i) * (rowH + rowGap) }
    let barW = max(1, (box.width - barGap * 7) / 8)
    L.barTiles = (0..<8).map { CGRect(x: CGFloat($0) * (barW + barGap), y: rowY(0), width: barW, height: rowH) }
    let colW = max(1, (box.width - colGap * 3) / 4)
    func col(_ c: Int) -> CGFloat { CGFloat(c) * (colW + colGap) }
    L.fill = CGRect(x: col(0), y: rowY(1), width: colW, height: rowH)
    L.speed = CGRect(x: col(1), y: rowY(1), width: colW, height: rowH)
    L.length = CGRect(x: col(2), y: rowY(1), width: colW, height: rowH)
    L.reverse = CGRect(x: col(3), y: rowY(1), width: colW, height: rowH)
    L.ranks = CGRect(x: col(0), y: rowY(2), width: colW * 2 + colGap, height: rowH)   // §3.5 spans cols 1–2 + the gap
    L.swell = CGRect(x: col(2), y: rowY(2), width: colW, height: rowH)
    L.brk = CGRect(x: col(3), y: rowY(2), width: colW, height: rowH)
    return L
}

// MARK: - §4.3/§4.4/§6 the value fields (SPEED · LENGTH · RANKS · SWELL)

enum EuclideousFillField: CaseIterable {
    case speed, length, ranks, swell
    var label: String { switch self { case .speed: return "SPEED"; case .length: return "LENGTH"; case .ranks: return "RANKS"; case .swell: return "SWELL" } }
    var bipolar: Bool { self == .ranks || self == .swell }        // §4.3 RANKS / SWELL add TILT's centre line
    var count: Int { switch self { case .speed: return 5; case .length: return 3; case .ranks: return 15; case .swell: return 7 } }
    /// §1.1 default, as a leading→trailing index.
    var defaultIndex: Int { switch self { case .speed: return 3; case .length: return 1; case .ranks: return 7; case .swell: return 3 } }
}

/// The field's current value as a leading→trailing index (§4.3 order: SPEED ×½…×4, LENGTH ¼ ½ BAR, RANKS −7…+7, SWELL −3…+3).
func euclideousFillFieldIndex(_ f: EuclideousFillField, _ line: EuclidLine) -> Int {
    switch f {
    case .speed: return line.fillSpeedResolved                    // stored 0…4 = ×½…×4 (already leading→trailing)
    case .length: return 2 - line.fillLengthResolved              // stored 0=BAR,1=½,2=¼ → leading ¼ = index 0
    case .ranks: return line.fillRanksResolved + 7
    case .swell: return line.fillSwellResolved + 3
    }
}

/// Write a leading→trailing index back into the lane (clamped). The ONE setter the tap, the drag and the reset use.
func euclideousFillSetFieldIndex(_ f: EuclideousFillField, _ idx: Int, _ line: inout EuclidLine) {
    let i = max(0, min(f.count - 1, idx))
    switch f {
    case .speed: line.fillSpeed = UInt8(i)
    case .length: line.fillLength = UInt8(2 - i)
    case .ranks: line.fillRanks = Int8(i - 7)
    case .swell: line.fillSwell = Int8(i - 3)
    }
}

/// §4.3: the value marker's position across the tile's inner width (0 leading … 1 trailing).
func euclideousFillFieldFraction(_ f: EuclideousFillField, _ line: EuclidLine) -> Double {
    f.count <= 1 ? 0 : Double(euclideousFillFieldIndex(f, line)) / Double(f.count - 1)
}

private func euclideousFillSigned(_ n: Int) -> String { n == 0 ? "0" : (n > 0 ? "+\(n)" : "\u{2212}\(abs(n))") }   // U+2212 minus

/// §4.4: the value text. SPEED "×½"/"×1"/"×1½"/"×2"/"×4"; LENGTH "¼"/"½"/"BAR"; RANKS/SWELL signed.
func euclideousFillFieldValueText(_ f: EuclideousFillField, _ line: EuclidLine) -> String {
    let i = euclideousFillFieldIndex(f, line)
    switch f {
    case .speed: return ["\u{00D7}\u{00BD}", "\u{00D7}1", "\u{00D7}1\u{00BD}", "\u{00D7}2", "\u{00D7}4"][i]   // ×½ ×1 ×1½ ×2 ×4
    case .length: return ["\u{00BC}", "\u{00BD}", "BAR"][i]                                                  // ¼ ½ BAR
    case .ranks: return euclideousFillSigned(i - 7)
    case .swell: return euclideousFillSigned(i - 3)
    }
}

/// §6.3 TAP HALVES: a tap on the leading half steps toward the leading end (index − 1); the trailing half toward the
/// trailing end (index + 1); clamped, no wrap. `fracX` is 0…1 across the tile.
func euclideousFillFieldTapStep(_ f: EuclideousFillField, _ line: EuclidLine, fracX: Double) -> Int {
    let cur = euclideousFillFieldIndex(f, line)
    return max(0, min(f.count - 1, cur + (fracX < 0.5 ? -1 : 1)))
}

/// §6.3 DRAG (as OFFSET's absolute-position drag): the index the touch at `fracX` (0…1 across the tile, inset-adjusted by the caller) selects.
func euclideousFillFieldDragIndex(_ f: EuclideousFillField, fracX: Double) -> Int {
    max(0, min(f.count - 1, Int((Double(f.count - 1) * max(0, min(1, fracX))).rounded())))
}

// MARK: - §8 VoiceOver (U+2019 apostrophes where needed — none here)

func euclideousFillBarAX(_ n: Int, on: Bool, current: Bool) -> String {
    "Fill bar \(n + 1), \(on ? "on" : "off")" + (current ? ", current" : "")
}
func euclideousFillToggleAX(_ on: Bool) -> String { "Fill, \(on ? "on" : "off")" }
func euclideousFillBoolAX(_ which: String, on: Bool) -> String { "Fill \(which), \(on ? "on" : "off")" }   // which = "reverse" / "break"
/// §8.3: "Fill speed, times two" / "Fill length, half" / "Fill ranks, plus three" / "Fill swell, minus two".
func euclideousFillFieldAX(_ f: EuclideousFillField, _ line: EuclidLine) -> String {
    let i = euclideousFillFieldIndex(f, line)
    let v: String
    switch f {
    case .speed: v = ["times one half", "times one", "times one and a half", "times two", "times four"][i]
    case .length: v = ["quarter", "half", "bar"][i]
    case .ranks: v = euclideousFillSpokenSigned(i - 7)
    case .swell: v = euclideousFillSpokenSigned(i - 3)
    }
    return "Fill \(f.label.lowercased()), \(v)"
}
private let euclideousFillNumberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
private func euclideousFillSpokenSigned(_ n: Int) -> String {   // §8.3 spells the number ("plus three", "minus two")
    let word = euclideousFillNumberWords[min(euclideousFillNumberWords.count - 1, abs(n))]
    return n == 0 ? "zero" : (n > 0 ? "plus \(word)" : "minus \(word)")
}
