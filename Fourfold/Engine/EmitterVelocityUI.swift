//  EmitterVelocityUI.swift — VELOCITY tab (2026-11-03): the PURE side of the VELOCITY tab, the sibling of `EmitterRatchetUI.swift`. Foundation only, so the test target compiles it and the views only paint what these return.
//  The tab shows four cards, one per output A–D (the ratchet's design): an on/off toggle, a 16-slot strip of the output's Euclid pattern, and five drag cells (STEPS · HITS · OFFSET · HIT VEL · MISS VEL). HIT VEL / MISS VEL are
//  the two SLIDERS — signed offsets (−63…+63) added to a note's velocity on a pattern hit / rest step, drawn centre-anchored (bipolar). The card layout reuses `emitterRatchetLayout(…, cellCount: 5)`.

import Foundation
import CoreGraphics

// MARK: - the readout cells (§ like the ratchet's §4.7 / §6.2)

/// STEPS "8"; HITS "3"; OFFSET "0", else "+2"; HIT VEL / MISS VEL "0", else "+20" / "−15".
func emitterVelocityValueText(_ f: EmitterVelocityField, _ v: EmitterVelocity) -> String {
    switch f {
    case .steps: return "\(v.steps)"
    case .hits: return "\(v.hits)"
    case .offset: return v.offset == 0 ? "0" : "+\(v.offset)"
    case .hitVel: return signed(v.hitVel)
    case .missVel: return signed(v.missVel)
    }
}
private func signed(_ n: Int) -> String { n == 0 ? "0" : (n > 0 ? "+\(n)" : "\u{2212}\(-n)") }   // U+2212 MINUS, so a negative reads as cleanly as a plus

/// The bar's fill fraction: a pattern field is its share of its range (0…1, drawn from the left, like the ratchet); HIT VEL / MISS VEL are SIGNED (−1…+1, drawn from the centre).
func emitterVelocityBarShare(_ f: EmitterVelocityField, _ v: EmitterVelocity) -> Double {
    if f.bipolar { return Double(f.value(of: v)) / Double(EmitterVelocity.maxVel) }
    let range = f.range(in: v)
    let span = Double(range.upperBound - range.lowerBound)
    let share = span > 0 ? Double(f.value(of: v) - range.lowerBound) / span : 1
    return max(0.06, min(1, share))
}

// MARK: - the drag (§6.2)

/// Points of upward travel per step: STEPS / HITS / OFFSET one per 10 pt; HIT VEL / MISS VEL (range ±63, step 5) one step per 3 pt, so a comfortable drag spans the range.
func emitterVelocityPointsPerStep(_ f: EmitterVelocityField) -> CGFloat {
    f.bipolar ? 3 : 10
}
/// The value a drag has reached — `start` plus a whole number of steps for the travel so far (up positive), clamped at the ends by `setting` (never wrapped).
func emitterVelocityDragValue(_ f: EmitterVelocityField, start v: EmitterVelocity, travelUp: CGFloat) -> EmitterVelocity {
    let steps = Int((travelUp / emitterVelocityPointsPerStep(f)).rounded(.towardZero))
    return f.setting(f.value(of: v) + steps * f.step, in: v)
}

// MARK: - VoiceOver (§ like the ratchet's §8)

func emitterVelocityTabAccessibilityLabel() -> String { "Velocity" }
func emitterVelocityToggleLabel(output x: Int) -> String { "Velocity on emitter \(emitterRatchetLetters[max(0, min(3, x))])" }
/// "Emitter A pattern, 3 of 8, hit velocity plus 20, miss velocity minus 10" — one static element; the strip is not announced as it plays.
func emitterVelocityStripLabel(output x: Int, _ v: EmitterVelocity) -> String {
    "Emitter \(emitterRatchetLetters[max(0, min(3, x))]) pattern, \(v.hits) of \(v.steps), hit velocity \(spoken(v.hitVel)), miss velocity \(spoken(v.missVel))"
}
/// "Emitter A steps 8" · "hits 3" · "offset plus 2" (0 reads "0") · "hit velocity plus 20" / "minus 10" / "0" · "miss velocity …".
func emitterVelocityCellLabel(output x: Int, _ f: EmitterVelocityField, _ v: EmitterVelocity) -> String {
    let who = "Emitter \(emitterRatchetLetters[max(0, min(3, x))])"
    switch f {
    case .steps: return "\(who) steps \(v.steps)"
    case .hits: return "\(who) hits \(v.hits)"
    case .offset: return v.offset == 0 ? "\(who) offset 0" : "\(who) offset plus \(v.offset)"
    case .hitVel: return "\(who) hit velocity \(spoken(v.hitVel))"
    case .missVel: return "\(who) miss velocity \(spoken(v.missVel))"
    }
}
private func spoken(_ n: Int) -> String { n == 0 ? "0" : (n > 0 ? "plus \(n)" : "minus \(-n)") }
