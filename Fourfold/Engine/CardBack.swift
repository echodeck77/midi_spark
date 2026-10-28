//  CardBack.swift
//  CARD BACKS ferry (2026-10-28): the pure functions behind the lane cards' rear panel — the header's PATTERN | MIX switch (§3.1), the flip (§3.3), the back's frames (§4), the roll's maths (§5), the XY pad and OCT drawing numbers
//  (§6), the jacks' looks and activity (§7) and the VoiceOver strings (§11). Foundation only, on purpose (the macOS test target compiles this file directly); the views paint these and nothing else, so every frame, colour, size
//  and word is decided — and tested — in one place.
//
//  Paul's decisions overriding the ferry text: the AU keeps its ALL output (five outputs: All, A–D), and the switch is 116 pt wide, not 132 (so layout A still holds at a 1190 pt view).
//  Where the ferry and the source disagree about an existing value the SOURCE wins and the difference is named at the function (the tab row's top: 60 in source, 62 in the ferry — `EuclideousCardBackMetrics.stripTop*`).

import Foundation

// MARK: - §3.1 PATTERN | MIX — the header switch

enum EuclideousCardSide: Int, Equatable { case pattern = 0, mix = 1
    var other: EuclideousCardSide { self == .pattern ? .mix : .pattern }
}

enum EuclideousCardSwitchMetrics {
    /// §3.1 (Paul: 116, the ferry said 132): container width. 3 inset + PATTERN 64 + 3 gap + MIX 43 + 3 inset.
    static let width: CGFloat = 116
    static let inset: CGFloat = 3, segmentGap: CGFloat = 3, segmentHeight: CGFloat = 25
    static let patternWidth: CGFloat = 64
    static var mixWidth: CGFloat { width - 2 * inset - segmentGap - patternWidth }       // "MIX taking the rest" = 43
    static var containerHeight: CGFloat { segmentHeight + 2 * inset }                      // 31
    static let containerRadius: CGFloat = 8, segmentRadius: CGFloat = 6
    static let targetHeight: CGFloat = 44
    static let fontSize: CGFloat = 9, tracking: CGFloat = 0.06
    static let container = HocketColor(0x1F2127), selectedFill = HocketColor(0xDFE3EA), selectedText = HocketColor(0x0D0F14), unselectedText = HocketColor(0xAAB0BA)
}
struct EuclideousCardSwitchFrames: Equatable {
    var container: CGRect
    var pattern: CGRect, mix: CGRect                       // the drawn segments (25 tall)
    var patternTarget: CGRect, mixTarget: CGRect           // the touch targets: 44 tall, together covering the whole container width
}
/// The switch's frames for its leading edge `x` and the y of its row's centre line.
func euclideousCardSwitchFrames(x: CGFloat, rowMidY: CGFloat) -> EuclideousCardSwitchFrames {
    typealias M = EuclideousCardSwitchMetrics
    let top = rowMidY - M.containerHeight / 2
    let pattern = CGRect(x: x + M.inset, y: top + M.inset, width: M.patternWidth, height: M.segmentHeight)
    let mix = CGRect(x: pattern.maxX + M.segmentGap, y: top + M.inset, width: M.mixWidth, height: M.segmentHeight)
    let split = pattern.maxX + M.segmentGap / 2                                           // the targets meet in the middle of the 3 pt gap
    let ty = rowMidY - M.targetHeight / 2
    return EuclideousCardSwitchFrames(container: CGRect(x: x, y: top, width: M.width, height: M.containerHeight), pattern: pattern, mix: mix,
                                      patternTarget: CGRect(x: x, y: ty, width: split - x, height: M.targetHeight),
                                      mixTarget: CGRect(x: split, y: ty, width: x + M.width - split, height: M.targetHeight))
}
/// §3.2: a tap on the unselected segment flips all four cards to that side; a tap on the selected one does nothing. The side to flip to, or nil.
func euclideousCardSwitchTapTarget(tapped: EuclideousCardSide, current: EuclideousCardSide) -> EuclideousCardSide? { tapped == current ? nil : tapped }

// MARK: - §3.3 / §3.5 the flip

enum EuclideousCardFlipMetrics {
    static let duration: Double = 0.280, stagger: Double = 0.070, reduceMotionDuration: Double = 0.150
    static let laneCount = 4
    /// Every card has finished: the last lane starts `stagger × 3` late.
    static var totalDuration: Double { duration + stagger * Double(laneCount - 1) }      // 0.49
}
/// CSS-style ease-in-out (quadratic), 0…1 → 0…1, symmetric about the midpoint.
func euclideousEaseInOut(_ p: Double) -> Double {
    let x = max(0, min(1, p))
    return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
}
/// What one card shows `sinceTap` seconds after the tap. `side` is the side drawn on top (with `opacity`); `underSide` is drawn beneath it while a Reduce-Motion crossfade runs.
struct EuclideousCardFlipFrame: Equatable {
    var scaleX: CGFloat
    var side: EuclideousCardSide
    var opacity: Double
    var underSide: EuclideousCardSide?
    var underOpacity: Double
    /// Touches on the card are ignored from the tap until it has finished turning.
    var ignoresTouches: Bool
}
/// §3.3 / §3.5. `lane` is 0-based (lane 1 = 0): lane n starts n × 70 ms after the tap, then scales horizontally about its centre 1 → 0 → 1 over 280 ms, easeInOut, swapping its side at the midpoint (scale 0). With Reduce Motion: a 150 ms
/// crossfade of all four at once, no scaling at all. `t < 0` is before the tap (the old side, untouched); the old side is always the other one from `target`.
/// Interpretation to confirm on device: the ease runs over the WHOLE 280 ms (so the scale passes 0 at its fastest), not once per half.
func euclideousCardFlip(sinceTap t: Double, lane: Int, target: EuclideousCardSide, reduceMotion: Bool = false) -> EuclideousCardFlipFrame {
    typealias M = EuclideousCardFlipMetrics
    let from = target.other
    if t < 0 { return EuclideousCardFlipFrame(scaleX: 1, side: from, opacity: 1, underSide: nil, underOpacity: 0, ignoresTouches: false) }
    if reduceMotion {
        if t >= M.reduceMotionDuration { return EuclideousCardFlipFrame(scaleX: 1, side: target, opacity: 1, underSide: nil, underOpacity: 0, ignoresTouches: false) }
        let p = t / M.reduceMotionDuration
        return EuclideousCardFlipFrame(scaleX: 1, side: target, opacity: p, underSide: from, underOpacity: 1 - p, ignoresTouches: true)
    }
    let local = euclideousMicroseconds(t - Double(max(0, lane)) * M.stagger)               // exact boundaries: the midpoint and the end are not a rounding error away
    if local < 0 { return EuclideousCardFlipFrame(scaleX: 1, side: from, opacity: 1, underSide: nil, underOpacity: 0, ignoresTouches: true) }   // committed, waiting its turn
    if local >= M.duration { return EuclideousCardFlipFrame(scaleX: 1, side: target, opacity: 1, underSide: nil, underOpacity: 0, ignoresTouches: false) }
    let p = local / M.duration
    let scale = abs(1 - 2 * euclideousEaseInOut(p))
    return EuclideousCardFlipFrame(scaleX: CGFloat(scale), side: p < 0.5 ? from : target, opacity: 1, underSide: nil, underOpacity: 0, ignoresTouches: true)
}
/// Is any card still turning (so the page needs its frame clock)?
func euclideousCardFlipIsLive(since t: Double, reduceMotion: Bool = false) -> Bool {
    let now = euclideousMicroseconds(t)
    return now >= 0 && now < euclideousMicroseconds(reduceMotion ? EuclideousCardFlipMetrics.reduceMotionDuration : EuclideousCardFlipMetrics.totalDuration)
}
/// Seconds rounded to the microsecond (flip times are sums of 70 / 280 ms steps; this keeps their comparisons exact).
func euclideousMicroseconds(_ t: Double) -> Double { (t * 1_000_000).rounded() / 1_000_000 }

// MARK: - §4 the card back's frames

enum EuclideousCardPart: Int, Equatable { case riff = 0, notes = 1
    var label: String { self == .riff ? "RIFF" : "NOTES" }
    var spoken: String { self == .riff ? "Riff" : "Notes" }
    /// §5.4 / clarity pass §2: RIFF is a 9 × 9 square, NOTES a 6 × 12 bar.
    var glyphSize: CGSize { self == .riff ? CGSize(width: 9, height: 9) : CGSize(width: 6, height: 12) }
}

enum EuclideousCardBackMetrics {
    static let inset: CGFloat = EuclideousLaneCardMetrics.inset                            // 10: the content box's side and bottom inset
    static let sp4: CGFloat = 4, sp8: CGFloat = 8
    /// The MIX strip's top. SOURCE (the lane card): inset 10 + comet row 44 + gap 6 = 60, where the RHYTHM / RIFF / NOTES / LISTEN tab row starts. The FERRY's reference numbers put the strip at y 62 (tiles y 10–52, tab row top 62):
    /// a 2 pt difference. Source wins; both are testable through `euclideousCardBackLayout(card:stripTop:)`.
    static var stripTopSource: CGFloat { EuclideousLaneCardMetrics.inset + EuclideousLaneCardMetrics.cometRowH + EuclideousLaneCardMetrics.rowGap }
    static let stripTopFerry: CGFloat = 62
    static let stripHeight: CGFloat = 22, stripRadius: CGFloat = 6, stripPadX: CGFloat = 9
    static let stripFont: CGFloat = 10, stripTracking: CGFloat = 0.14
    static let fillColor = HocketColor(0x17191E), borderAlpha = 0.28, borderWidth: CGFloat = 1
    static let stripAlpha = 0.12
    // inside a row (§4.4)
    static let leftColumnWidth: CGFloat = 92, columnGap: CGFloat = 8
    static let octHeight: CGFloat = 28, octGap: CGFloat = 4
    static var xyBelow: CGFloat { octHeight + octGap }                                      // the XY pad ends 32 above the row's bottom
    static let jackStripHeight: CGFloat = 46
    static let jackCount = 4
    // floors (§4.5)
    static let floorXY: CGFloat = 44, floorRoll: CGFloat = 40, floorJackCellWidth: CGFloat = 46
    // jack cell internals (§7.2)
    static let lightSize: CGFloat = 6, lightInset: CGFloat = 8
    static let socketSize: CGFloat = 24, socketInset: CGFloat = 18
    static let letterInset: CGFloat = 46, letterFont: CGFloat = 10
    /// CARD BACKS review (2026-10-28): a cell narrower than `letterInset` + the letter (≈ 6.6 pt) + 1 pulls the light, the socket and the letter in (5 / 13 / 39) so the letter stays inside it down to `floorJackCellWidth`.
    static let tightLightInset: CGFloat = 5, tightSocketInset: CGFloat = 13, tightLetterInset: CGFloat = 39
    static var letterAdvance: CGFloat { letterFont * EuclideousCardLabelMetrics.monoAdvance }
    static var tightBelow: CGFloat { letterInset + letterAdvance + 1 }
    static let seamHeight: CGFloat = 2
}

struct EuclideousCardBackFloor: Equatable {
    var name: String
    var value: CGFloat
    var floor: CGFloat
}
/// One part's row, in CARD coordinates.
struct EuclideousCardBackPartFrames: Equatable {
    var row: CGRect
    var xy: CGRect, oct: CGRect
    var rollPanel: CGRect, roll: CGRect, jackStrip: CGRect, seam: CGRect
    var jackCells: [CGRect], jackLights: [CGRect], jackSockets: [CGRect], jackLetters: [CGRect]
}
struct EuclideousCardBackLayout: Equatable {
    var card: CGSize
    var strip: CGRect
    var riff: EuclideousCardBackPartFrames, notes: EuclideousCardBackPartFrames
    var rowHeight: CGFloat
    /// Every floor under its minimum at this card size (drawn at the formula's values and listed, never shrunk — the page's own rule).
    var floors: [EuclideousCardBackFloor]
    func part(_ p: EuclideousCardPart) -> EuclideousCardBackPartFrames { p == .riff ? riff : notes }
}
/// §4.3–4.5 and §7.2: every frame on the back from the card's size. The content box is the card inset by 10; the MIX strip starts at `stripTop`; the two rows split what is left under the strip, sp8 apart and sp8 below it:
/// rowH = (contentBottom − stripBottom − 2·sp8) ÷ 2. In a row: the left column (92 wide: the XY pad, sp4, OCT 28 tall at the bottom), sp8, then the roll panel — the roll (rowH − 46 tall) on top of the 46-tall jack strip.
func euclideousCardBackLayout(card: CGSize, stripTop: CGFloat = EuclideousCardBackMetrics.stripTopSource) -> EuclideousCardBackLayout {
    typealias M = EuclideousCardBackMetrics
    let x0 = M.inset, w = max(1, card.width - 2 * M.inset)
    let bottom = card.height - M.inset
    let strip = CGRect(x: x0, y: stripTop, width: w, height: M.stripHeight)
    let rowH = (bottom - strip.maxY - 2 * M.sp8) / 2
    func part(rowTop: CGFloat) -> EuclideousCardBackPartFrames {
        let row = CGRect(x: x0, y: rowTop, width: w, height: rowH)
        let xy = CGRect(x: x0, y: rowTop, width: M.leftColumnWidth, height: rowH - M.xyBelow)
        let oct = CGRect(x: x0, y: rowTop + rowH - M.octHeight, width: M.leftColumnWidth, height: M.octHeight)
        let panelX = x0 + M.leftColumnWidth + M.columnGap
        let panel = CGRect(x: panelX, y: rowTop, width: max(1, w - M.leftColumnWidth - M.columnGap), height: rowH)
        let roll = CGRect(x: panelX, y: rowTop, width: panel.width, height: rowH - M.jackStripHeight)
        let jackStrip = CGRect(x: panelX, y: roll.maxY, width: panel.width, height: M.jackStripHeight)
        let seam = CGRect(x: panelX, y: jackStrip.minY, width: panel.width, height: M.seamHeight)
        let cellW = panel.width / CGFloat(M.jackCount)
        var cells: [CGRect] = [], lights: [CGRect] = [], sockets: [CGRect] = [], letters: [CGRect] = []
        for i in 0..<M.jackCount {
            let cell = CGRect(x: panelX + CGFloat(i) * cellW, y: jackStrip.minY, width: cellW, height: M.jackStripHeight)
            cells.append(cell)
            let tight = cellW < M.tightBelow
            let lightIn = tight ? M.tightLightInset : M.lightInset, socketIn = tight ? M.tightSocketInset : M.socketInset, letterIn = tight ? M.tightLetterInset : M.letterInset
            lights.append(CGRect(x: cell.minX + lightIn, y: cell.midY - M.lightSize / 2, width: M.lightSize, height: M.lightSize))
            sockets.append(CGRect(x: cell.minX + socketIn, y: cell.midY - M.socketSize / 2, width: M.socketSize, height: M.socketSize))
            let letterW = max(1, cell.width - letterIn)
            letters.append(CGRect(x: cell.minX + letterIn, y: cell.midY - M.letterFont * 0.6, width: letterW, height: M.letterFont * 1.2))
        }
        return EuclideousCardBackPartFrames(row: row, xy: xy, oct: oct, rollPanel: panel, roll: roll, jackStrip: jackStrip, seam: seam,
                                            jackCells: cells, jackLights: lights, jackSockets: sockets, jackLetters: letters)
    }
    let riff = part(rowTop: strip.maxY + M.sp8)
    let notes = part(rowTop: riff.row.maxY + M.sp8)
    var floors: [EuclideousCardBackFloor] = []
    let cell = riff.jackCells[0].width
    if riff.xy.height < M.floorXY { floors.append(EuclideousCardBackFloor(name: "XY pad height", value: riff.xy.height, floor: M.floorXY)) }
    if riff.roll.height < M.floorRoll { floors.append(EuclideousCardBackFloor(name: "roll height", value: riff.roll.height, floor: M.floorRoll)) }
    if cell < M.floorJackCellWidth { floors.append(EuclideousCardBackFloor(name: "jack cell width", value: cell, floor: M.floorJackCellWidth)) }
    // review 2026-10-28: the roll must be wide enough for the label pill AND the widest invitation side by side (5 + label + gap + invitation + 5), else the invitation overlaps the label
    let rollNeeds = euclideousCardInvitationRollWidthFloor()
    if riff.roll.width < rollNeeds { floors.append(EuclideousCardBackFloor(name: "roll width for the label and its invitation", value: riff.roll.width, floor: rollNeeds)) }
    return EuclideousCardBackLayout(card: card, strip: strip, riff: riff, notes: notes, rowHeight: rowH, floors: floors)
}

// MARK: - §5.4 the label pill, §5.6 the invitations

enum EuclideousCardLabelMetrics {
    static let inset: CGFloat = 5, height: CGFloat = 20, radius: CGFloat = 5, padX: CGFloat = 7, glyphGap: CGFloat = 6
    static let font: CGFloat = 9, tracking: CGFloat = 0.12, targetHeight: CGFloat = 44
    static let fill = HocketColor(0x131519, 0.82), offAlpha = 0.55
    static let monoAdvance: CGFloat = 0.66      // SF Mono Heavy measures ≈ 0.66 em an advance on device (0.6 clipped "TURN ON NOTES" to "TURN ON NOT…")
    static func textWidth(_ chars: Int, size: CGFloat, tracking em: CGFloat) -> CGFloat { CGFloat(chars) * size * (monoAdvance + em) }
}
struct EuclideousCardLabelFrames: Equatable {
    var pill: CGRect, target: CGRect, glyph: CGRect, text: CGRect
}
/// §5.4: top-left of the roll, 5 pt in: a pill 20 tall (radius 5, 7 pt side padding) holding the part's glyph, 6 pt, then the label (9 pt heavy, 0.12 em); a 44-tall touch target centred on the pill.
func euclideousCardLabelFrames(roll: CGRect, part: EuclideousCardPart) -> EuclideousCardLabelFrames {
    typealias L = EuclideousCardLabelMetrics
    let g = part.glyphSize
    let textW = L.textWidth(part.label.count, size: L.font, tracking: L.tracking)
    let pill = CGRect(x: roll.minX + L.inset, y: roll.minY + L.inset, width: L.padX + g.width + L.glyphGap + textW + L.padX, height: L.height)
    let glyph = CGRect(x: pill.minX + L.padX, y: pill.midY - g.height / 2, width: g.width, height: g.height)
    let text = CGRect(x: glyph.maxX + L.glyphGap, y: pill.minY, width: textW, height: L.height)
    return EuclideousCardLabelFrames(pill: pill, target: CGRect(x: pill.minX, y: pill.midY - L.targetHeight / 2, width: pill.width, height: L.targetHeight), glyph: glyph, text: text)
}

/// The narrowest roll that holds the NOTES label pill (the wider of the two) and the widest invitation (TURN ON NOTES) side by side without touching.
func euclideousCardInvitationRollWidthFloor() -> CGFloat {
    typealias L = EuclideousCardLabelMetrics
    typealias I = EuclideousCardInvitationMetrics
    let label = L.padX + EuclideousCardPart.notes.glyphSize.width + L.glyphGap + L.textWidth(EuclideousCardPart.notes.label.count, size: L.font, tracking: L.tracking) + L.padX
    let inv = I.padX + I.plus + I.plusGap + L.textWidth(EuclideousCardInvitation.turnOnNotes.label.count, size: I.font, tracking: I.tracking) + I.padX
    return L.inset + label + I.labelGap + inv + L.inset
}
enum EuclideousCardInvitation: Equatable {
    case turnOnRiff, turnOnNotes, addHits
    var label: String { switch self { case .turnOnRiff: return "TURN ON RIFF"; case .turnOnNotes: return "TURN ON NOTES"; case .addHits: return "ADD HITS" } }
}
enum EuclideousCardInvitationMetrics {
    static let pillHeight: CGFloat = 28, radius: CGFloat = 7, padX: CGFloat = 10, targetHeight: CGFloat = 44, labelGap: CGFloat = 6
    static let plus: CGFloat = 9, plusStroke: CGFloat = 1.6, plusGap: CGFloat = 6
    static let font: CGFloat = 8, tracking: CGFloat = 0.1
    static let fillAlpha = 0.20, borderWidth: CGFloat = 1
}
struct EuclideousCardInvitationFrames: Equatable { var pill: CGRect, target: CGRect, plus: CGRect, text: CGRect }
/// §5.6: centred in the roll — a pill 28 tall (10 pt side padding): a 9 × 9 plus, 6 pt, the label (8 pt heavy, 0.1 em); a 44-tall target. It draws at full strength over the 42 % dim.
/// `avoiding` (the label pill's frame, review 2026-10-28): a roll too narrow for both pills centred slides the invitation right until it clears the label by `labelGap` — never past the roll's right edge less its inset; if even that overlaps
/// (a roll narrower than the two pills together) it stays right-aligned, drawn above the label, and its touch target — the later sibling — takes the shared taps.
func euclideousCardInvitationFrames(roll: CGRect, _ kind: EuclideousCardInvitation, avoiding label: CGRect? = nil) -> EuclideousCardInvitationFrames {
    typealias I = EuclideousCardInvitationMetrics
    let textW = EuclideousCardLabelMetrics.textWidth(kind.label.count, size: I.font, tracking: I.tracking)
    let w = I.padX + I.plus + I.plusGap + textW + I.padX
    var x = roll.midX - w / 2
    if let label, x < label.maxX + I.labelGap {
        x = min(label.maxX + I.labelGap, roll.maxX - EuclideousCardLabelMetrics.inset - w)
        if x < roll.minX { x = roll.minX }
    }
    let pill = CGRect(x: x, y: roll.midY - I.pillHeight / 2, width: w, height: I.pillHeight)
    return EuclideousCardInvitationFrames(pill: pill, target: CGRect(x: pill.minX, y: roll.midY - I.targetHeight / 2, width: w, height: I.targetHeight),
                                          plus: CGRect(x: pill.minX + I.padX, y: pill.midY - I.plus / 2, width: I.plus, height: I.plus),
                                          text: CGRect(x: pill.minX + I.padX + I.plus + I.plusGap, y: pill.minY, width: textW, height: I.pillHeight))
}
/// §5.6: which invitation (if any) the roll offers — one at a time: the part off ⇒ TURN ON <part>; on but the lane's rhythm has no hits ⇒ ADD HITS.
func euclideousCardInvitation(part: EuclideousCardPart, partOn: Bool, laneHasHits: Bool) -> EuclideousCardInvitation? {
    if !partOn { return part == .riff ? .turnOnRiff : .turnOnNotes }
    return laneHasHits ? nil : .addHits
}

// MARK: - §6 the XY pad and OCT

/// The XY pad is the MIX pad's VEL / GATE control for a part: X = GATE, Y = VEL (up louder) — the same axes and ranges as `EuclideousMixPadGeometry`, minus its strips (the back's pad has none): the dot's travel is inset 7 at every
/// edge, gate % = round((x − 7) ÷ (w − 14) × 100) clamped 1…99, velocity = round((h − 7 − y) ÷ (h − 14) × 127) clamped 1…127.
enum EuclideousCardXYMetrics {
    static let inset: CGFloat = 7, dot: CGFloat = 11, dotRing: CGFloat = 2, radius: CGFloat = 8, textInset: CGFloat = 5
    static let well = HocketColor(0x131519), border = HocketColor(0x262930), text = HocketColor(0xDFE3EA)
    static let fillAlpha = 0.22, crosshairAlpha = 0.60, crosshairWidth: CGFloat = 1, textFont: CGFloat = 8, textTracking: CGFloat = 0.06
}
func euclideousCardXYDot(gate: Double, velocity: Int, in pad: CGRect) -> CGPoint {
    typealias X = EuclideousCardXYMetrics
    let tx = pad.width - 2 * X.inset, ty = pad.height - 2 * X.inset
    return CGPoint(x: pad.minX + X.inset + CGFloat(gate) * tx, y: pad.maxY - X.inset - CGFloat(max(1, min(127, velocity))) / 127 * ty)
}
func euclideousCardXYValues(at p: CGPoint, in pad: CGRect) -> (gate: Double, velocity: Int) {
    typealias X = EuclideousCardXYMetrics
    let tx = max(1, pad.width - 2 * X.inset), ty = max(1, pad.height - 2 * X.inset)   // (review 2026-10-28: a pad exactly 2 × the inset tall divided by zero and trapped in `Int(...)`)
    let g = Int((Double((p.x - pad.minX - X.inset) / tx) * 100).rounded())
    let v = Int((Double((pad.maxY - X.inset - p.y) / ty) * 127).rounded())
    return (Double(max(1, min(Int(euclideousLaneGateMax * 100), g))) / 100, max(1, min(127, v)))
}
/// §6.2: lane100 at 22 % "from the left edge to the dot and from the dot down to the bottom" — the rectangle below-left of the dot.
func euclideousCardXYFillRect(dot: CGPoint, in pad: CGRect) -> CGRect {
    CGRect(x: pad.minX, y: dot.y, width: max(0, dot.x - pad.minX), height: max(0, pad.maxY - dot.y))
}
/// The two crosshair lines (1 pt) through the dot, across the whole pad.
func euclideousCardXYCrosshair(dot: CGPoint, in pad: CGRect) -> (horizontal: CGRect, vertical: CGRect) {
    let w = EuclideousCardXYMetrics.crosshairWidth
    return (CGRect(x: pad.minX, y: dot.y - w / 2, width: pad.width, height: w), CGRect(x: dot.x - w / 2, y: pad.minY, width: w, height: pad.height))
}
/// "VEL 24" top-left and "38%" bottom-right, 5 pt in (8 pt heavy, 0.06 em, #DFE3EA). The gate text is the page's own (`euclideousMixGateValueText`).
func euclideousCardXYTexts(gate: Double, velocity: Int) -> (vel: String, gate: String) { ("VEL \(velocity)", euclideousMixGateValueText(gate: gate)) }

enum EuclideousCardOctMetrics {
    static let height: CGFloat = 28, radius: CGFloat = 7, zone: CGFloat = 28, glyph: CGFloat = 10, glyphStroke: CGFloat = 1.6
    static let fill = HocketColor(0x22252C), glyphColor = HocketColor(0xAAB0BA), captionColor = HocketColor(0x8A909A), zeroColor = HocketColor(0xF2F4F7)
    static let captionFont: CGFloat = 8, captionTracking: CGFloat = 0.08, valueFont: CGFloat = 10, captionGap: CGFloat = 4
}
struct EuclideousCardOctFrames: Equatable { var minusZone: CGRect, plusZone: CGRect, minusGlyph: CGRect, plusGlyph: CGRect, caption: CGRect, value: CGRect }
/// §6.3: − and + zones 28 × 28 at the ends with 10 × 10 glyphs; between them "OCT" and the value (centred as a pair).
func euclideousCardOctFrames(oct: CGRect, valueChars: Int = 2) -> EuclideousCardOctFrames {
    typealias O = EuclideousCardOctMetrics
    let minus = CGRect(x: oct.minX, y: oct.minY, width: O.zone, height: oct.height), plus = CGRect(x: oct.maxX - O.zone, y: oct.minY, width: O.zone, height: oct.height)
    let capW = EuclideousCardLabelMetrics.textWidth(3, size: O.captionFont, tracking: O.captionTracking)
    let valW = CGFloat(valueChars) * O.valueFont * EuclideousCardLabelMetrics.monoAdvance
    let startX = oct.midX - (capW + O.captionGap + valW) / 2
    return EuclideousCardOctFrames(minusZone: minus, plusZone: plus,
                                   minusGlyph: CGRect(x: minus.midX - O.glyph / 2, y: oct.midY - O.glyph / 2, width: O.glyph, height: O.glyph),
                                   plusGlyph: CGRect(x: plus.midX - O.glyph / 2, y: oct.midY - O.glyph / 2, width: O.glyph, height: O.glyph),
                                   caption: CGRect(x: startX, y: oct.minY, width: capW, height: oct.height),
                                   value: CGRect(x: startX + capW + O.captionGap, y: oct.minY, width: valW, height: oct.height))
}
/// "+1", "0", "−1" (U+2212); the value is #F2F4F7 at 0 and the lane's colour otherwise.
func euclideousCardOctValueText(_ v: Int) -> String { euclideousMixOctaveText(v) }
func euclideousCardOctValueIsLaneColour(_ v: Int) -> Bool { v != 0 }

// MARK: - §7 the jacks

/// A colour mix in sRGB 8-bit space: `amount` of `b` into `a` (alpha mixed the same way).
func euclideousCardMix(_ a: HocketColor, toward b: HocketColor, _ amount: Double) -> HocketColor {
    let t = max(0, min(1, amount))
    func ch(_ shift: UInt32) -> UInt32 {
        let x = Double((a.hex >> shift) & 0xFF), y = Double((b.hex >> shift) & 0xFF)
        return UInt32((x + (y - x) * t).rounded())
    }
    return HocketColor((ch(16) << 16) | (ch(8) << 8) | ch(0), a.alpha + (b.alpha - a.alpha) * t)
}

enum EuclideousJackMetrics {
    static let ringWidth: CGFloat = 1.5, socketRadius: CGFloat = 10.5, plugRadius: CGFloat = 8.5, capRadius: CGFloat = 3
    static let notch = CGSize(width: 2.5, height: 2.5), notchRadius: CGFloat = 0.5, pinSize: CGFloat = 2.3
    /// The five pins' centres in the 24 pt socket box (§7.3).
    static let pins: [CGPoint] = [CGPoint(x: 6.4, y: 10.4), CGPoint(x: 17.6, y: 10.4), CGPoint(x: 8, y: 15.2), CGPoint(x: 16, y: 15.2), CGPoint(x: 12, y: 17.2)]
    static let socketDisc = HocketColor(0x0B0C0E), notchColor = HocketColor(0x3A3E47), pinColor = HocketColor(0x4A4E57), cap = HocketColor(0x15161A)
    static let cellBase = HocketColor(0x101114), stripBorder = HocketColor(0x262930), unplugRing = HocketColor(0x3A3E47)
    static let letterOn = HocketColor(0xF2F4F7), letterOff = HocketColor(0x6E727B), lightOff = HocketColor(0x2A2D34)
    static let cellMixPlugged = 0.12, cellMixActive = 0.28, lightAlphaPlugged = 0.30, plugAlphaPartOff = 0.45
    static let decay: Double = 0.220
    static let glowRadius: CGFloat = 10, glowAlpha = 0.90
    static let seamGlowRadius: CGFloat = 6, seamGlowAlpha = 0.80, seamAlphaAudible = 0.35
    static let seamOff = HocketColor(0x262930)
}
struct EuclideousJackLook: Equatable {
    var ring: HocketColor
    var plug: HocketColor?               // the disc of r 8.5 over the pins (nil: unplugged)
    var plugCap: HocketColor?            // the r 3 cap
    var letter: HocketColor
    var cellFill: HocketColor?           // nil: unfilled
    var light: HocketColor
}
/// §7.3 (a pure function of the lane's colour index, plugged and the part being on).
///  - plugged, part on: ring lane100; plug lane100; cap #15161A; letter #F2F4F7; cell #101114 mixed 12 % toward lane100; light lane100 at 30 %
///  - plugged, part off: as above but the plug at 45 %, the cell unfilled, the light #2A2D34
///  - unplugged: ring #3A3E47, no plug, letter #6E727B, cell unfilled, light #2A2D34
func euclideousJackLook(lane: Int, plugged: Bool, partOn: Bool) -> EuclideousJackLook {
    typealias J = EuclideousJackMetrics
    let lane100 = HocketPalette.lane100(lane)
    guard plugged else { return EuclideousJackLook(ring: J.unplugRing, plug: nil, plugCap: nil, letter: J.letterOff, cellFill: nil, light: J.lightOff) }
    if partOn {
        return EuclideousJackLook(ring: lane100, plug: lane100, plugCap: J.cap, letter: J.letterOn, cellFill: euclideousCardMix(J.cellBase, toward: lane100, J.cellMixPlugged),
                                  light: HocketColor(lane100.hex, J.lightAlphaPlugged))
    }
    return EuclideousJackLook(ring: lane100, plug: HocketColor(lane100.hex, J.plugAlphaPartOff), plugCap: J.cap, letter: J.letterOn, cellFill: nil, light: J.lightOff)
}
/// §7.5: a note-on through this output: the light goes to lane100 with a 10 pt glow at 90 % and the cell's fill to 28 % toward lane100; both fall back to the plugged look linearly over 220 ms. `amount` is 1 at the note-on, 0 from 220 ms.
struct EuclideousJackActivity: Equatable {
    var amount: Double
    var glowRadius: CGFloat
    var glowAlpha: Double
    var cellMix: Double              // the fill's mix toward lane100: 0.12 (plugged) … 0.28 (note-on)
    var lightMix: Double             // the light's mix from its plugged colour toward lane100 at full alpha
}
func euclideousJackActivity(sinceNoteOn t: Double) -> EuclideousJackActivity {
    typealias J = EuclideousJackMetrics
    let a = t < 0 ? 0 : max(0, min(1, 1 - t / J.decay))
    return EuclideousJackActivity(amount: a, glowRadius: J.glowRadius * CGFloat(a), glowAlpha: J.glowAlpha * a, cellMix: J.cellMixPlugged + (J.cellMixActive - J.cellMixPlugged) * a, lightMix: a)
}
/// §7.6: the seam — lane100 at 35 % while the part is audible, else #262930; on a note-on lane100 at full with a 6 pt glow at 80 %, falling back over 220 ms.
struct EuclideousSeamLook: Equatable { var colour: HocketColor; var glowRadius: CGFloat; var glowAlpha: Double }
func euclideousSeamLook(lane: Int, audible: Bool, sinceNoteOn t: Double) -> EuclideousSeamLook {
    typealias J = EuclideousJackMetrics
    let lane100 = HocketPalette.lane100(lane)
    let a = t < 0 ? 0 : max(0, min(1, 1 - t / J.decay))
    let base = audible ? HocketColor(lane100.hex, J.seamAlphaAudible) : J.seamOff
    return EuclideousSeamLook(colour: euclideousCardMix(base, toward: lane100, a), glowRadius: J.seamGlowRadius * CGFloat(a), glowAlpha: J.seamGlowAlpha * a)
}
/// §7.4: a tap toggles this output's bit in the part's mask (bit n = output A + n); the new mask.
func euclideousJackToggle(mask: UInt8, output: Int) -> UInt8 { guard (0..<4).contains(output) else { return mask & 0x0F }; return (mask ^ (UInt8(1) << UInt8(output))) & 0x0F }
func euclideousJackIsPlugged(mask: UInt8, output: Int) -> Bool { (0..<4).contains(output) && mask & (UInt8(1) << UInt8(output)) != 0 }
let euclideousJackLetters = ["A", "B", "C", "D"]

// MARK: - §5.3 the roll

enum EuclideousRollMetrics {
    static let windowBars = 2
    static let minSpan = 12                                    // semitones
    static let shrinkSeconds: Double = 0.300
    static let borderWidth: CGFloat = 1, topRadius: CGFloat = 8
    static let border = HocketColor(0x262930), ground = HocketColor(0x131519), groundMix = 0.07
    static let blackKeyRow = HocketColor(0x000000, 0.28)
    static let beatLineAlpha = 0.04, barLineAlpha = 0.09
    static let noteMinHeight: CGFloat = 2.5, noteRadius: CGFloat = 2, silentBorder: CGFloat = 1.5, silentAlpha = 0.55
    static let playheadWidth: CGFloat = 2, playheadAlphaAudible = 0.55, playheadIdle = HocketColor(0xDFE3EA, 0.25)
    static let blackKeys: Set<Int> = [1, 3, 6, 8, 10]
}
/// A pitch span in semitones, inclusive: `lo…hi`.
struct EuclideousRollSpan: Equatable {
    var lo: Double, hi: Double
    var rows: Double { hi - lo + 1 }
}
/// §5.3 / test 9: the span a set of pitches asks for. Their own extent plus one semitone above and below, at least 12 semitones — a set that fits inside 12 gives a 12-semitone span CENTRED on it (the extra row, if the slack is odd,
/// goes on top). No notes ⇒ 12 semitones centred on middle C (60).
func euclideousRollTargetSpan(pitches: [Int]) -> EuclideousRollSpan {
    typealias R = EuclideousRollMetrics
    guard let mn = pitches.min(), let mx = pitches.max() else { return EuclideousRollSpan(lo: 60 - 6, hi: 60 - 6 + Double(R.minSpan) - 1) }
    let own = mx - mn + 3                                      // the notes plus a semitone each side
    if own >= R.minSpan { return EuclideousRollSpan(lo: Double(mn - 1), hi: Double(mx + 1)) }
    let slack = R.minSpan - (mx - mn + 1)                      // rows left over for the two sides
    let below = slack / 2
    let lo = mn - below
    return EuclideousRollSpan(lo: Double(lo), hi: Double(lo + R.minSpan - 1))
}
/// §5.3: the span DRAWN, from the one drawn last and the target: it grows at once to take in a note outside it, and shrinks over 300 ms after the notes have left (`shrinkElapsed` = seconds since the target first became
/// narrower than the drawn span; eased out linearly — the span moves proportionally from the drawn span to the target).
func euclideousRollDisplaySpan(target: EuclideousRollSpan, drawn: EuclideousRollSpan, shrinkElapsed: Double) -> EuclideousRollSpan {
    let p = max(0, min(1, shrinkElapsed / EuclideousRollMetrics.shrinkSeconds))
    func lo() -> Double { target.lo < drawn.lo ? target.lo : drawn.lo + (target.lo - drawn.lo) * p }
    func hi() -> Double { target.hi > drawn.hi ? target.hi : drawn.hi + (target.hi - drawn.hi) * p }
    return EuclideousRollSpan(lo: lo(), hi: hi())
}
struct EuclideousRollRow: Equatable { var pitch: Int; var y: CGFloat; var height: CGFloat; var isBlackKey: Bool }
/// §5.3: equal pitch rows spanning `span` in `height`, the highest pitch on top; black-key rows (C♯ D♯ F♯ G♯ A♯) are darkened by the view (rgba(0,0,0,0.28)).
func euclideousRollRows(span: EuclideousRollSpan, top: CGFloat, height: CGFloat) -> [EuclideousRollRow] {
    let lo = Int(span.lo.rounded(.down)), hi = Int(span.hi.rounded(.up))
    let n = max(1, hi - lo + 1)
    let h = height / CGFloat(n)
    return (lo...hi).reversed().enumerated().map { i, p in
        EuclideousRollRow(pitch: p, y: top + CGFloat(i) * h, height: h, isBlackKey: EuclideousRollMetrics.blackKeys.contains(((p % 12) + 12) % 12))
    }
}
/// §5.1 the scroll mapping (documented choice): the window is 2 bars of the page clock ending NOW, newest at the RIGHT edge, scrolling left as the clock advances: x(beat) = right − (nowBeat − beat) ÷ windowBeats × width.
func euclideousRollX(beat: Double, nowBeat: Double, beatsPerBar: Double, left: CGFloat, width: CGFloat) -> CGFloat {
    let window = Double(EuclideousRollMetrics.windowBars) * max(1, beatsPerBar)
    return left + width - CGFloat((nowBeat - beat) / window) * width
}
struct EuclideousRollGridLine: Equatable { var x: CGFloat; var isBar: Bool; var alpha: Double }
/// §5.3 beat lines, 1 pt: rgba(255,255,255,0.04) on beats, 0.09 on bars. Whole beats inside the window; beat 0 and every `beatsPerBar` after it are bar lines.
func euclideousRollGrid(nowBeat: Double, beatsPerBar: Double, left: CGFloat, width: CGFloat) -> [EuclideousRollGridLine] {
    let bpb = max(1, beatsPerBar), window = Double(EuclideousRollMetrics.windowBars) * bpb
    let first = Int((nowBeat - window).rounded(.up)), last = Int(nowBeat.rounded(.down))
    guard first <= last else { return [] }
    return (first...last).map { b in
        let bar = Double(b).truncatingRemainder(dividingBy: bpb) == 0
        return EuclideousRollGridLine(x: euclideousRollX(beat: Double(b), nowBeat: nowBeat, beatsPerBar: bpb, left: left, width: width), isBar: bar,
                                      alpha: bar ? EuclideousRollMetrics.barLineAlpha : EuclideousRollMetrics.beatLineAlpha)
    }
}
/// A note's rectangle in the roll: from its note-on to its note-off (or the right edge while it sounds), the pitch row's height minus 1 and at least 2.5, centred in the row; clipped to the roll. nil when it is wholly outside.
func euclideousRollNoteRect(pitch: Int, onBeat: Double, offBeat: Double?, nowBeat: Double, beatsPerBar: Double, span: EuclideousRollSpan, roll: CGRect) -> CGRect? {
    let rows = euclideousRollRows(span: span, top: roll.minY, height: roll.height)
    guard let row = rows.first(where: { $0.pitch == pitch }) else { return nil }
    let x0 = max(roll.minX, euclideousRollX(beat: onBeat, nowBeat: nowBeat, beatsPerBar: beatsPerBar, left: roll.minX, width: roll.width))
    let x1 = offBeat.map { min(roll.maxX, euclideousRollX(beat: $0, nowBeat: nowBeat, beatsPerBar: beatsPerBar, left: roll.minX, width: roll.width)) } ?? roll.maxX
    guard x1 > x0 else { return nil }
    let h = max(EuclideousRollMetrics.noteMinHeight, row.height - 1)
    return CGRect(x: x0, y: row.y + (row.height - h) / 2, width: x1 - x0, height: h)
}
enum EuclideousRollNoteState: Equatable { case sounding, ended, silent }
struct EuclideousRollNoteLook: Equatable {
    var fill: HocketColor?            // lane100 at `alpha` (nil: hollow)
    var glowRadius: CGFloat, glowAlpha: Double
    var border: HocketColor?          // the silent note's 1.5 pt outline (lane100 at 55 %)
    var borderWidth: CGFloat
}
/// §5.3, with s = 0.4 + 0.6 × velocity ÷ 127: a SOUNDING note is lane100 at s with a glow of 4 + 8 × velocity ÷ 127 pt at 0.7 × s; an ENDED note is lane100 at 0.6 × s; a SILENT note (routed nowhere) is hollow: a 1.5 pt lane100 border at 55 %.
func euclideousRollNoteLook(lane: Int, velocity: Int, state: EuclideousRollNoteState) -> EuclideousRollNoteLook {
    typealias R = EuclideousRollMetrics
    let lane100 = HocketPalette.lane100(lane)
    let v = Double(max(1, min(127, velocity))) / 127
    let s = 0.4 + 0.6 * v
    switch state {
    case .sounding: return EuclideousRollNoteLook(fill: HocketColor(lane100.hex, s), glowRadius: CGFloat(4 + 8 * v), glowAlpha: 0.7 * s, border: nil, borderWidth: 0)
    case .ended: return EuclideousRollNoteLook(fill: HocketColor(lane100.hex, 0.6 * s), glowRadius: 0, glowAlpha: 0, border: nil, borderWidth: 0)
    case .silent: return EuclideousRollNoteLook(fill: nil, glowRadius: 0, glowAlpha: 0, border: HocketColor(lane100.hex, R.silentAlpha), borderWidth: R.silentBorder)
    }
}
/// The roll's ground: #131519 mixed 7 % toward lane100 while the lane is audible, the part is on and the lane has hits; plain otherwise.
func euclideousRollGround(lane: Int, laneAudible: Bool, partOn: Bool, laneHasHits: Bool) -> HocketColor {
    let live = laneAudible && partOn && laneHasHits
    return live ? euclideousCardMix(EuclideousRollMetrics.ground, toward: HocketPalette.lane100(lane), EuclideousRollMetrics.groundMix) : EuclideousRollMetrics.ground
}
/// The playhead at the right edge: 2 pt, lane100 at 55 % while the part is audible, else rgba(223,227,234,0.25).
func euclideousRollPlayhead(lane: Int, audible: Bool, roll: CGRect) -> (rect: CGRect, colour: HocketColor) {
    (CGRect(x: roll.maxX - EuclideousRollMetrics.playheadWidth, y: roll.minY, width: EuclideousRollMetrics.playheadWidth, height: roll.height),
     audible ? HocketColor(HocketPalette.lane100(lane).hex, EuclideousRollMetrics.playheadAlphaAudible) : EuclideousRollMetrics.playheadIdle)
}

// MARK: - §11 VoiceOver (U+2019 for apostrophes — none is needed in these strings)

enum EuclideousCardBackAX {
    static let switchGroup = "Card side", patternSegment = "Pattern", mixSegment = "Mix"
    static func segment(_ side: EuclideousCardSide) -> String { side == .pattern ? patternSegment : mixSegment }
    /// "Lane 1 mix" — one group per lane; the order inside is play, SOLO, the riff row, the notes row.
    static func group(lane: Int) -> String { "Lane \(lane + 1) mix" }
    /// The label's toggle: "Riff, on" / "Riff, off".
    static func partToggle(_ part: EuclideousCardPart, on: Bool) -> String { "\(part.spoken), \(on ? "on" : "off")" }
    /// The XY pad (adjustable): "Riff velocity 24, gate 38%". (The old MIX pad read "Lane 1 riff" + "gate 60 percent, velocity 104": the ferry's wording puts velocity first, spells the percent sign and prefixes the part.)
    static func xy(_ part: EuclideousCardPart, velocity: Int, gate: Double) -> String { "\(part.spoken) velocity \(velocity), gate \(euclideousMixGateValueText(gate: gate))" }
    /// OCT (adjustable): "Riff octave, 0" — the value spoken as the MIX stepper speaks it ("plus 1", "minus 2").
    static func oct(_ part: EuclideousCardPart, value: Int) -> String { "\(part.spoken) octave, \(euclideousMixOctaveSpoken(value))" }
    /// The roll, one static element: "Riff playing" / "Riff silent" (silent = routed to no output).
    static func roll(_ part: EuclideousCardPart, silent: Bool) -> String { "\(part.spoken) \(silent ? "silent" : "playing")" }
    /// A jack (a toggle): "Riff to output A, plugged in" / "Riff to output A, empty".
    static func jack(_ part: EuclideousCardPart, output: Int, plugged: Bool) -> String {
        "\(part.spoken) to output \(euclideousJackLetters[max(0, min(3, output))]), \(plugged ? "plugged in" : "empty")"
    }
    /// An invitation is a button named by its label in sentence case: "Turn on notes", "Add hits".
    static func invitation(_ kind: EuclideousCardInvitation) -> String {
        switch kind { case .turnOnRiff: return "Turn on riff"; case .turnOnNotes: return "Turn on notes"; case .addHits: return "Add hits" }
    }
}
