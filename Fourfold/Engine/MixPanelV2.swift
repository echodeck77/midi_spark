//  MixPanelV2.swift — MIX v2 ferry (2026-11-05) + its amendment 1 (revised): the MIX panel's frames, looks and strings as PURE functions (Foundation + CoreGraphics only). It replaces the MIX rows build's band layout
//  (`MixPanel.swift`'s `euclideousMixRowsLayout`, which stays compiled, hidden). Everything a view draws or touches comes from here, so the views, the page floors and the tests read the same numbers.
//
//  Coordinates: a BAND's own sub-frames are in its INNER coordinates (the band's 6 pt inset's top-left); `EuclideousMixV2BandFrames.frame` / `inner` are in the PANEL's coordinates; the emitters and the lines' start points
//  are in panel coordinates too. The panel is W × H: the emitter column takes the rightmost 76, four bands (lane 1 to 4, 6 apart) the rest.

import Foundation
import CoreGraphics

enum EuclideousMixV2Metrics {
    // §1.1–1.3
    static let emitterColumnW: CGFloat = 76, bandGap: CGFloat = 6, bandInset: CGFloat = 6
    static let topLineH: CGFloat = 30
    static let poolW: CGFloat = 56, forkEndX: CGFloat = 70, blockX: CGFloat = 70
    static let poolTop: CGFloat = 36, riffRowTop: CGFloat = 36, partRowGap: CGFloat = 6
    static let chipGap: CGFloat = 2
    // §1.4 — a part row
    static let plateInset: CGFloat = 3
    static let soloW: CGFloat = 22, toggleW: CGFloat = 48, stackW: CGFloat = 30, transW: CGFloat = 54, octW: CGFloat = 110, outW: CGFloat = 26, outsW: CGFloat = 104
    static let gapSoloToggle: CGFloat = 4, gapToggleStack: CGFloat = 6, gapStackVel: CGFloat = 6, gapSlider: CGFloat = 4, gapGateTrans: CGFloat = 4, gapTransOct: CGFloat = 4, gapOctOuts: CGFloat = 6
    /// Everything in a part row but the two sliders, plate insets included: 6 + 22 + 4 + 48 + 6 + 30 + 6 + 4 + 4 + 54 + 4 + 110 + 6 + 104 — V = (blockW − 6 − 402) ÷ 2.
    static let rowFixed: CGFloat = 402
    // amendment B1 — the top line
    static let stripFrameRightInset: CGFloat = 113, hitsBoxesRightInset: CGFloat = 107, boxW: CGFloat = 50, boxGap: CGFloat = 4, stripInset: CGFloat = 2.5
    static let playTarget = CGSize(width: 56, height: 36)
    static let badge: CGFloat = 25
    // §6 — emitters
    static let emitterD: CGFloat = 36, emitterX: CGFloat = 40
    static let lineBend1: CGFloat = 23, lineBend2: CGFloat = 18.5
    // §3.3 — the fork's control-point x's
    static let forkC1: CGFloat = 63.8, forkC2: CGFloat = 62.2
    // §1.6 floors
    static let floorV: CGFloat = 72, floorRowH: CGFloat = 44, floorBandH: CGFloat = 140
    // §4.7 TRANS
    static let transLeftW: CGFloat = 34
    // §4.8 OCT
    static let octLabelH: CGFloat = 9, octBottomGap: CGFloat = 2
}

enum EuclideousMixV2Floor: Equatable, Hashable { case slider, row, band }

/// One part row (riff or notes), in the band's inner coordinates.
struct EuclideousMixV2RowFrames: Equatable {
    var plate: CGRect
    /// The tiles' height: the row less its 3 pt plate inset top and bottom.
    var tileH: CGFloat
    var solo: CGRect, soloTarget: CGRect
    var toggle: CGRect
    var stack: CGRect
    var vel: CGRect, gate: CGRect
    var trans: CGRect, transLeft: CGRect, transRight: CGRect, transUpper: CGRect, transLower: CGRect
    var oct: CGRect, octLabel: CGRect
    var octBoxes: [CGRect]
    var octTargets: [CGRect]
    var outs: CGRect
    var outTargets: [CGRect], outCircles: [CGRect]
    var centreY: CGFloat { plate.midY }
}
struct EuclideousMixV2BandFrames: Equatable {
    /// The band and its 6 pt inset, in PANEL coordinates.
    var frame: CGRect, inner: CGRect
    /// Top line (y 0–30): play over the pool's column, the strip frame, HITS and STEPS over the A–D column.
    var play: CGRect, playTarget: CGRect
    var stripFrame: CGRect, stripSteps: CGRect, stripStepsWithBadge: CGRect, badge: CGRect
    var hitsBox: CGRect, stepsBox: CGRect
    /// The pool: the column x 0–56 from y 36 to the inner bottom, its eight chips (index 0 = rank 8, the top) and the fork's three points.
    var pool: CGRect
    var chips: [CGRect]
    var forkStart: CGPoint, forkRiffEnd: CGPoint, forkNotesEnd: CGPoint
    var riff: EuclideousMixV2RowFrames, notes: EuclideousMixV2RowFrames
    func row(notes isNotes: Bool) -> EuclideousMixV2RowFrames { isNotes ? notes : riff }
}
struct EuclideousMixV2Layout: Equatable {
    var size: CGSize
    var bandW: CGFloat, bandH: CGFloat, innerW: CGFloat, innerH: CGFloat, blockW: CGFloat, rowH: CGFloat, tileH: CGFloat, sliderW: CGFloat, chipH: CGFloat
    var bands: [EuclideousMixV2BandFrames]
    var emitterColumn: CGRect
    /// The four emitter circles, panel coordinates.
    var emitters: [CGRect]
    var floors: [EuclideousMixV2Floor]
}

/// §1 + amendment B1/B2: the whole panel from its size. Pure; every number a view uses.
func euclideousMixV2Layout(size: CGSize) -> EuclideousMixV2Layout {
    typealias M = EuclideousMixV2Metrics
    let bandW = size.width - M.emitterColumnW
    let bandH = (size.height - 3 * M.bandGap) / 4
    let innerW = bandW - 2 * M.bandInset, innerH = bandH - 2 * M.bandInset
    let blockW = innerW - M.blockX
    let rowH = (innerH - 42) / 2
    let tileH = rowH - 2 * M.plateInset
    let v = (blockW - 2 * M.plateInset - M.rowFixed) / 2
    let chipH = (innerH - M.poolTop - 14) / 8

    func row(top: CGFloat) -> EuclideousMixV2RowFrames {
        let plate = CGRect(x: M.blockX, y: top, width: blockW, height: rowH)
        let y = top + M.plateInset
        var x = plate.minX + M.plateInset
        let solo = CGRect(x: x, y: y, width: M.soloW, height: tileH)
        // S's target: its width with the plate inset on each side, by the row's full height
        let soloTarget = CGRect(x: plate.minX, y: top, width: M.plateInset + M.soloW + 1, height: rowH)
        x += M.soloW + M.gapSoloToggle
        let toggle = CGRect(x: x, y: y, width: M.toggleW, height: tileH); x += M.toggleW + M.gapToggleStack
        let stack = CGRect(x: x, y: y, width: M.stackW, height: tileH); x += M.stackW + M.gapStackVel
        let vel = CGRect(x: x, y: y, width: v, height: tileH); x += v + M.gapSlider
        let gate = CGRect(x: x, y: y, width: v, height: tileH); x += v + M.gapGateTrans
        let trans = CGRect(x: x, y: y, width: M.transW, height: tileH); x += M.transW + M.gapTransOct
        let transLeft = CGRect(x: trans.minX, y: y, width: M.transLeftW, height: tileH)
        let transRight = CGRect(x: trans.minX + M.transLeftW, y: y, width: M.transW - M.transLeftW, height: tileH)
        // §4.7 targets: the row's upper half across the whole tile steps up, its lower half steps down (54 × rowH ÷ 2 each)
        let transUpper = CGRect(x: trans.minX, y: top, width: M.transW, height: rowH / 2)
        let transLower = CGRect(x: trans.minX, y: top + rowH / 2, width: M.transW, height: rowH / 2)
        let oct = CGRect(x: x, y: y, width: M.octW, height: tileH); x += M.octW + M.gapOctOuts
        let octLabel = CGRect(x: oct.minX, y: y, width: M.octW, height: M.octLabelH)
        let boxH = max(0, tileH - M.octLabelH - M.octBottomGap)
        let boxW = M.octW / 5
        let boxes = (0..<5).map { CGRect(x: oct.minX + CGFloat($0) * boxW, y: y + M.octLabelH, width: boxW, height: boxH) }
        // §5.4: each box's width by the row height, never less than 44 tall
        let tH = max(44, rowH), tTop = top - (tH - rowH) / 2
        let octTargets = (0..<5).map { CGRect(x: oct.minX + CGFloat($0) * boxW, y: tTop, width: boxW, height: tH) }
        let outs = CGRect(x: x, y: y, width: M.outsW, height: tileH)
        let outTargets = (0..<4).map { CGRect(x: outs.minX + CGFloat($0) * M.outW, y: top, width: M.outW, height: rowH) }
        let outCircles = (0..<4).map { CGRect(x: outs.minX + CGFloat($0) * M.outW + (M.outW - 22) / 2, y: y + (tileH - 22) / 2, width: 22, height: 22) }
        return EuclideousMixV2RowFrames(plate: plate, tileH: tileH, solo: solo, soloTarget: soloTarget, toggle: toggle, stack: stack, vel: vel, gate: gate,
                                        trans: trans, transLeft: transLeft, transRight: transRight, transUpper: transUpper, transLower: transLower,
                                        oct: oct, octLabel: octLabel, octBoxes: boxes, octTargets: octTargets, outs: outs, outTargets: outTargets, outCircles: outCircles)
    }

    var bands: [EuclideousMixV2BandFrames] = []
    for n in 0..<4 {
        let top = CGFloat(n) * (bandH + M.bandGap)
        let frame = CGRect(x: 0, y: top, width: bandW, height: bandH)
        let inner = CGRect(x: M.bandInset, y: top + M.bandInset, width: innerW, height: innerH)
        // the top line: three things with one top and one height
        let play = CGRect(x: 0, y: 0, width: M.poolW, height: M.topLineH)
        let playTarget = CGRect(x: 0, y: 0, width: M.playTarget.width, height: M.playTarget.height)
        let stripFrame = CGRect(x: M.blockX, y: 0, width: max(0, blockW - M.stripFrameRightInset), height: M.topLineH)   // clamped at 0 wide below the floors (nothing shrinks, nothing goes negative)
        let steps = CGRect(x: stripFrame.minX + M.stripInset, y: M.stripInset, width: max(0, stripFrame.width - 2 * M.stripInset), height: M.topLineH - 2 * M.stripInset)
        let badge = CGRect(x: stripFrame.maxX - M.stripInset - M.badge, y: M.stripInset, width: M.badge, height: M.badge)
        let stepsWithBadge = CGRect(x: steps.minX, y: steps.minY, width: max(0, badge.minX - 4 - steps.minX), height: steps.height)   // the steps end sp4 before the badge
        let hitsX = M.blockX + blockW - M.hitsBoxesRightInset
        let hits = CGRect(x: hitsX, y: 0, width: M.boxW, height: M.topLineH)
        let stepsBox = CGRect(x: hitsX + M.boxW + M.boxGap, y: 0, width: M.boxW, height: M.topLineH)
        // the pool and its fork
        let pool = CGRect(x: 0, y: M.poolTop, width: M.poolW, height: innerH - M.poolTop)
        let chips = (0..<8).map { CGRect(x: 0, y: M.poolTop + CGFloat($0) * (chipH + M.chipGap), width: M.poolW, height: chipH) }
        let riff = row(top: M.riffRowTop)
        let notes = row(top: 42 + rowH)
        let forkStart = CGPoint(x: M.poolW, y: (M.poolTop + innerH) / 2)
        bands.append(EuclideousMixV2BandFrames(frame: frame, inner: inner, play: play, playTarget: playTarget, stripFrame: stripFrame, stripSteps: steps, stripStepsWithBadge: stepsWithBadge, badge: badge,
                                               hitsBox: hits, stepsBox: stepsBox, pool: pool, chips: chips, forkStart: forkStart,
                                               forkRiffEnd: CGPoint(x: M.forkEndX, y: riff.centreY), forkNotesEnd: CGPoint(x: M.forkEndX, y: notes.centreY), riff: riff, notes: notes))
    }
    let column = CGRect(x: bandW, y: 0, width: M.emitterColumnW, height: size.height)
    let emitters = (0..<4).map { n -> CGRect in
        let top = CGFloat(n) * (bandH + M.bandGap)
        let cy = top + M.bandInset + 36 + rowH + 3   // §6.1: band n's top + 6 + 36 + rowH + 3
        return CGRect(x: bandW + M.emitterX, y: cy - M.emitterD / 2, width: M.emitterD, height: M.emitterD)
    }
    var floors: [EuclideousMixV2Floor] = []
    if v < M.floorV { floors.append(.slider) }
    if rowH < M.floorRowH { floors.append(.row) }
    if bandH < M.floorBandH { floors.append(.band) }
    return EuclideousMixV2Layout(size: size, bandW: bandW, bandH: bandH, innerW: innerW, innerH: innerH, blockW: blockW, rowH: rowH, tileH: tileH, sliderW: v, chipH: chipH,
                                 bands: bands, emitterColumn: column, emitters: emitters, floors: floors)
}

/// §3.3: the fork's two cubic curves — from the pool's mid-height to each row's centre, control points (63.8, y0) and (62.2, y1).
struct EuclideousMixV2ForkCurve: Equatable {
    var start: CGPoint, c1: CGPoint, c2: CGPoint, end: CGPoint
}
func euclideousMixV2ForkCurve(from start: CGPoint, to end: CGPoint) -> EuclideousMixV2ForkCurve {
    typealias M = EuclideousMixV2Metrics
    return EuclideousMixV2ForkCurve(start: start, c1: CGPoint(x: M.forkC1, y: start.y), c2: CGPoint(x: M.forkC2, y: end.y), end: end)
}
/// The panel's size in the page: the lane cards' 2×2 bounding box (the lane strip's width by two cards and the gap) — unchanged from the MIX rows build.
func euclideousMixV2PanelSize(stripWidth: CGFloat, laneBox: CGSize) -> CGSize { CGSize(width: stripWidth, height: 2 * laneBox.height + 8) }

// MARK: - §2.3 the strip's cells (v2 fills) and the HITS / STEPS boxes

enum EuclideousMixV2StripMetrics {
    static let radius: CGFloat = 4, gap: CGFloat = 2, bottomLine: CGFloat = 2.5, glow: CGFloat = 8
    static let emptyHex: UInt32 = 0x2A2C33, currentEmptyHex: UInt32 = 0x383B43, hitAlpha = 0.55
    static let frameFillHex: UInt32 = 0x141519, frameBorderAlpha = 0.45, frameRadius: CGFloat = 8
    static let bandFillHex: UInt32 = 0x17181C, bandBorderHex: UInt32 = 0x25272D, bandRadius: CGFloat = 12
    static let boxFillHex: UInt32 = 0x1F2127, boxRadius: CGFloat = 7, numberSize: CGFloat = 12, labelSize: CGFloat = 6, numberGap: CGFloat = 3
}
struct EuclideousMixV2CellLook: Equatable {
    var fill: EuclideousStripColumnFill
    /// A 2.5 pt lane-colour line along the cell's bottom (a hit that is not the current step).
    var bottomLine: Bool
    /// An 8 pt lane-colour glow (the current step on a hit).
    var glow: Bool
}
/// §2.3: empty #2A2C33 · the current step on an empty step #383B43 · a hit lane100 at 55 % + the 2.5 pt bottom line · the current step on a hit solid lane100 with the 8 pt glow. No numbers.
func euclideousMixV2CellLook(isHit: Bool, isCurrent: Bool) -> EuclideousMixV2CellLook {
    typealias S = EuclideousMixV2StripMetrics
    switch (isHit, isCurrent) {
    case (false, false): return EuclideousMixV2CellLook(fill: .solid(hex: S.emptyHex), bottomLine: false, glow: false)
    case (false, true): return EuclideousMixV2CellLook(fill: .solid(hex: S.currentEmptyHex), bottomLine: false, glow: false)
    case (true, false): return EuclideousMixV2CellLook(fill: .lane(alpha: S.hitAlpha), bottomLine: true, glow: false)
    case (true, true): return EuclideousMixV2CellLook(fill: .lane(alpha: 1), bottomLine: false, glow: true)
    }
}
/// B1.4: the two boxes' numbers — the lane's hit count and its step count — and their labels.
func euclideousMixV2HitsStepsTexts(hits: Int, steps: Int) -> (hits: String, steps: String) { (String(max(0, hits)), String(max(0, steps))) }
let euclideousMixV2HitsLabel = "HITS", euclideousMixV2StepsLabel = "STEPS"

// MARK: - §4.2 dims — one 42 %, never stacked

enum EuclideousMixV2Element: Equatable { case pool, fork, solo, toggle, stack, vel, gate, trans, oct, outs }
/// §2.1 / §4.2: a dimmed LANE (muted, solo-silenced, no hits) dims everything below the strip frame to 42 %; otherwise a part that is off or solo-silenced dims only its stack, VEL, GATE, TRANS and OCT. S, the toggle and A–D keep
/// full strength (unless the lane dims). Everything stays live. Never 42 % × 42 %.
func euclideousMixV2Opacity(laneDimmed: Bool, partDimmed: Bool, element: EuclideousMixV2Element) -> Double {
    if laneDimmed { return EuclideousLaneDimStyle.opacity }
    switch element {
    case .stack, .vel, .gate, .trans, .oct: return partDimmed ? EuclideousLaneDimStyle.opacity : 1
    case .pool, .fork, .solo, .toggle, .outs: return 1
    }
}
/// What an element ADDS inside a group that already applies the lane dim (so the product is the net above).
func euclideousMixV2OwnOpacity(laneDimmed: Bool, partDimmed: Bool, element: EuclideousMixV2Element) -> Double {
    laneDimmed ? 1 : euclideousMixV2Opacity(laneDimmed: false, partDimmed: partDimmed, element: element)
}

// MARK: - §3.3 the fork's look

/// lane100 at 70 % while its part is on, 25 % while off.
func euclideousMixV2ForkAlpha(partOn: Bool) -> Double { partOn ? 0.70 : 0.25 }

// MARK: - §4.5 the stack

enum EuclideousMixV2StackCell: Equatable {
    case unlit
    /// lane100 with a 4 pt glow
    case lit
    /// a silent note (routed nowhere): a 1 pt lane100 outline, no fill
    case silent
}
enum EuclideousMixV2StackMetrics {
    static let gap: CGFloat = 1, radius: CGFloat = 1.5, glow: CGFloat = 4, silentLine: CGFloat = 1
    static let unlitOnHex: UInt32 = 0x2A2C33, unlitOffHex: UInt32 = 0x202227
}
/// The eight cells' frames in a stack tile, rank 8 at the top (index 0), 1 apart: cell height (tileH − 7) ÷ 8.
func euclideousMixV2StackFrames(tile: CGRect) -> [CGRect] {
    typealias S = EuclideousMixV2StackMetrics
    let h = (tile.height - 7 * S.gap) / 8
    return (0..<8).map { CGRect(x: tile.minX, y: tile.minY + CGFloat($0) * (h + S.gap), width: tile.width, height: h) }
}
/// §4.5: a rank's cell lights from a note-on of that rank in THIS part until the note's note-off; a silent note lights its cell as an outline only; a rank with both a sounding and a silent note is lit. Index 0 = rank 8 … 7 = rank 1.
func euclideousMixV2StackCells(notes: [NoteRollNote], nowBeat: Double) -> [EuclideousMixV2StackCell] {
    var cells = [EuclideousMixV2StackCell](repeating: .unlit, count: 8)
    for n in notes where n.rank >= 1 && n.rank <= 8 && euclideousMixNoteSounds(n, at: nowBeat) {
        let i = 8 - Int(n.rank)
        if n.outs == 0 { if cells[i] == .unlit { cells[i] = .silent } } else { cells[i] = .lit }
    }
    return cells
}
/// The ranks (1…8, ascending) a part is playing now, silent notes excluded — for VoiceOver.
func euclideousMixV2PlayingRanks(notes: [NoteRollNote], nowBeat: Double) -> [Int] {
    var set = Set<Int>()
    for n in notes where n.rank >= 1 && n.rank <= 8 && n.outs != 0 && euclideousMixNoteSounds(n, at: nowBeat) { set.insert(Int(n.rank)) }
    return set.sorted()
}

// MARK: - §7.5 the S button

struct EuclideousMixV2SoloLook: Equatable {
    var fillHex: UInt32?       // nil = the off fill
    var inkHex: UInt32
    var border: Bool
}
enum EuclideousMixV2SoloMetrics { static let latchedHex: UInt32 = 0xF2C230, heldHex: UInt32 = 0xDFE3EA, offFillHex: UInt32 = 0x1F2127, borderHex: UInt32 = 0x30333A, offInkHex: UInt32 = 0x8A909A, onInkHex: UInt32 = 0x0D0F14, radius: CGFloat = 6, size: CGFloat = 10, border: CGFloat = 1.5 }
/// Off: #1F2127 with a 1.5 pt #30333A border, ink #8A909A. Latched: #F2C230, ink #0D0F14. Held (a finger down past 300 ms): #DFE3EA, ink #0D0F14.
func euclideousMixV2SoloLook(latched: Bool, heldLook: Bool) -> EuclideousMixV2SoloLook {
    typealias S = EuclideousMixV2SoloMetrics
    if heldLook { return EuclideousMixV2SoloLook(fillHex: S.heldHex, inkHex: S.onInkHex, border: false) }
    if latched { return EuclideousMixV2SoloLook(fillHex: S.latchedHex, inkHex: S.onInkHex, border: false) }
    return EuclideousMixV2SoloLook(fillHex: nil, inkHex: S.offInkHex, border: true)
}

// MARK: - §4.7 TRANS

let euclideousMixV2TransRange = -7...7
/// "+2", "0", "−1" (U+2212 for minus).
func euclideousMixV2TransText(_ v: Int) -> String { v == 0 ? "0" : (v > 0 ? "+\(v)" : "\u{2212}\(-v)") }
/// One tap: a step up or down, clamped to −7…+7.
func euclideousMixV2TransStep(_ v: Int, up: Bool) -> Int { max(euclideousMixV2TransRange.lowerBound, min(euclideousMixV2TransRange.upperBound, v + (up ? 1 : -1))) }
/// A hold repeats every 150 ms after 400 ms: how many REPEAT steps have fired after the finger has been down `heldFor` seconds (0 before 0.4 s; 1 at 0.4; 2 at 0.55; …).
func euclideousMixV2TransRepeatSteps(heldFor: Double) -> Int { heldFor < 0.4 - 1e-9 ? 0 : 1 + Int((heldFor - 0.4 + 1e-9) / 0.15) }
/// A tap in the tile's UPPER half (the half-tile target) steps up, the LOWER half down.
func euclideousMixV2TransTapIsUp(y: CGFloat, targetHeight: CGFloat) -> Bool { y < targetHeight / 2 }

// MARK: - §5 OCT: five linked boxes (one function for every surface)

let euclideousOctRange = -2...2
/// "−2", "−1", "0", "+1", "+2" (U+2212).
let euclideousOctLabels = ["\u{2212}2", "\u{2212}1", "0", "+1", "+2"]
/// The ONE selected box: the stored value clamped to −2…+2 (an old document's ±3 from the 8×8 workbench shows its end box), as an index 0…4.
func euclideousOctSelectedIndex(value: Int) -> Int { max(-2, min(2, value)) + 2 }
func euclideousOctValue(index: Int) -> Int { max(0, min(4, index)) - 2 }
/// The box under a finger at `x` in a control `width` wide (a drag across the boxes selects the one under it); clamped to the ends.
func euclideousOctIndex(x: CGFloat, width: CGFloat) -> Int { width <= 0 ? 2 : max(0, min(4, Int((x / width * 5).rounded(.down)))) }
/// VoiceOver's adjustable step.
func euclideousOctStep(_ v: Int, up: Bool) -> Int { max(-2, min(2, v + (up ? 1 : -1))) }
/// Label size: 9 pt where the boxes are 28 or more tall, else 8.
func euclideousOctLabelSize(boxHeight: CGFloat) -> CGFloat { boxHeight >= 28 ? 9 : 8 }
func euclideousOctValueText(_ v: Int) -> String { v == 0 ? "0" : (v > 0 ? "+\(v)" : "\u{2212}\(-v)") }

// MARK: - §6.3 the lines (from each part row's centre to its emitter)

/// A line for each part that is ON, to each emitter its mask holds: from (bandW, the row's centre) to (bandW + 40, the emitter's centre), a cubic with control points (bandW + 23, y0) and (bandW + 18.5, y1) — MIX rows §7 with v2's row centres.
func euclideousMixV2Lines(layout: EuclideousMixV2Layout, masks: [UInt8], partOn: [Bool]) -> [EuclideousMixLineGeometry] {
    typealias M = EuclideousMixV2Metrics
    var out: [EuclideousMixLineGeometry] = []
    for part in 0..<8 {
        guard part < masks.count, part < partOn.count, partOn[part] else { continue }
        let lane = part / 2, notes = part % 2 == 1
        let band = layout.bands[lane]
        let y0 = band.inner.minY + band.row(notes: notes).centreY
        for o in 0..<4 where masks[part] & (UInt8(1) << UInt8(o)) != 0 {
            let y1 = layout.emitters[o].midY
            out.append(EuclideousMixLineGeometry(part: part, output: o, lane: lane, from: CGPoint(x: layout.bandW, y: y0), c1: CGPoint(x: layout.bandW + M.lineBend1, y: y0),
                                                 c2: CGPoint(x: layout.bandW + M.lineBend2, y: y1), to: CGPoint(x: layout.bandW + M.emitterX, y: y1)))
        }
    }
    return out
}

// MARK: - §6.2 the emitters

enum EuclideousMixV2EmitterMetrics { static let ringHex: UInt32 = 0xDFE3EA, idleFillHex: UInt32 = 0x1F2127, idleLetterHex: UInt32 = 0xDFE3EA, activeFillHex: UInt32 = 0xDFE3EA, activeLetterHex: UInt32 = 0x0D0F14, ring: CGFloat = 3, letterSize: CGFloat = 14 }

// MARK: - §10 VoiceOver

enum EuclideousMixV2AX {
    static func part(notes: Bool) -> String { notes ? "Notes" : "Riff" }
    static func solo(notes: Bool, lane: Int) -> String { "Solo \(notes ? "notes" : "riff"), lane \(lane + 1)" }
    static func soloValue(latched: Bool) -> String { latched ? "on" : "off" }
    static let soloHint = "Tap to latch; hold to solo while held"
    /// "Pool, C3 to E♭5"; an empty pool "Pool, empty".
    static func pool(lowest: String?, highest: String?) -> String { guard let lo = lowest, let hi = highest else { return "Pool, empty" }; return lo == hi ? "Pool, \(lo)" : "Pool, \(lo) to \(hi)" }
    /// "Riff playing rank 4", "Riff playing ranks 2, 4 and 6", "Riff silent".
    static func stack(notes: Bool, ranks: [Int]) -> String {
        let p = part(notes: notes)
        switch ranks.count {
        case 0: return "\(p) silent"
        case 1: return "\(p) playing rank \(ranks[0])"
        case 2: return "\(p) playing ranks \(ranks[0]) and \(ranks[1])"
        default: return "\(p) playing ranks " + ranks.dropLast().map(String.init).joined(separator: ", ") + " and \(ranks.last!)"
        }
    }
    static func transpose(notes: Bool, value: Int) -> String { "\(part(notes: notes)) transpose \(euclideousMixV2TransText(value))" }
    static func octave(notes: Bool, value: Int) -> String { "\(part(notes: notes)) octave \(euclideousOctValueText(value))" }
    static let reset = "Reset"
}

// MARK: - §3.2 the pool never lights

/// The eight chips (rank 8 … 1) for a lane's pool — never lit (§3.2: the pool takes no touches and shows no sounding; the STACKS show what plays).
func euclideousMixV2PoolChips(sortedPool: [Int], name: (Int) -> String) -> [EuclideousMixPoolChip] { euclideousMixPoolChips(sortedPool: sortedPool, lit: 0, name: name) }

// MARK: - §4.7 the TRANS tile's touch machine

/// What a touch-down on the TRANS tile does: step the value (one undo step), or — a second tap on the LEFT part within the double-tap window — set it to 0.
enum EuclideousMixV2TransAction: Equatable { case step(up: Bool), reset }
/// §4.7: the tile's whole row height is the target (upper half up, lower half down); the left part (x < 34) is also the double-tap zone for 0. Two touch-downs inside `doubleTapWindow` that both land on the left part reset; a third is a fresh tap.
struct EuclideousMixV2TransPress: Equatable {
    static let doubleTapWindow: Double = 0.3
    private(set) var lastLeftDownAt: Double? = nil
    mutating func touchDown(at t: Double, x: CGFloat, y: CGFloat, targetHeight: CGFloat) -> EuclideousMixV2TransAction {
        let left = x < EuclideousMixV2Metrics.transLeftW
        if left, let last = lastLeftDownAt, t - last <= Self.doubleTapWindow {
            lastLeftDownAt = nil
            return .reset
        }
        lastLeftDownAt = left ? t : nil
        return .step(up: euclideousMixV2TransTapIsUp(y: y, targetHeight: targetHeight))
    }
}

// MARK: - §5 the OCT boxes' touch: tap or drag

/// A finger on the five boxes: the first box it lands on is selected (one undo step) unless it is already the selection; sliding to another box selects that one inside the SAME step; a tap on the selected box writes nothing.
struct EuclideousOctaveTouch: Equatable {
    private(set) var wrote = false
    /// The write (value, startsNewUndoStep) a finger at `index` asks for while the stored value is `current`; nil = nothing to write.
    mutating func move(to index: Int, current: Int) -> (value: Int, newStep: Bool)? {
        let v = euclideousOctValue(index: index)
        guard v != euclideousOctSelectedValue(current) else { return nil }
        defer { wrote = true }
        return (v, !wrote)
    }
    mutating func end() { wrote = false }
}
/// The stored value as the selected box shows it (clamped to −2…+2).
func euclideousOctSelectedValue(_ stored: Int) -> Int { max(-2, min(2, stored)) }

// MARK: - §4.4 the part toggle's tile

/// The riff's dot grid, from the ONE function the RIFF tab's thumbnail and MIX's toggle both read: per column the ranks (1…8) it plays, which columns lie in the walk's window, the never-played ones and the live step.
struct EuclideousRiffGlyph: Equatable {
    var columns: Int
    /// `hits[col * 8 + (rank − 1)]`
    var hits: [Bool]
    var inWindow: [Bool]
    var neverPlay: [Bool]
    var current: Int
    func isHit(col: Int, rank: Int) -> Bool { col >= 0 && col < columns && rank >= 1 && rank <= 8 && col * 8 + rank - 1 < hits.count && hits[col * 8 + rank - 1] }
    func opacity(col: Int) -> Double { (col < inWindow.count && !inWindow[col]) || (col < neverPlay.count && neverPlay[col]) ? 0.32 : 1.0 }
}
/// MONO: a column's rank is the stencil's; POLY: a note covers every column it spans (`covering`), INVERT / TRANSPOSE turn the written rank into the row it shows on.
func euclideousRiffGlyph(columns n: Int, poly: Bool, stepRanks: [Int], polyCovers: (_ col: Int, _ writtenRank: Int) -> Bool, invert: Bool, transpose: Int,
                         window: Set<Int>, neverPlay: Set<Int>, current: Int) -> EuclideousRiffGlyph {
    var hits = [Bool](repeating: false, count: n * 8)
    for col in 0..<n {
        for rank in 1...8 {
            if poly {
                let src = invert ? 9 - (rank - transpose) : rank - transpose
                hits[col * 8 + rank - 1] = src >= 1 && src <= 8 && polyCovers(col, src)
            } else {
                let raw = col < stepRanks.count ? stepRanks[col] : 0
                hits[col * 8 + rank - 1] = raw >= 1 && raw <= 8 && raw == rank
            }
        }
    }
    return EuclideousRiffGlyph(columns: n, hits: hits, inWindow: (0..<n).map { window.contains($0) }, neverPlay: (0..<n).map { neverPlay.contains($0) }, current: current)
}

struct EuclideousMixV2ToggleLook: Equatable {
    /// nil = the plate has no fill (OUTLINE on)
    var fillHex: UInt32?
    var fillIsLane: Bool
    var borderIsLane: Bool
    var borderAlpha: Double
    var borderWidth: CGFloat
    var borderHex: UInt32
    /// The glyph: its lit-cell colour, its background-cell colour and alpha, and whether the glyph wears the lane colour.
    var glyphHex: UInt32
    var glyphIsLane: Bool
    var backdropHex: UInt32
    var backdropAlpha: Double
}
enum EuclideousMixToggleMode: String, CaseIterable { case filled = "FILLED", outline = "OUTLINE" }
let euclideousMixToggleModeKey = "fourfold.mixToggleMode"
/// §4.4 / §8.1. FILLED: on = lane100 fill, glyph ink #0D0F14 (backdrop ink at 28 %); off = #1F2127 with a 1.5 pt lane100 border at 45 %, glyph #8A909A (backdrop #3A3E47). OUTLINE: on = #1F2127 with a 1.5 pt lane100 border and a lane100 glyph (backdrop rgba(223,227,234,0.14)); off as FILLED's off.
func euclideousMixV2ToggleLook(on: Bool, mode: EuclideousMixToggleMode) -> EuclideousMixV2ToggleLook {
    if !on {
        return EuclideousMixV2ToggleLook(fillHex: 0x1F2127, fillIsLane: false, borderIsLane: true, borderAlpha: 0.45, borderWidth: 1.5, borderHex: 0, glyphHex: 0x8A909A, glyphIsLane: false, backdropHex: 0x3A3E47, backdropAlpha: 1)
    }
    switch mode {
    case .filled: return EuclideousMixV2ToggleLook(fillHex: nil, fillIsLane: true, borderIsLane: false, borderAlpha: 0, borderWidth: 0, borderHex: 0, glyphHex: 0x0D0F14, glyphIsLane: false, backdropHex: 0x0D0F14, backdropAlpha: 0.28)
    case .outline: return EuclideousMixV2ToggleLook(fillHex: 0x1F2127, fillIsLane: false, borderIsLane: true, borderAlpha: 1, borderWidth: 1.5, borderHex: 0, glyphHex: 0, glyphIsLane: true, backdropHex: 0xDFE3EA, backdropAlpha: 0.14)
    }
}
/// The glyph's frame inside the 48 × tileH tile: 5 pt in on every side.
func euclideousMixV2ToggleGlyphFrame(tile: CGSize) -> CGRect { CGRect(x: 5, y: 5, width: max(0, tile.width - 10), height: max(0, tile.height - 10)) }
/// The dot grid's cells in a glyph frame: `columns` across with 1 pt gaps, 8 rows (rank 8 at the top).
func euclideousMixV2RiffCellFrames(glyph: CGRect, columns n: Int) -> [[CGRect]] {
    let cw = max(0, (glyph.width - CGFloat(n - 1)) / CGFloat(n)), ch = max(0, (glyph.height - 7) / 8)
    return (0..<n).map { col in (0..<8).map { row in CGRect(x: glyph.minX + CGFloat(col) * (cw + 1), y: glyph.minY + CGFloat(row) * (ch + 1), width: cw, height: ch) } }
}
/// The NOTES tile's glyph: eight lit-note bars (rank 8 at the top), lit at full strength, unlit at 25 % — `notesStrip`'s own bars.
func euclideousMixV2NotesBarFrames(glyph: CGRect) -> [CGRect] {
    let h = max(0, (glyph.height - 7) / 8)
    return (0..<8).map { CGRect(x: glyph.minX, y: glyph.minY + CGFloat($0) * (h + 1), width: glyph.width, height: h) }
}

// MARK: - §4.6 VEL / GATE: the OFFSET tile's looks at the part row's frame

enum EuclideousMixV2FieldLook {
    static let radius: CGFloat = 8, groundHex: UInt32 = 0x22252C, inset: CGFloat = 6
    static let fillHex: UInt32 = 0xDFE3EA, fillAlpha = 0.07, edge: CGFloat = 2
    static let tickW: CGFloat = 1, tickH: CGFloat = 5, tickHex: UInt32 = 0x4A4E57
    static let valueBackingHex: UInt32 = 0x131519, valueBackingAlpha = 0.78, valueBackingRadius: CGFloat = 3
    static let labelHex: UInt32 = 0xAAB0BA, valueHex: UInt32 = 0xF2F4F7
}
/// The nine ticks at tenths (fractions 0.1 … 0.9) — OFFSET's ticks, at the spec's count.
let euclideousMixV2FieldTickFracs: [Double] = (1...9).map { Double($0) / 10 }
/// OFFSET's text sizes (label 10 pt semibold, value 13 pt heavy) where the tile is wide enough for both strings (monospaced: 0.6 em a character, tracking 0.8, 3 pt padding a side, 12 pt of insets, 4 between); otherwise the ferry's 7 / 11.
func euclideousMixV2FieldTextSizes(tileWidth: CGFloat, labelChars: Int, valueChars: Int) -> (label: CGFloat, value: CGFloat) {
    let need = CGFloat(labelChars) * (6 + 0.8) + 6 + CGFloat(valueChars) * 7.8 + 6 + 4 + 12
    return need <= tileWidth ? (10, 13) : (7, 11)
}
/// The fill, the marker and the travel for a value fraction in a V-wide tile (the travel inset is OFFSET's 6).
func euclideousMixV2FieldGeometry(size: CGSize, frac: Double) -> (fill: CGRect, edge: CGRect, travel: CGFloat) {
    typealias F = EuclideousMixV2FieldLook
    let travel = max(1, size.width - F.inset * 2)
    let x = F.inset + CGFloat(max(0, min(1, frac))) * travel
    return (CGRect(x: 0, y: 0, width: x, height: size.height), CGRect(x: x - F.edge / 2, y: 0, width: F.edge, height: size.height), travel)
}

// MARK: - §5.5 OCT on the RIFF and NOTES tabs

/// The five boxes right-aligned in the tab's OCT frame — 30 wide each where the frame has room for them and the "OCT" label (7 pt heavy, 0.2 em ≈ 17 pt) sp6 to their left, narrower otherwise — the frame's full height; the label's frame to their left.
func euclideousOctRowLayout(frame: CGSize) -> (label: CGRect, boxes: CGRect) {
    let labelW: CGFloat = 17, gap: CGFloat = 6
    let boxW = max(1, min(30, ((frame.width - labelW - gap) / 5).rounded(.down)))
    let boxes = CGRect(x: frame.width - 5 * boxW, y: 0, width: 5 * boxW, height: frame.height)
    return (CGRect(x: max(0, boxes.minX - gap - labelW), y: 0, width: labelW, height: frame.height), boxes)
}
