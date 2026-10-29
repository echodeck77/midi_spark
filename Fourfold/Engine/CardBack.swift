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
    /// §4.2: the BACK's own fill and a 1 pt lane100 border at 28 % — on the CARD (CARD BACKS v2 puts them there; the first build drew them round the roll panel instead and left the card in the front's #1B1D23).
    static let fillColor = HocketColor(0x17191E), borderAlpha = 0.28, borderWidth: CGFloat = 1, cardRadius: CGFloat = 12
    // inside a row (§4.4, CARD BACKS v2): [VEL/GATE pad][sp4][PITCH pad][sp8][roll panel]; the pads keep 72 pt each until the roll panel would drop under 176, then give way down to their 44 pt floor
    static let padWidth: CGFloat = 72, padGap: CGFloat = 4, columnGap: CGFloat = 8
    static let rollPanelPreferredMin: CGFloat = 176
    static let jackStripHeight: CGFloat = 32, jackTargetHeight: CGFloat = 44
    static let jackCount = 4
    // floors (§4.5)
    static let floorPadWidth: CGFloat = 44, floorPadHeight: CGFloat = 60, floorRoll: CGFloat = 40, floorJackTargetWidth: CGFloat = 44
    // the socket (§7.2): a 22 pt box centred in the cell's drawn area
    static let socketSize: CGFloat = 22
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
    /// The VEL/GATE pad and the PITCH pad: each the row's full height.
    var velGate: CGRect, pitch: CGRect
    var rollPanel: CGRect, roll: CGRect, jackStrip: CGRect, seam: CGRect
    /// The four cells as DRAWN (a quarter of the panel wide, 32 tall), the touch targets (the same width, 44 tall, bottom-aligned with the row — 12 pt reaching up over the roll) and the 22 pt sockets centred in the cells.
    var jackCells: [CGRect], jackTargets: [CGRect], jackSockets: [CGRect]
}
struct EuclideousCardBackLayout: Equatable {
    var card: CGSize
    /// The body's top in card coordinates (62): the first row starts here.
    var bodyTop: CGFloat
    var riff: EuclideousCardBackPartFrames, notes: EuclideousCardBackPartFrames
    var rowHeight: CGFloat
    /// Every floor under its minimum at this card size (drawn at the formula's values and listed, never shrunk — the page's own rule).
    var floors: [EuclideousCardBackFloor]
    func part(_ p: EuclideousCardPart) -> EuclideousCardBackPartFrames { p == .riff ? riff : notes }
}
/// The width each pad gets in a content box `w` wide: 72, or less when the roll panel (what is left after the two pads and their gaps) would fall under 176 — never under the 44 pt floor.
func euclideousCardBackPadWidth(contentWidth w: CGFloat) -> CGFloat {
    typealias M = EuclideousCardBackMetrics
    let fixed = M.padGap + M.columnGap
    return max(M.floorPadWidth, min(M.padWidth, (w - fixed - M.rollPanelPreferredMin) / 2))
}
/// §4.3–4.5 and §7.2: every frame on the back from the card's size. The content box is the card inset by 10; the body starts at `bodyTop` (62: sp8 below the top row — TAB STRIP ferry 2026-10-29: the back's own "MIX" strip is gone, the
/// page's strip chooses the tab) and the two rows split what is left, sp8 apart: rowH = (contentBottom − bodyTop − sp8) ÷ 2. In a row: the VEL/GATE pad, sp4, the PITCH pad, sp8, then the roll panel — the roll (rowH − 32 tall) on
/// top of the 32-tall jack strip, whose four 44-tall touch targets reach 12 pt up over the roll's bottom edge.
func euclideousCardBackLayout(card: CGSize, bodyTop: CGFloat = EuclideousLaneCardMetrics.bodyTop) -> EuclideousCardBackLayout {
    typealias M = EuclideousCardBackMetrics
    let x0 = M.inset, w = max(1, card.width - 2 * M.inset)
    let bottom = card.height - M.inset
    let rowH = (bottom - bodyTop - M.sp8) / 2
    let padW = euclideousCardBackPadWidth(contentWidth: w)
    func part(rowTop: CGFloat) -> EuclideousCardBackPartFrames {
        let row = CGRect(x: x0, y: rowTop, width: w, height: rowH)
        let velGate = CGRect(x: x0, y: rowTop, width: padW, height: rowH)
        let pitch = CGRect(x: velGate.maxX + M.padGap, y: rowTop, width: padW, height: rowH)
        let panelX = pitch.maxX + M.columnGap
        let panel = CGRect(x: panelX, y: rowTop, width: max(1, x0 + w - panelX), height: rowH)
        let roll = CGRect(x: panelX, y: rowTop, width: panel.width, height: rowH - M.jackStripHeight)
        let jackStrip = CGRect(x: panelX, y: roll.maxY, width: panel.width, height: M.jackStripHeight)
        let seam = CGRect(x: panelX, y: jackStrip.minY, width: panel.width, height: M.seamHeight)
        let cellW = panel.width / CGFloat(M.jackCount)
        var cells: [CGRect] = [], targets: [CGRect] = [], sockets: [CGRect] = []
        for i in 0..<M.jackCount {
            let cell = CGRect(x: panelX + CGFloat(i) * cellW, y: jackStrip.minY, width: cellW, height: M.jackStripHeight)
            cells.append(cell)
            targets.append(CGRect(x: cell.minX, y: rowTop + rowH - M.jackTargetHeight, width: cellW, height: M.jackTargetHeight))
            sockets.append(CGRect(x: cell.midX - M.socketSize / 2, y: cell.midY - M.socketSize / 2, width: M.socketSize, height: M.socketSize))
        }
        return EuclideousCardBackPartFrames(row: row, velGate: velGate, pitch: pitch, rollPanel: panel, roll: roll, jackStrip: jackStrip, seam: seam,
                                            jackCells: cells, jackTargets: targets, jackSockets: sockets)
    }
    let riff = part(rowTop: bodyTop)
    let notes = part(rowTop: riff.row.maxY + M.sp8)
    var floors: [EuclideousCardBackFloor] = []
    if riff.velGate.width < M.floorPadWidth { floors.append(EuclideousCardBackFloor(name: "pad width", value: riff.velGate.width, floor: M.floorPadWidth)) }
    if riff.velGate.height < M.floorPadHeight { floors.append(EuclideousCardBackFloor(name: "pad height", value: riff.velGate.height, floor: M.floorPadHeight)) }
    if riff.roll.height < M.floorRoll { floors.append(EuclideousCardBackFloor(name: "roll height", value: riff.roll.height, floor: M.floorRoll)) }
    let target = riff.jackTargets[0].width
    if target < M.floorJackTargetWidth { floors.append(EuclideousCardBackFloor(name: "jack target width", value: target, floor: M.floorJackTargetWidth)) }
    // the roll must be wide enough for the label pill AND the invitation side by side (5 + label + gap + invitation + 5), else the invitation overlaps the label
    let rollNeeds = euclideousCardInvitationRollWidthFloor()
    if riff.roll.width < rollNeeds { floors.append(EuclideousCardBackFloor(name: "roll width for the label and its invitation", value: riff.roll.width, floor: rollNeeds)) }
    return EuclideousCardBackLayout(card: card, bodyTop: bodyTop, riff: riff, notes: notes, rowHeight: rowH, floors: floors)
}

// MARK: - §5.4 the label pill, §5.6 the invitations

enum EuclideousCardLabelMetrics {
    static let inset: CGFloat = 5, height: CGFloat = 20, radius: CGFloat = 5, padX: CGFloat = 7, glyphGap: CGFloat = 6
    static let font: CGFloat = 9, tracking: CGFloat = 0.12, targetHeight: CGFloat = 32, targetMinWidth: CGFloat = 44
    static let fill = HocketColor(0x131519, 0.82), offAlpha = 0.55
    static let monoAdvance: CGFloat = 0.66      // SF Mono Heavy measures ≈ 0.66 em an advance on device (0.6 clipped "TURN ON NOTES" to "TURN ON NOT…")
    static func textWidth(_ chars: Int, size: CGFloat, tracking em: CGFloat) -> CGFloat { CGFloat(chars) * size * (monoAdvance + em) }
}
struct EuclideousCardLabelFrames: Equatable {
    var pill: CGRect, target: CGRect, glyph: CGRect, text: CGRect
}
/// §5.4: top-left of the roll, 5 pt in: a pill 20 tall (radius 5, 7 pt side padding) holding the part's glyph, 6 pt, then the label (9 pt heavy, 0.12 em). CARD BACKS v2: its touch target is at least 44 wide and 32 tall, from the roll's top-left.
func euclideousCardLabelFrames(roll: CGRect, part: EuclideousCardPart) -> EuclideousCardLabelFrames {
    typealias L = EuclideousCardLabelMetrics
    let g = part.glyphSize
    let textW = L.textWidth(part.label.count, size: L.font, tracking: L.tracking)
    let pill = CGRect(x: roll.minX + L.inset, y: roll.minY + L.inset, width: L.padX + g.width + L.glyphGap + textW + L.padX, height: L.height)
    let glyph = CGRect(x: pill.minX + L.padX, y: pill.midY - g.height / 2, width: g.width, height: g.height)
    let text = CGRect(x: glyph.maxX + L.glyphGap, y: pill.minY, width: textW, height: L.height)
    return EuclideousCardLabelFrames(pill: pill, target: CGRect(x: roll.minX, y: roll.minY, width: max(L.targetMinWidth, pill.maxX - roll.minX), height: L.targetHeight), glyph: glyph, text: text)
}

/// The narrowest roll that holds the NOTES label pill (the wider of the two) and the invitation (ADD HITS) side by side without touching.
func euclideousCardInvitationRollWidthFloor() -> CGFloat {
    typealias L = EuclideousCardLabelMetrics
    typealias I = EuclideousCardInvitationMetrics
    let label = L.padX + EuclideousCardPart.notes.glyphSize.width + L.glyphGap + L.textWidth(EuclideousCardPart.notes.label.count, size: L.font, tracking: L.tracking) + L.padX
    let inv = I.padX + I.plus + I.plusGap + L.textWidth(EuclideousCardInvitation.addHits.label.count, size: I.font, tracking: I.tracking) + I.padX   // CARD BACKS v2: ADD HITS is the only invitation (the label is the switch)
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
/// §5.5 / §5.6 (CARD BACKS v2): there is no turn-on button — the label is the switch — so the roll offers exactly one thing: ADD HITS, while the part is ON and the lane's rhythm has no hits. (The two TURN ON cases of
/// `EuclideousCardInvitation` stay in the type, hidden: nothing returns them.)
func euclideousCardInvitation(part: EuclideousCardPart, partOn: Bool, laneHasHits: Bool) -> EuclideousCardInvitation? {
    partOn && !laneHasHits ? .addHits : nil
}

// MARK: - §6 the XY pad and OCT

/// The XY pad is the MIX pad's VEL / GATE control for a part: X = GATE, Y = VEL (up louder) — the same axes and ranges as `EuclideousMixPadGeometry`, minus its strips (the back's pad has none): the dot's travel is inset 7 at every
/// edge, gate % = round((x − 7) ÷ (w − 14) × 100) clamped 1…99, velocity = round((h − 7 − y) ÷ (h − 14) × 127) clamped 1…127.
enum EuclideousCardXYMetrics {
    static let inset: CGFloat = 7, dot: CGFloat = 11, dotRing: CGFloat = 2, radius: CGFloat = 8, textInset: CGFloat = 5
    static let well = HocketColor(0x131519), border = HocketColor(0x262930), text = HocketColor(0xDFE3EA)
    /// §6.2: "a 2 pt #131519 ring" — the well's own colour (the retired MIX pad's puck ring was #15161A; the first build of the back kept that one).
    static let dotRingColor = HocketColor(0x131519)
    static let fillAlpha = 0.22, crosshairAlpha = 0.60, crosshairWidth: CGFloat = 1, textFont: CGFloat = 8, textTracking: CGFloat = 0.06
}
/// Does `chars` characters of the pads' 8 pt heavy label face (0.06 em tracking) fit in a pad `padWidth` wide with the 5 pt text inset on both sides? (The pads shrink to 44 pt in small windows; a word that cannot fit is
/// shortened to its value rather than left to run over the neighbouring pad — §4.6 "truncate, never shrink".)
func euclideousCardPadTextFits(_ chars: Int, padWidth: CGFloat) -> Bool {
    EuclideousCardLabelMetrics.textWidth(chars, size: EuclideousCardXYMetrics.textFont, tracking: EuclideousCardXYMetrics.textTracking) <= padWidth - 2 * EuclideousCardXYMetrics.textInset + 1e-9
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
func euclideousCardXYTexts(gate: Double, velocity: Int, padWidth: CGFloat = .infinity) -> (vel: String, gate: String) {
    let word = "VEL \(velocity)"
    return (euclideousCardPadTextFits(word.count, padWidth: padWidth) ? word : "\(velocity)", euclideousMixGateValueText(gate: gate))
}

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

// MARK: - CARD BACKS v2 §6.3–6.8 the PITCH pad

/// The PITCH pad sets a part's OCTAVE (rows, the part's own OCT field, −2…+2) and its OUT-TRANSPOSE (columns, −7…+7 steps of the key's scale). Both snap: every detent is a value. Not the RIFF tab's TRANS (a rank shift) and never
/// written by it.
enum EuclideousCardPitchMetrics {
    static let octaveTop = 2, octaveBottom = -2, transposeMax = 7
    static let inset: CGFloat = 6, travelLoss: CGFloat = 14          // x = 6 + (t + 7) ÷ 14 × (w − 14), y = 6 + (top − o) ÷ (top − bottom) × (h − 14)
    static let radius: CGFloat = 8, dot: CGFloat = 11, dotRing: CGFloat = 2, textInset: CGFloat = 5
    static let detent: CGFloat = 2
    static let well = HocketColor(0x131519), border = HocketColor(0x262930), detentColor = HocketColor(0x2E3138), detentEdgeColor = HocketColor(0x4A4E57), homeLine = HocketColor(0x30333A)
    static let homeCrosshair = HocketColor(0x8A909A, 0.35), homeDot = HocketColor(0x8A909A), text = HocketColor(0xDFE3EA)
    static let fillAlpha = 0.22, crosshairAlpha = 0.60, lineWidth: CGFloat = 1
    static let textFont: CGFloat = 8, textTracking: CGFloat = 0.06
}
struct EuclideousCardPitchValue: Equatable {
    var octave: Int
    var transpose: Int
    static let home = EuclideousCardPitchValue(octave: 0, transpose: 0)
    var isHome: Bool { octave == 0 && transpose == 0 }
}
/// §6.4: detent (o, t)'s centre in `pad`.
func euclideousCardPitchDot(_ v: EuclideousCardPitchValue, in pad: CGRect) -> CGPoint {
    typealias P = EuclideousCardPitchMetrics
    let o = max(P.octaveBottom, min(P.octaveTop, v.octave)), t = max(-P.transposeMax, min(P.transposeMax, v.transpose))
    let tx = max(1, pad.width - P.travelLoss), ty = max(1, pad.height - P.travelLoss)
    return CGPoint(x: pad.minX + P.inset + CGFloat(t + P.transposeMax) / CGFloat(2 * P.transposeMax) * tx,
                   y: pad.minY + P.inset + CGFloat(P.octaveTop - o) / CGFloat(P.octaveTop - P.octaveBottom) * ty)
}
/// §6.3: the detent nearest the finger — a drag moves the dot to it, so every position is a value; clamped to the pad's edge detents.
func euclideousCardPitchValue(at p: CGPoint, in pad: CGRect) -> EuclideousCardPitchValue {
    typealias P = EuclideousCardPitchMetrics
    let tx = max(1, pad.width - P.travelLoss), ty = max(1, pad.height - P.travelLoss)
    let tf = ((p.x - pad.minX - P.inset) / tx * CGFloat(2 * P.transposeMax)).rounded() - CGFloat(P.transposeMax)
    let of = CGFloat(P.octaveTop) - ((p.y - pad.minY - P.inset) / ty * CGFloat(P.octaveTop - P.octaveBottom)).rounded()
    let t = Int(max(CGFloat(-P.transposeMax), min(CGFloat(P.transposeMax), tf.isFinite ? tf : 0)))
    let o = Int(max(CGFloat(P.octaveBottom), min(CGFloat(P.octaveTop), of.isFinite ? of : 0)))
    return EuclideousCardPitchValue(octave: o, transpose: t)
}
/// Every detent's centre: 5 octave rows × 15 transpose columns. `edge` marks the columns at t = 0 and ±7 (drawn in the brighter #4A4E57).
func euclideousCardPitchDetents(in pad: CGRect) -> [(point: CGPoint, edge: Bool)] {
    typealias P = EuclideousCardPitchMetrics
    var out: [(CGPoint, Bool)] = []
    for o in stride(from: P.octaveTop, through: P.octaveBottom, by: -1) {
        for t in -P.transposeMax...P.transposeMax { out.append((euclideousCardPitchDot(EuclideousCardPitchValue(octave: o, transpose: t), in: pad), t == 0 || abs(t) == P.transposeMax)) }
    }
    return out
}
/// §6.4: the rectangle spanning from the home point to the dot (lane100 at 22 %); nil at home.
func euclideousCardPitchRect(_ v: EuclideousCardPitchValue, in pad: CGRect) -> CGRect? {
    guard !v.isHome else { return nil }
    let d = euclideousCardPitchDot(v, in: pad), h = euclideousCardPitchDot(.home, in: pad)
    return CGRect(x: min(d.x, h.x), y: min(d.y, h.y), width: abs(d.x - h.x), height: abs(d.y - h.y))
}
/// §6.4: the home lines (1 pt #30333A) — horizontal through octave 0, vertical through transpose 0 — across the whole pad.
func euclideousCardPitchHomeLines(in pad: CGRect) -> (horizontal: CGRect, vertical: CGRect) {
    let h = euclideousCardPitchDot(.home, in: pad), w = EuclideousCardPitchMetrics.lineWidth
    return (CGRect(x: pad.minX, y: h.y - w / 2, width: pad.width, height: w), CGRect(x: h.x - w / 2, y: pad.minY, width: w, height: pad.height))
}
/// "OCT +1" top-left, "TRANS +2" bottom-right: U+2212 for minus, "0" at zero.
/// In a pad too narrow for the word and the value ("TRANS +7" needs 56 pt) only the value is drawn.
func euclideousCardPitchTexts(_ v: EuclideousCardPitchValue, padWidth: CGFloat = .infinity) -> (oct: String, trans: String) {
    let o = euclideousMixOctaveText(v.octave), t = euclideousMixOctaveText(v.transpose)
    let oct = "OCT \(o)", trans = "TRANS \(t)"
    return (euclideousCardPadTextFits(oct.count, padWidth: padWidth) ? oct : o, euclideousCardPadTextFits(trans.count, padWidth: padWidth) ? trans : t)
}
/// Gestures (§6.8) written as values: the octave one step up / down (VoiceOver swipe), the transpose one step, and the reset.
func euclideousCardPitchOctaveStep(_ v: EuclideousCardPitchValue, up: Bool) -> EuclideousCardPitchValue? {
    let n = v.octave + (up ? 1 : -1)
    return (EuclideousCardPitchMetrics.octaveBottom...EuclideousCardPitchMetrics.octaveTop).contains(n) ? EuclideousCardPitchValue(octave: n, transpose: v.transpose) : nil
}
func euclideousCardPitchTransposeStep(_ v: EuclideousCardPitchValue, up: Bool) -> EuclideousCardPitchValue? {
    let n = v.transpose + (up ? 1 : -1)
    return abs(n) <= EuclideousCardPitchMetrics.transposeMax ? EuclideousCardPitchValue(octave: v.octave, transpose: n) : nil
}
/// What the part reads as, and the one place a pitch value is written onto a lane. The octave goes straight into the part's own OCT field (`riffOctave`, or the notes layer's `octave` — NOT through `euclideousSetNotesOctave`, which also
/// switches the NOTES layer on: the pad is live on an OFF part and must not turn it on); the out-transpose into `riffOutTranspose` / `notesOutTranspose`, stored as nil at 0 so a pad put back home leaves the document as it was.
func euclideousCardPitchValue(of line: EuclidLine, notes: Bool) -> EuclideousCardPitchValue {
    EuclideousCardPitchValue(octave: euclideousMixOctave(of: line, notes: notes), transpose: notes ? line.notesOutTransposeResolved : line.riffOutTransposeResolved)
}
func euclideousCardPitchWrite(_ line: inout EuclidLine, notes: Bool, _ v: EuclideousCardPitchValue) {
    let o = max(EuclideousCardPitchMetrics.octaveBottom, min(EuclideousCardPitchMetrics.octaveTop, v.octave))
    let t = max(-EuclideousCardPitchMetrics.transposeMax, min(EuclideousCardPitchMetrics.transposeMax, v.transpose))
    if notes { line.octave = o; line.notesOutTranspose = t == 0 ? nil : t } else { line.riffOctave = o; line.riffOutTranspose = t == 0 ? nil : t }
}

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
    /// CARD BACKS v2 §7.2: a 22 pt box — a disc of r 10 in #0B0C0E with a 1.5 pt ring, a 2.4 × 2.4 key notch at 12 o'clock (#3A3E47, radius 0.5) and five 2.2 pt pins in #4A4E57. No other mark in the cell.
    static let ringWidth: CGFloat = 1.5, socketRadius: CGFloat = 10, plugRadius: CGFloat = 8
    static let notch = CGSize(width: 2.4, height: 2.4), notchRadius: CGFloat = 0.5, pinSize: CGFloat = 2.2
    /// The five pins' centres in the 22 pt socket box.
    static let pins: [CGPoint] = [CGPoint(x: 5.8, y: 9.6), CGPoint(x: 16.2, y: 9.6), CGPoint(x: 7.3, y: 14), CGPoint(x: 14.7, y: 14), CGPoint(x: 11, y: 15.9)]
    static let socketDisc = HocketColor(0x0B0C0E), notchColor = HocketColor(0x3A3E47), pinColor = HocketColor(0x4A4E57)
    static let cellBase = HocketColor(0x101114), stripBorder = HocketColor(0x262930), stripRadius: CGFloat = 8, unplugRing = HocketColor(0x3A3E47)
    static let letterInk = HocketColor(0x0D0F14), letterFont: CGFloat = 9
    static let plugAlphaPartOn = 0.75, plugAlphaPartOff = 0.40
    static let cellMixPlugged = 0.12, cellMixActive = 0.28
    static let decay: Double = 0.220
    static let plugFlashWhiteMix = 0.35, glowRadius: CGFloat = 5, glowAlpha = 0.95
    static let seamGlowRadius: CGFloat = 6, seamGlowAlpha = 0.80, seamAlphaAudible = 0.35
    static let seamOff = HocketColor(0x262930)
}
struct EuclideousJackLook: Equatable {
    var ring: HocketColor
    var plug: HocketColor?               // the disc of r 8 over the pins, carrying the letter (nil: unplugged — pins showing, no letter)
    var letter: HocketColor              // ink on the plug
    var cellFill: HocketColor?           // nil: unfilled
}
/// §7.3 (a pure function of the lane's colour index, plugged — this part's mask holds this output — and the part being on):
///  - plugged, part on: ring lane100; plug lane100 at 75 % carrying the output's letter in ink #0D0F14; the cell #101114 mixed 12 % toward lane100
///  - plugged, part off: ring lane100; plug lane100 at 40 %; the cell unfilled
///  - unplugged: ring #3A3E47, the pins showing, no plug, no letter; the cell unfilled
func euclideousJackLook(lane: Int, plugged: Bool, partOn: Bool) -> EuclideousJackLook {
    typealias J = EuclideousJackMetrics
    let lane100 = HocketPalette.lane100(lane)
    guard plugged else { return EuclideousJackLook(ring: J.unplugRing, plug: nil, letter: J.letterInk, cellFill: nil) }
    if partOn {
        return EuclideousJackLook(ring: lane100, plug: HocketColor(lane100.hex, J.plugAlphaPartOn), letter: J.letterInk, cellFill: euclideousCardMix(J.cellBase, toward: lane100, J.cellMixPlugged))
    }
    return EuclideousJackLook(ring: lane100, plug: HocketColor(lane100.hex, J.plugAlphaPartOff), letter: J.letterInk, cellFill: nil)
}
/// §7.5: a note-on through this output: the plug disc mixes 35 % toward white with a 5 pt lane100 glow at 95 %, and its cell's fill goes to 28 % toward lane100; both fall back to the plugged look linearly over 220 ms. `amount` is 1 at the note-on, 0 from 220 ms.
struct EuclideousJackActivity: Equatable {
    var amount: Double
    var glowRadius: CGFloat
    var glowAlpha: Double
    var cellMix: Double              // the fill's mix toward lane100: 0.12 (plugged) … 0.28 (note-on)
    var plugWhiteMix: Double         // the plug's mix toward #FFFFFF: 0 … 0.35
}
func euclideousJackActivity(sinceNoteOn t: Double) -> EuclideousJackActivity {
    typealias J = EuclideousJackMetrics
    let a = t < 0 ? 0 : max(0, min(1, 1 - t / J.decay))
    return EuclideousJackActivity(amount: a, glowRadius: J.glowRadius * CGFloat(a), glowAlpha: J.glowAlpha * a, cellMix: J.cellMixPlugged + (J.cellMixActive - J.cellMixPlugged) * a, plugWhiteMix: J.plugFlashWhiteMix * a)
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
    /// The PITCH pad (adjustable): label "Riff pitch", value "octave +1, transpose +2"; swipe up / down changes the octave by one; custom actions "Transpose up", "Transpose down" and "Reset pitch".
    static func pitch(_ part: EuclideousCardPart) -> String { "\(part.spoken) pitch" }
    static func pitchValue(_ v: EuclideousCardPitchValue) -> String { "octave \(euclideousMixOctaveText(v.octave)), transpose \(euclideousMixOctaveText(v.transpose))" }
    static let transposeUp = "Transpose up", transposeDown = "Transpose down", resetPitch = "Reset pitch"
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
