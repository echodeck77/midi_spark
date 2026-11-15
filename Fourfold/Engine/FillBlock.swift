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
    // §3.1 bar row (the loop's worth of bars) + the 4/8/16 loop chip at the trailing end
    var barTiles: [CGRect] = []
    var loopChip = CGRect.zero
    var barCount = 8
    // §5 the live-preview strip (zero-height when the card is too short)
    var preview = CGRect.zero
    // §3.4 the 12 control tiles, grouped by function (Paul 2026-11-14):
    var fill = CGRect.zero          // row 1
    var speed = CGRect.zero
    var length = CGRect.zero
    var order = CGRect.zero
    var ranks = CGRect.zero         // row 2
    var swell = CGRect.zero
    var hits = CGRect.zero
    var roll = CGRect.zero
    var chance = CGRect.zero        // row 3
    var brk = CGRect.zero
    var land = CGRect.zero
    var spare = CGRect.zero         // row 3, col 4 — reserved
    // §4.4 the two mini chips (top-trailing, their own hit area)
    var curveChip = CGRect.zero
    var shapeChip = CGRect.zero
    var radius: CGFloat = 6
    var rowH: CGFloat = 0
    var previewH: CGFloat = 0
}

/// FILL TAB ferry (2026-11-14) §3: the FILL tab fills the whole card. A 28 pt bar row (the `loop` bars 2.5 apart) with a
/// trailing loop chip; a preview strip (50 pt, 36 under a 200 pt card, gone under 180); then THREE control rows of four
/// equal columns (4.5 apart). The curve / shape chips sit in SPEED's / RANKS's top-trailing corner (13 pt, their own hit area).
func euclideousFillBlockLayout(box: CGSize, loop: Int = 8) -> EuclideousFillBlockLayout {
    var L = EuclideousFillBlockLayout()
    let n = max(1, loop)
    L.barCount = n
    let gap: CGFloat = 3          // the column / section gap
    let rowGap: CGFloat = 4.5     // §3.1 the control rows' gap
    let barGap: CGFloat = 2.5     // §3.1 the bar tiles' gap
    let barRowH: CGFloat = 28
    let loopChipW: CGFloat = 34
    // §5 preview height: 50, 36 on a short (< 200) card, nothing under 180
    L.previewH = box.height < 180 ? 0 : (box.height < 200 ? 36 : 50)
    // §3.1 bar row
    let barAreaW = max(1, box.width - loopChipW - gap)
    let barW = max(1, (barAreaW - barGap * CGFloat(n - 1)) / CGFloat(n))
    L.barTiles = (0..<n).map { CGRect(x: CGFloat($0) * (barW + barGap), y: 0, width: barW, height: barRowH) }
    L.loopChip = CGRect(x: box.width - loopChipW, y: 0, width: loopChipW, height: barRowH)
    var y = barRowH + gap
    if L.previewH > 0 { L.preview = CGRect(x: 0, y: y, width: box.width, height: L.previewH); y += L.previewH + gap }
    // §3.4 three control rows of four equal columns
    let controlTop = y
    let rowH = max(1, (box.height - controlTop - rowGap * 2) / 3)
    L.rowH = rowH
    func rowY(_ i: Int) -> CGFloat { controlTop + CGFloat(i) * (rowH + rowGap) }
    let colW = max(1, (box.width - gap * 3) / 4)
    func col(_ c: Int) -> CGFloat { CGFloat(c) * (colW + gap) }
    func cell(_ c: Int, _ r: Int) -> CGRect { CGRect(x: col(c), y: rowY(r), width: colW, height: rowH) }
    L.fill = cell(0, 0); L.speed = cell(1, 0); L.length = cell(2, 0); L.order = cell(3, 0)
    L.ranks = cell(0, 1); L.swell = cell(1, 1); L.hits = cell(2, 1); L.roll = cell(3, 1)
    L.chance = cell(0, 2); L.brk = cell(1, 2); L.land = cell(2, 2); L.spare = cell(3, 2)
    // §4.4 the curve / shape chips — top-trailing, 13 pt
    let chip: CGFloat = 13
    L.curveChip = CGRect(x: L.speed.maxX - chip - 2, y: L.speed.minY + 2, width: chip, height: chip)
    L.shapeChip = CGRect(x: L.ranks.maxX - chip - 2, y: L.ranks.minY + 2, width: chip, height: chip)
    return L
}

// MARK: - §4.3/§4.4/§6 the value fields (SPEED · LENGTH · RANKS · SWELL)

enum EuclideousFillField: CaseIterable {
    case speed, length, ranks, swell, roll, chance   // FILL TAB ferry (2026-11-14): ROLL (§2.5) and CHANCE (§2.7) are value tiles too
    var label: String { switch self { case .speed: return "SPEED"; case .length: return "LENGTH"; case .ranks: return "RANKS"; case .swell: return "SWELL"; case .roll: return "ROLL"; case .chance: return "CHANCE" } }
    var bipolar: Bool { self == .ranks || self == .swell }        // §4.3 RANKS / SWELL add TILT's centre line (ROLL / CHANCE are unipolar)
    var count: Int { switch self { case .speed: return 5; case .length: return 3; case .ranks: return 15; case .swell: return 7; case .roll: return 5; case .chance: return 4 } }
    /// §1.1 default, as a leading→trailing index.
    var defaultIndex: Int { switch self { case .speed: return 3; case .length: return 1; case .ranks: return 7; case .swell: return 3; case .roll: return 0; case .chance: return 3 } }
}

private let euclideousFillChanceSteps = [25, 50, 75, 100]   // CHANCE's four stored values, leading→trailing

/// The field's current value as a leading→trailing index (§4.3 order: SPEED ×½…×4, LENGTH ¼ ½ BAR, RANKS −7…+7, SWELL −3…+3, ROLL 0…4, CHANCE 25…100).
func euclideousFillFieldIndex(_ f: EuclideousFillField, _ line: EuclidLine) -> Int {
    switch f {
    case .speed: return line.fillSpeedResolved                    // stored 0…4 = ×½…×4 (already leading→trailing)
    case .length: return 2 - line.fillLengthResolved              // stored 0=BAR,1=½,2=¼ → leading ¼ = index 0
    case .ranks: return line.fillRanksResolved + 7
    case .swell: return line.fillSwellResolved + 3
    case .roll: return line.fillRollResolved                      // 0…4
    case .chance: return max(0, euclideousFillChanceSteps.firstIndex(of: line.fillChanceResolved) ?? 3)
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
    case .roll: line.fillRoll = UInt8(i)
    case .chance: line.fillChance = UInt8(euclideousFillChanceSteps[i])
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
    case .roll: return i == 0 ? "OFF" : "\(i)"                                                               // §2.5 0 = no roll
    case .chance: return "\(euclideousFillChanceSteps[i])%"                                                  // §2.7 25/50/75/100 %
    }
}

// MARK: - §4.4 the curve / shape CHIPS (a top-trailing mini chip on SPEED / RANKS) + §4.5 the ORDER / HITS SELECTORS

/// §4.4 SPEED's curve chip: STEADY (blank) vs RUSH. The chip's short text; a tap cycles it.
func euclideousFillCurveChipText(_ line: EuclidLine) -> String { line.fillCurveResolved == .rush ? "RUSH" : "STDY" }
func euclideousFillCurveIsRush(_ line: EuclidLine) -> Bool { line.fillCurveResolved == .rush }
func euclideousFillCycleCurve(_ line: inout EuclidLine) { line.fillCurve = (line.fillCurveResolved == .rush) ? .steady : .rush }

/// §4.4 RANKS's shape chip: CLIMB / ARCH / SHIFT. The chip's short text; a tap cycles it.
func euclideousFillShapeChipText(_ line: EuclidLine) -> String { switch line.fillShapeResolved { case .climb: return "CLB"; case .arch: return "ARC"; case .shift: return "SHF" } }
func euclideousFillCycleShape(_ line: inout EuclidLine) {
    switch line.fillShapeResolved { case .climb: line.fillShape = .arch; case .arch: line.fillShape = .shift; case .shift: line.fillShape = .climb }
}

/// §4.5 the two SELECTOR tiles (tap cycles, double-tap resets to the default).
enum EuclideousFillSelector: CaseIterable {
    case order, hits
    var label: String { self == .order ? "ORDER" : "HITS" }
}
/// The selector's current value as a short label (§4.5: FWD / REV / BOUNCE / SHUF · KEEP / ALL / FLIP).
func euclideousFillSelectorText(_ s: EuclideousFillSelector, _ line: EuclidLine) -> String {
    switch s {
    case .order: switch line.fillOrderResolved { case .fwd: return "FWD"; case .rev: return "REV"; case .bounce: return "BOUNCE"; case .shuffle: return "SHUF" }
    case .hits:  switch line.fillHitsResolved  { case .keep: return "KEEP"; case .all: return "ALL"; case .flip: return "FLIP" }
    }
}
func euclideousFillCycleSelector(_ s: EuclideousFillSelector, _ line: inout EuclidLine) {
    switch s {
    case .order: switch line.fillOrderResolved { case .fwd: line.fillOrder = .rev; case .rev: line.fillOrder = .bounce; case .bounce: line.fillOrder = .shuffle; case .shuffle: line.fillOrder = .fwd }; line.fillReverse = nil   // ORDER supersedes the retired REVERSE flag
    case .hits:  switch line.fillHitsResolved  { case .keep: line.fillHits = .all; case .all: line.fillHits = .flip; case .flip: line.fillHits = .keep }
    }
}
func euclideousFillResetSelector(_ s: EuclideousFillSelector, _ line: inout EuclidLine) {
    switch s { case .order: line.fillOrder = .fwd; line.fillReverse = nil; case .hits: line.fillHits = .keep }
}
func euclideousFillSelectorAX(_ s: EuclideousFillSelector, _ line: EuclidLine) -> String {
    let v: String
    switch s {
    case .order: switch line.fillOrderResolved { case .fwd: v = "forward"; case .rev: v = "reverse"; case .bounce: v = "bounce"; case .shuffle: v = "shuffle" }
    case .hits:  switch line.fillHitsResolved  { case .keep: v = "keep"; case .all: v = "all"; case .flip: v = "flip" }
    }
    return "Fill \(s.label.lowercased()), \(v)"
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
    case .roll: v = i == 0 ? "off" : euclideousFillNumberWords[min(euclideousFillNumberWords.count - 1, i)]
    case .chance: v = "\(euclideousFillChanceSteps[i]) percent"
    }
    return "Fill \(f.label.lowercased()), \(v)"
}
private let euclideousFillNumberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
private func euclideousFillSpokenSigned(_ n: Int) -> String {   // §8.3 spells the number ("plus three", "minus two")
    let word = euclideousFillNumberWords[min(euclideousFillNumberWords.count - 1, abs(n))]
    return n == 0 ? "zero" : (n > 0 ? "plus \(word)" : "minus \(word)")
}
