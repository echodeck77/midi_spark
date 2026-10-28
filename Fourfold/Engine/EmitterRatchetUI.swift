//  EmitterRatchetUI.swift — RATCH tab ferry (2026-10-28) §4–§8: the PURE side of the RATCH tab. Foundation only, so the test target compiles it and the views only paint what these functions return.
//  The tab shows four cards, one per output A–D: an on/off toggle, a 16-slot strip of the output's Euclid pattern, and five drag cells (STEPS · HITS · OFFSET · CHANCE · STRIKES). The numbers are the ferry's, measured from the
//  bottom-right panel's top-left corner at its landscape frame (410 × 303 in the ferry; the real panel is whatever `euclideousPageLayout` gives it — see `emitterRatchetLayout`, which scales the width and keeps every other number).

import Foundation
import CoreGraphics

// MARK: - the tab strip (§4.1)

/// The tab strip's widths: RATCH is a fixed 80; the other tabs share what is left equally, sp4 apart. (The old `euclideousSeqTabWidth` — an equal split — is kept for the callers and tests that still use it.)
func euclideousSeqTabWidths(tabs: [EuclideousSeqTab], contentWidth: CGFloat) -> [CGFloat] {
    guard !tabs.isEmpty else { return [] }
    let gaps = CGFloat(tabs.count - 1) * 4
    let fixed = tabs.filter { $0 == .ratch }.count
    let ratchW: CGFloat = 80
    let others = tabs.count - fixed
    let rest = max(0, contentWidth - gaps - CGFloat(fixed) * ratchW)
    let each = others > 0 ? rest / CGFloat(others) : 0
    return tabs.map { $0 == .ratch ? ratchW : each }
}

// MARK: - the layout (§4.2–§4.8)

enum EmitterRatchetMetrics {
    /// Where the first card starts, in the TAB BODY's coordinates: the ferry's panel y 35 less the 32 pt the panel spends on its padding, tab row and gap above the body (the body starts at panel y 32 — the same 3 pt "source wins"
    /// difference FX and LANES carry).
    static let top: CGFloat = 3
    static let gap: CGFloat = 6
    static let landscapeCardHeight: CGFloat = 60
    static let minCardHeight: CGFloat = 52
    static let padVertical: CGFloat = 4, padRight: CGFloat = 8
    static let toggleWidth: CGFloat = 44, toggleGap: CGFloat = 6
    static let stripHeight: CGFloat = 20, stripGap: CGFloat = 4
    static let minReadoutHeight: CGFloat = 24
    static let slotCount = 16, slotGap: CGFloat = 2, slotRadius: CGFloat = 3
    static let cardRadius: CGFloat = 10
    static let barWidth: CGFloat = 2, barGap: CGFloat = 1, barRadius: CGFloat = 1
    static let barHeights: [CGFloat] = [14, 12, 10, 8]
    static let restDot: CGFloat = 2
    static let cellLabelTop: CGFloat = 7, cellLabelGap: CGFloat = 4
    static let progressHeight: CGFloat = 2, progressBottom: CGFloat = 3, progressInset: CGFloat = 8, progressMinShare = 0.06
    static let cellPressedRadius: CGFloat = 6
    static let discSize: CGFloat = 28
}

struct EmitterRatchetLayout: Equatable {
    /// The four cards in the tab body's coordinates.
    var cards: [CGRect]
    /// Everything below is CARD-LOCAL (origin = the card's top-left corner), the same for all four cards.
    var toggle: CGRect              // the 44 × inner-height touch target at the card's left edge (the disc is centred in it)
    var strip: CGRect               // the 16-slot strip, 20 tall
    var slots: [CGRect]             // 16 equal slots
    var cells: [CGRect]             // the five readout cells
    var cardHeight: CGFloat
    /// §4.8: a card under 52 pt — the frame is reported (and listed in the page's floors) rather than shrunk or left empty.
    var belowFloor: Bool { cardHeight < EmitterRatchetMetrics.minCardHeight - 0.01 }
}

/// §4.2–§4.8. `bodySize` is the tab body (the panel less its padding, tab row and gap). Landscape: cards 60 tall, 6 apart, from y 3. Portrait: the four cards share the height equally (6 apart, 35 above in panel terms and the panel's
/// own 8 below), the readout row taking whatever the 20 pt strip leaves (never under 24). A landscape card that cannot be 60 shares the height the same way.
func emitterRatchetLayout(bodySize: CGSize, portrait: Bool) -> EmitterRatchetLayout {
    typealias M = EmitterRatchetMetrics
    let w = max(0, bodySize.width)
    let shared = (bodySize.height - M.top - 3 * M.gap) / 4
    let h = max(0, portrait ? shared : min(M.landscapeCardHeight, shared))
    let cards = (0..<4).map { CGRect(x: 0, y: M.top + CGFloat($0) * (h + M.gap), width: w, height: h) }
    let innerH = max(0, h - 2 * M.padVertical)
    let colX = M.toggleWidth + M.toggleGap
    let colW = max(0, w - M.padRight - colX)
    let toggle = CGRect(x: 0, y: M.padVertical, width: M.toggleWidth, height: innerH)
    let strip = CGRect(x: colX, y: M.padVertical, width: colW, height: M.stripHeight)
    let slotW = max(0, (colW - CGFloat(M.slotCount - 1) * M.slotGap) / CGFloat(M.slotCount))
    let slots = (0..<M.slotCount).map { CGRect(x: colX + CGFloat($0) * (slotW + M.slotGap), y: M.padVertical, width: slotW, height: M.stripHeight) }
    let readoutY = M.padVertical + M.stripHeight + M.stripGap
    let readoutH = max(M.minReadoutHeight, innerH - M.stripHeight - M.stripGap)
    let cellW = colW / 5
    let cells = (0..<5).map { CGRect(x: colX + CGFloat($0) * cellW, y: readoutY, width: cellW, height: readoutH) }
    return EmitterRatchetLayout(cards: cards, toggle: toggle, strip: strip, slots: slots, cells: cells, cardHeight: h)
}

/// §4.5: the strike bars of a hit slot — `strikes` bars, centred in the slot, 2 wide, 1 apart, 14 / 12 / 10 / 8 tall in strike order.
func emitterRatchetBarRects(in slot: CGRect, strikes: Int) -> [CGRect] {
    typealias M = EmitterRatchetMetrics
    let n = max(0, min(M.barHeights.count, strikes))
    guard n > 0 else { return [] }
    let total = CGFloat(n) * M.barWidth + CGFloat(n - 1) * M.barGap
    let x0 = slot.midX - total / 2
    return (0..<n).map { CGRect(x: x0 + CGFloat($0) * (M.barWidth + M.barGap), y: slot.midY - M.barHeights[$0] / 2, width: M.barWidth, height: M.barHeights[$0]) }
}
/// §4.5: the 2 × 2 dot of a rest slot, centred.
func emitterRatchetRestDot(in slot: CGRect) -> CGRect {
    CGRect(x: slot.midX - EmitterRatchetMetrics.restDot / 2, y: slot.midY - EmitterRatchetMetrics.restDot / 2, width: EmitterRatchetMetrics.restDot, height: EmitterRatchetMetrics.restDot)
}
/// §4.5: the bars' alpha — 0.5 at CHANCE 0, 1.0 at CHANCE 100.
func emitterRatchetBarAlpha(chance: Int) -> Double { 0.5 + 0.5 * Double(max(0, min(100, chance))) / 100 }

// MARK: - the readout cells (§4.6, §4.7, §6.2)

/// §4.7: STEPS "8"; HITS "3"; OFFSET "0", else "+" and the value; CHANCE the value and "%"; STRIKES "×" and the value.
func emitterRatchetValueText(_ f: EmitterRatchetField, _ r: EmitterRatchet) -> String {
    switch f {
    case .steps: return "\(r.steps)"
    case .hits: return "\(r.hits)"
    case .offset: return r.offset == 0 ? "0" : "+\(r.offset)"
    case .chance: return "\(r.chance)%"
    case .strikes: return "\u{00D7}\(r.strikes)"
    }
}
/// §4.6: the progress bar's fill — the value's share of its range, (v − min) ÷ (max − min), never under 6 % of the track.
func emitterRatchetBarShare(_ f: EmitterRatchetField, _ r: EmitterRatchet) -> Double {
    let range = f.range(in: r)
    let span = Double(range.upperBound - range.lowerBound)
    let share = span > 0 ? Double(f.value(of: r) - range.lowerBound) / span : 1
    return max(EmitterRatchetMetrics.progressMinShare, min(1, share))
}
/// §6.2: a drag starts once the touch has moved 6 pt …
let emitterRatchetDragActivation: CGFloat = 6
/// … then raises the value by one step per this much upward travel (measured from where the touch went down): STEPS, HITS and OFFSET one per 10 pt, CHANCE 5 per 3 pt, STRIKES one per 18 pt.
func emitterRatchetPointsPerStep(_ f: EmitterRatchetField) -> CGFloat {
    switch f { case .steps, .hits, .offset: return 10; case .chance: return 3; case .strikes: return 18 }
}
/// §6.2: the value a drag has reached — `start` plus a whole number of steps for the travel so far (up positive), clamped at the ends by `setting` (never wrapped).
func emitterRatchetDragValue(_ f: EmitterRatchetField, start r: EmitterRatchet, travelUp: CGFloat) -> EmitterRatchet {
    let steps = Int((travelUp / emitterRatchetPointsPerStep(f)).rounded(.towardZero))
    return f.setting(f.value(of: r) + steps * f.step, in: r)
}

// MARK: - VoiceOver (§8)

let emitterRatchetLetters = ["A", "B", "C", "D"]
func emitterRatchetTabAccessibilityLabel() -> String { "Ratchet" }
func emitterRatchetToggleLabel(output x: Int) -> String { "Ratchet on emitter \(emitterRatchetLetters[max(0, min(3, x))])" }
func emitterRatchetToggleValue(on: Bool) -> String { on ? "on" : "off" }
/// "Emitter A pattern, 3 of 8, offset 0, 3 strikes" — `counts` is "hits" or "steps" in a dev build (as FX COUNTS reads), nil in release. One static element: it is not announced as it plays.
func emitterRatchetStripLabel(output x: Int, _ r: EmitterRatchet, counts: String?) -> String {
    "Emitter \(emitterRatchetLetters[max(0, min(3, x))]) pattern, \(r.hits) of \(r.steps)\(counts.map { " \($0)" } ?? ""), offset \(r.offset), \(r.strikes) strikes"
}
/// "Emitter A steps 8" · "hits 3" · "offset plus 2" (0 reads "0") · "chance 75 percent" · "strikes 3".
func emitterRatchetCellLabel(output x: Int, _ f: EmitterRatchetField, _ r: EmitterRatchet) -> String {
    let who = "Emitter \(emitterRatchetLetters[max(0, min(3, x))])"
    switch f {
    case .steps: return "\(who) steps \(r.steps)"
    case .hits: return "\(who) hits \(r.hits)"
    case .offset: return r.offset == 0 ? "\(who) offset 0" : "\(who) offset plus \(r.offset)"
    case .chance: return "\(who) chance \(r.chance) percent"
    case .strikes: return "\(who) strikes \(r.strikes)"
    }
}

// MARK: - the flare (§5.3, §5.4)

/// What an output's toggle and strip flash for its most recent RATCHED or MISSED hit: the lane that struck it, which of the two it was, and the PULSE flash envelope `f` (0…1, τ 0.16 s, gone after 1.5 s — the same timing the
/// emitter circles' sounding flare used). With several lanes striking at once the LOWEST-numbered lane's colour is used (§5.3).
struct EmitterRatchetFlare: Equatable {
    var lane: Int
    var ratcheted: Bool      // RATCHED ⇒ lane100 bars, a thickened ring and a wash; MISSED ⇒ lane100 bars at 35 % and no ring flare (§5.4)
    var f: Double
}
func emitterRatchetFlare(output x: Int, strikes: [[EuclideousPulseStrike]], now: Double, scale: Double) -> EmitterRatchetFlare? {
    guard x >= 0, x < 4, scale > 0 else { return nil }
    let bit = UInt8(1) << UInt8(x)
    var best: (lane: Int, at: Double, ratcheted: Bool, vel: Int)? = nil
    for lane in 0..<min(4, strikes.count) {
        // the lane's newest strike that has happened and that this output ratcheted or missed
        guard let s = strikes[lane].last(where: { $0.onsetAt <= now && ($0.emitMasks & 0x0F & bit != 0 || ($0.emitMasks >> 4) & bit != 0) }) else { continue }
        let ratcheted = s.emitMasks & 0x0F & bit != 0
        let vel = Int(max(s.riffVel, s.notesVel))
        // a later strike wins; strikes within 5 ms of each other are the same moment — the lower lane keeps it
        if best == nil || s.onsetAt > best!.at + 0.005 { best = (lane, s.onsetAt, ratcheted, vel) }
    }
    guard let b = best else { return nil }
    let env = euclideousPulseEnvelopes(velocity: b.vel, seconds: now - b.at, scale: scale)
    return env.f > 0 ? EmitterRatchetFlare(lane: b.lane, ratcheted: b.ratcheted, f: env.f) : nil
}
