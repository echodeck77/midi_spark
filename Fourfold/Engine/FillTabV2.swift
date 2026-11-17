//  FillTabV2.swift — FILL TAB V2 (2026-11-17) §3/§4/§5/§8: the paged tab's PURE layer. The roll row (FILL · one cell per
//  bar · LOOP), four control rows of one-tap segments / steppers / toggles, every frame, text, look-state and VoiceOver
//  string. Foundation + CoreGraphics only (test target). The views in FillTabV2Views.swift / EuclideousPage paint these
//  and nothing else. Reference: a 360 × 231 content area (the landscape lane card); GEOMETRY IS DEVICE-OWED.

import CoreGraphics

// MARK: - §3.1/§4.1 the frames

enum EuclideousFillV2Metrics {
    static let rollH: CGFloat = 69.5, rollMinH: CGFloat = 52      // §3.1 / §4.1 shrink floor
    static let fillW: CGFloat = 52, loopW: CGFloat = 43, rollGap: CGFloat = 3
    static let cellGap: CGFloat = 2, cellRadius: CGFloat = 4
    static let rowH: CGFloat = 36, rowMinH: CGFloat = 30          // §4.1
    static let rowGap: CGFloat = 4.5, colGap: CGFloat = 4.5, belowRoll: CGFloat = 4
    static let segRowInset: CGFloat = 4, segRowH: CGFloat = 19, segGap: CGFloat = 2, segRadius: CGFloat = 3   // §4.3
    static let stepBtnW: CGFloat = 20, ranksStepBtnW: CGFloat = 22, shapeSegW: CGFloat = 28, ranksShapeGap: CGFloat = 3   // §4.4
    static let breakLandGap: CGFloat = 2.5                        // §4.1 row 4 col 4
}

struct EuclideousFillTabV2Layout: Equatable {
    var fillTile = CGRect.zero        // §3.8 (PLAY RIFF's lamp + "FILL")
    var cellsStrip = CGRect.zero
    var cells: [CGRect] = []          // §3.2 one per bar of the loop
    var loopTile = CGRect.zero        // §3.9
    var speed = CGRect.zero, length = CGRect.zero, rush = CGRect.zero                  // row 1
    var order = CGRect.zero, hits = CGRect.zero                                        // row 2
    var notes = CGRect.zero, ranks = CGRect.zero                                       // row 3
    var swell = CGRect.zero, roll = CGRect.zero, chance = CGRect.zero                  // row 4
    var brk = CGRect.zero, land = CGRect.zero                                          //   (col 4, split)
    var rollH: CGFloat = 0, rowH: CGFloat = 0, colW: CGFloat = 0, twoColW: CGFloat = 0
    var shrunkRows = false, shrunkRoll = false   // §4.1: report every layout that shrank
}

/// §3.1/§4.1 — the whole tab from the content area's size. If the area is shorter than the 231 reference, the control
/// rows shrink first (to 30), then the roll row (to 52); everything is drawn at the formula's values either way.
func euclideousFillTabV2Layout(box: CGSize, loop: Int) -> EuclideousFillTabV2Layout {
    typealias M = EuclideousFillV2Metrics
    var L = EuclideousFillTabV2Layout()
    let fixed = M.belowRoll + 3 * M.rowGap
    var rowH = M.rowH, rollH = M.rollH
    let need = M.rollH + fixed + 4 * M.rowH
    if box.height < need {
        rowH = max(M.rowMinH, (box.height - M.rollH - fixed) / 4)
        L.shrunkRows = true
        if rowH <= M.rowMinH + 1e-9 {
            rowH = M.rowMinH
            rollH = max(M.rollMinH, box.height - fixed - 4 * M.rowMinH)
            L.shrunkRoll = rollH < M.rollH - 1e-9
        }
    }
    L.rollH = rollH; L.rowH = rowH
    // §3.1 the roll row
    L.fillTile = CGRect(x: 0, y: 0, width: M.fillW, height: rollH)
    L.loopTile = CGRect(x: box.width - M.loopW, y: 0, width: M.loopW, height: rollH)
    let stripX = M.fillW + M.rollGap
    let stripW = max(1, box.width - M.fillW - M.loopW - 2 * M.rollGap)
    L.cellsStrip = CGRect(x: stripX, y: 0, width: stripW, height: rollH)
    let n = max(1, loop)
    let cellW = max(1, (stripW - M.cellGap * CGFloat(n - 1)) / CGFloat(n))
    L.cells = (0..<n).map { CGRect(x: stripX + CGFloat($0) * (cellW + M.cellGap), y: 0, width: cellW, height: rollH) }
    // §4.1 the four control rows
    let colW = max(1, (box.width - 3 * M.colGap) / 4)
    let twoColW = colW * 2 + M.colGap
    L.colW = colW; L.twoColW = twoColW
    func rowY(_ i: Int) -> CGFloat { rollH + M.belowRoll + CGFloat(i) * (rowH + M.rowGap) }
    func cell(_ c: Int, _ r: Int, span2: Bool = false) -> CGRect { CGRect(x: CGFloat(c) * (colW + M.colGap), y: rowY(r), width: span2 ? twoColW : colW, height: rowH) }
    L.speed = cell(0, 0, span2: true); L.length = cell(2, 0); L.rush = cell(3, 0)
    L.order = cell(0, 1, span2: true); L.hits = cell(2, 1, span2: true)
    L.notes = cell(0, 2, span2: true); L.ranks = cell(2, 2, span2: true)
    L.swell = cell(0, 3); L.roll = cell(1, 3); L.chance = cell(2, 3)
    let halfW = (colW - M.breakLandGap) / 2
    let c4 = cell(3, 3)
    L.brk = CGRect(x: c4.minX, y: c4.minY, width: halfW, height: rowH)
    L.land = CGRect(x: c4.minX + halfW + M.breakLandGap, y: c4.minY, width: halfW, height: rowH)
    return L
}

// MARK: - §3.4 the cell's internals (in CELL-LOCAL coordinates)

/// The number chip: inset 2 at each side, 12 tall, 3 above the cell's bottom, radius 3.
func euclideousFillV2CellChip(cellSize: CGSize) -> CGRect { CGRect(x: 2, y: cellSize.height - 3 - 12, width: max(0, cellSize.width - 4), height: 12) }
/// The notes area: from 3.5 below the top to 2 above the number chip.
func euclideousFillV2CellNotesArea(cellSize: CGSize) -> CGRect {
    let chip = euclideousFillV2CellChip(cellSize: cellSize)
    return CGRect(x: 0, y: 3.5, width: cellSize.width, height: max(0, chip.minY - 2 - 3.5))
}
/// The progress line (current bar): 1.5 tall, 0.5 above the bottom, from 3 in, width (cellW − 6) × the bar's elapsed fraction.
func euclideousFillV2CellProgress(cellSize: CGSize, fraction: Double) -> CGRect {
    CGRect(x: 3, y: cellSize.height - 0.5 - 1.5, width: max(0, (cellSize.width - 6) * CGFloat(max(0, min(1, fraction)))), height: 1.5)
}

// MARK: - §4.3/§4.4 the controls' inner frames

/// §4.3 — the inset control row: 4 from the leading, trailing and bottom edges, 19 tall.
func euclideousFillV2SegRow(tileSize: CGSize) -> CGRect {
    typealias M = EuclideousFillV2Metrics
    return CGRect(x: M.segRowInset, y: tileSize.height - M.segRowInset - M.segRowH, width: max(1, tileSize.width - 2 * M.segRowInset), height: M.segRowH)
}
/// §4.3 — `count` segments sharing the row's width, 2 apart (row-local x offsets inside the seg row).
func euclideousFillV2SegFrames(row: CGRect, count: Int) -> [CGRect] {
    typealias M = EuclideousFillV2Metrics
    let n = max(1, count)
    let w = max(1, (row.width - M.segGap * CGFloat(n - 1)) / CGFloat(n))
    return (0..<n).map { CGRect(x: row.minX + CGFloat($0) * (w + M.segGap), y: row.minY, width: w, height: row.height) }
}
/// §4.4 — a stepper's − / value / + inside the row (RANKS passes 22-wide buttons, the rest 20).
func euclideousFillV2StepperFrames(row: CGRect, buttonW: CGFloat = EuclideousFillV2Metrics.stepBtnW) -> (minus: CGRect, value: CGRect, plus: CGRect) {
    typealias M = EuclideousFillV2Metrics
    let minus = CGRect(x: row.minX, y: row.minY, width: buttonW, height: row.height)
    let plus = CGRect(x: row.maxX - buttonW, y: row.minY, width: buttonW, height: row.height)
    let value = CGRect(x: minus.maxX + M.segGap, y: row.minY, width: max(1, plus.minX - minus.maxX - 2 * M.segGap), height: row.height)
    return (minus, value, plus)
}
/// §4.3/§4.4 — RANKS's row: two 28-wide shape segments (2 apart), sp3, then the stepper in the rest (22-wide buttons).
func euclideousFillV2RanksFrames(row: CGRect) -> (climb: CGRect, arch: CGRect, minus: CGRect, value: CGRect, plus: CGRect) {
    typealias M = EuclideousFillV2Metrics
    let climb = CGRect(x: row.minX, y: row.minY, width: M.shapeSegW, height: row.height)
    let arch = CGRect(x: climb.maxX + M.segGap, y: row.minY, width: M.shapeSegW, height: row.height)
    let rest = CGRect(x: arch.maxX + M.ranksShapeGap, y: row.minY, width: max(1, row.maxX - arch.maxX - M.ranksShapeGap), height: row.height)
    let s = euclideousFillV2StepperFrames(row: rest, buttonW: M.ranksStepBtnW)
    return (climb, arch, s.minus, s.value, s.plus)
}

// MARK: - the controls' identity, values, texts and neutrality (§4.3/§4.4/§5)

/// The six segmented controls. SPEED/LENGTH/HITS/NOTES label segments; ORDER draws glyphs; RANKS's shapes are their own pair.
enum EuclideousFillV2Seg: CaseIterable {
    case speed, length, order, hits, notes
    var label: String { switch self { case .speed: return "SPEED"; case .length: return "LENGTH"; case .order: return "ORDER"; case .hits: return "HITS"; case .notes: return "NOTES" } }
    var count: Int { switch self { case .speed: return 5; case .length: return 3; case .order: return 5; case .hits: return 4; case .notes: return 5 } }
    /// §4.3 the segment labels (ORDER's are glyphs — these are its VoiceOver names).
    var segTexts: [String] {
        switch self {
        case .speed: return ["\u{00D7}\u{00BD}", "\u{00D7}1", "\u{00D7}1\u{00BD}", "\u{00D7}2", "\u{00D7}4"]
        case .length: return ["\u{00BC}", "\u{00BD}", "BAR"]
        case .order: return ["FWD", "REV", "BOUNCE", "SHUFFLE", "STUTTER"]
        case .hits: return ["KEEP", "ALL", "FLIP", "BUILD"]
        case .notes: return ["RIFF", "FLAT", "PEDAL", "OCT", "CHORD"]
        }
    }
    var textSize: CGFloat { self == .notes ? 6.5 : 7.5 }   // §4.3: NOTES 6.5 pt, the rest 7.5
    /// §8.2 spoken segment names.
    var spoken: [String] {
        switch self {
        case .speed: return ["times one half", "times one", "times one and a half", "times two", "times four"]
        case .length: return ["quarter", "half", "bar"]
        case .order: return ["forward", "reverse", "bounce", "shuffle", "stutter"]
        case .hits: return ["keep", "all", "flip", "build"]
        case .notes: return ["riff", "flat", "pedal", "octave", "chord"]
        }
    }
    var spokenGroup: String { switch self { case .speed: return "Speed"; case .length: return "Length"; case .order: return "Order"; case .hits: return "Hits"; case .notes: return "Notes" } }
}

/// The selected index of a segmented control (leading → trailing, §4.3's orders).
func euclideousFillV2SegIndex(_ s: EuclideousFillV2Seg, _ line: EuclidLine) -> Int {
    switch s {
    case .speed: return line.fillSpeedResolved
    case .length: return 2 - line.fillLengthResolved                                  // stored 0=BAR,1=½,2=¼ → leading ¼
    case .order: switch line.fillOrderResolved { case .fwd: return 0; case .rev: return 1; case .bounce: return 2; case .shuffle: return 3; case .stutter: return 4 }
    case .hits: switch line.fillHitsResolved { case .keep: return 0; case .all: return 1; case .flip: return 2; case .build: return 3 }
    case .notes: switch line.fillNotesResolved { case .riff: return 0; case .flat: return 1; case .pedal: return 2; case .oct: return 3; case .chord: return 4 }
    }
}
/// Write a tapped segment back (the ONE setter; a tap on the selected segment is a no-op — the caller checks).
func euclideousFillV2SegSet(_ s: EuclideousFillV2Seg, _ idx: Int, _ line: inout EuclidLine) {
    let i = max(0, min(s.count - 1, idx))
    switch s {
    case .speed: line.fillSpeed = UInt8(i)
    case .length: line.fillLength = UInt8(2 - i)
    case .order: line.fillOrder = [EuclideousFillOrder.fwd, .rev, .bounce, .shuffle, .stutter][i]; line.fillReverse = nil
    case .hits: line.fillHits = [EuclideousFillHits.keep, .all, .flip, .build][i]
    case .notes: line.fillNotes = [EuclideousFillNotes.riff, .flat, .pedal, .oct, .chord][i]
    }
}
/// §5.1 — is the SELECTED segment a NEUTRAL value (grey #4A4D57, no lane colour)? LENGTH always is (it says where, not how).
func euclideousFillV2SegIsNeutral(_ s: EuclideousFillV2Seg, index: Int) -> Bool {
    switch s {
    case .speed: return index == 1          // ×1
    case .length: return true
    case .order: return index == 0          // FWD
    case .hits: return index == 0           // KEEP
    case .notes: return index == 0          // RIFF
    }
}

/// The four steppers. Ranges and labels per §4.4; the default is the double-tap reset's target.
enum EuclideousFillV2Step: CaseIterable {
    case ranks, swell, roll, chance
    var label: String { switch self { case .ranks: return "RANKS"; case .swell: return "SWELL"; case .roll: return "ROLL"; case .chance: return "CHANCE" } }
    var range: ClosedRange<Int> { switch self { case .ranks: return -7...7; case .swell: return -3...3; case .roll: return 0...4; case .chance: return 0...3 } }
    var defaultValue: Int { switch self { case .ranks, .swell, .roll: return 0; case .chance: return 3 } }
    var spokenName: String { switch self { case .ranks: return "Fill ranks"; case .swell: return "Fill swell"; case .roll: return "Fill roll"; case .chance: return "Fill chance" } }
}
private let euclideousFillV2ChanceSteps = [25, 50, 75, 100]

func euclideousFillV2StepValue(_ f: EuclideousFillV2Step, _ line: EuclidLine) -> Int {
    switch f {
    case .ranks: return line.fillRanksResolved
    case .swell: return line.fillSwellResolved
    case .roll: return line.fillRollResolved
    case .chance: return euclideousFillV2ChanceSteps.firstIndex(of: line.fillChanceResolved) ?? 3
    }
}
func euclideousFillV2StepSet(_ f: EuclideousFillV2Step, _ v: Int, _ line: inout EuclidLine) {
    let c = max(f.range.lowerBound, min(f.range.upperBound, v))
    switch f {
    case .ranks: line.fillRanks = Int8(c)
    case .swell: line.fillSwell = Int8(c)
    case .roll: line.fillRoll = UInt8(c)
    case .chance: line.fillChance = UInt8(euclideousFillV2ChanceSteps[c])
    }
}
/// §4.4 the value text ("−3"…"+3", "OFF"/"1"…"4", "25%"…"100%"; U+2212 minus).
func euclideousFillV2StepText(_ f: EuclideousFillV2Step, _ line: EuclidLine) -> String {
    let v = euclideousFillV2StepValue(f, line)
    switch f {
    case .ranks, .swell: return v == 0 ? "0" : (v > 0 ? "+\(v)" : "\u{2212}\(abs(v))")
    case .roll: return v == 0 ? "OFF" : "\(v)"
    case .chance: return "\(euclideousFillV2ChanceSteps[v])%"
    }
}
/// §5.2 — the value box at its NEUTRAL value draws plain (#22242A / #C9CDD5); otherwise lane colour.
func euclideousFillV2StepIsNeutral(_ f: EuclideousFillV2Step, _ line: EuclidLine) -> Bool { euclideousFillV2StepValue(f, line) == f.defaultValue }

/// §5.1 — RANKS's shape segments draw the NEUTRAL selected look while RANKS is 0.
func euclideousFillV2ShapeIsNeutral(_ line: EuclidLine) -> Bool { line.fillRanksResolved == 0 }

// MARK: - §4.3 the ORDER / RANKS glyph paths (a 24-unit box; FWD/REV/BOUNCE reuse EUCLID's own direction icons in the view)

/// SHUFFLE / STUTTER / CLIMB / ARCH as 24-box path commands: (move-to, line-to…) tuples a Shape scales. FWD and REV also
/// provided for completeness (the view prefers `RiffDirectionIcon` where it exists, per the spec's reuse clause).
enum EuclideousFillV2Glyph {
    case fwd, rev, shuffle, stutter, climb, arch
    /// Each subpath as its points (in the 24-unit box); straight-line polylines only.
    var subpaths: [[CGPoint]] {
        switch self {
        case .fwd: return [[CGPoint(x: 5, y: 12), CGPoint(x: 19, y: 12)], [CGPoint(x: 13, y: 6), CGPoint(x: 19, y: 12), CGPoint(x: 13, y: 18)]]
        case .rev: return [[CGPoint(x: 19, y: 12), CGPoint(x: 5, y: 12)], [CGPoint(x: 11, y: 6), CGPoint(x: 5, y: 12), CGPoint(x: 11, y: 18)]]
        case .shuffle: return [[CGPoint(x: 4, y: 7), CGPoint(x: 8, y: 7), CGPoint(x: 16, y: 17), CGPoint(x: 20, y: 17)],
                               [CGPoint(x: 17, y: 14), CGPoint(x: 20, y: 17), CGPoint(x: 17, y: 20)],
                               [CGPoint(x: 4, y: 17), CGPoint(x: 8, y: 17), CGPoint(x: 10.5, y: 14)],
                               [CGPoint(x: 13.5, y: 10), CGPoint(x: 16, y: 7), CGPoint(x: 20, y: 7)],
                               [CGPoint(x: 17, y: 4), CGPoint(x: 20, y: 7), CGPoint(x: 17, y: 10)]]
        case .stutter: return [[CGPoint(x: 6, y: 6), CGPoint(x: 6, y: 18)], [CGPoint(x: 12, y: 6), CGPoint(x: 12, y: 18)], [CGPoint(x: 18, y: 6), CGPoint(x: 18, y: 18)]]
        case .climb: return [[CGPoint(x: 4, y: 18), CGPoint(x: 20, y: 6)], [CGPoint(x: 13, y: 6), CGPoint(x: 20, y: 6), CGPoint(x: 20, y: 13)]]
        case .arch: return [[CGPoint(x: 3, y: 18), CGPoint(x: 12, y: 6), CGPoint(x: 21, y: 18)]]
        }
    }
}

// MARK: - §8 VoiceOver

func euclideousFillV2CellAX(bar: Int, on: Bool, current: Bool, plays: Bool?) -> String {
    var s = "Fill bar \(bar + 1), \(on ? "on" : "off")" + (current ? ", current" : "")
    if on, let p = plays { s += p ? ", fill plays" : ", skipped" }   // §8.1 the hint-free value when the bar is lit
    return s
}
func euclideousFillV2SegAX(_ s: EuclideousFillV2Seg, index: Int) -> String { "\(s.spokenGroup), \(s.spoken[max(0, min(s.spoken.count - 1, index))])" }
func euclideousFillV2StepAX(_ f: EuclideousFillV2Step, _ line: EuclidLine) -> String {
    let v = euclideousFillV2StepValue(f, line)
    switch f {
    case .ranks, .swell:
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven"]
        let w = words[min(words.count - 1, abs(v))]
        return "\(f.spokenName), \(v == 0 ? "zero" : (v > 0 ? "plus \(w)" : "minus \(w)"))"
    case .roll: return "\(f.spokenName), \(v == 0 ? "off" : "\(v)")"
    case .chance: return "\(f.spokenName), \(euclideousFillV2ChanceSteps[v]) percent"
    }
}
func euclideousFillV2ToggleAX(_ which: String, on: Bool) -> String { "Fill \(which), \(on ? "on" : "off")" }   // rush / break / land
func euclideousFillV2LoopAX(_ loop: Int) -> String { "Fill loop, \(loop) bars" }
func euclideousFillV2ShapeAX(climb: Bool) -> String { "Fill shape, \(climb ? "climb" : "arch")" }
