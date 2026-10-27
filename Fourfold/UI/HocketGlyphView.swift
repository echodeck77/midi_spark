//  HocketGlyphView.swift
//  HOCKET ferry (2026-10-27) §9.2: the lane cards' RIFF square and NOTES bar, drawn by the part's hocket state — on the tab row (clarity pass §2) and on the MIX pad labels (§3.4), at the clarity pass's sizes.
//  What each state looks like is `hocketGlyphSpec` (Derivations.swift); this file only paints it. `HocketPartGlyph` OBSERVES the live model (a leaf: a turn changing re-evaluates this glyph, never the page body),
//  and `hocketPartAX` does the same for the VoiceOver label. With no rule lit the page keeps drawing the plain `EuclideousTabGlyphView` — nothing here runs.

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}

/// The hocket state of lane `lane`'s riff (`notes == false`) or notes part right now, from the live counts: the same `hocketPartView` the engine's routing and the pop-up's chips agree with.
func hocketLivePartView(lane: Int, notes: Bool, rules: [HocketRule], live: HocketLiveModel) -> HocketPartView {
    let snap = HocketRulesSnap(rules: rules)
    guard !snap.isInert else { return HocketPartView() }
    var turns = HocketTurns(); turns.running = live.running
    for i in 0..<HocketRuleSet.maxRules where snap.litMask & (UInt8(1) << UInt8(i)) != 0 { turns[i] = live.turn(rule: i, snap: snap[i]) }
    return hocketPartView(bus: lane * 2 + (notes ? 1 : 0), rules: snap, turns: turns)
}

struct HocketPartGlyph: View {
    let shape: EuclideousGlyphShape          // .square (RIFF) or .bar (NOTES)
    let on: Bool                              // the tab's own on/off — an OFF part shows only the clarity pass's off look
    let fill: Color                           // the clarity pass's on fill (lane100)
    let lane: Int
    let rules: [HocketRule]
    @ObservedObject var live: HocketLiveModel
    let ground: Color                         // the card's fill (the pad's, on MIX): the rings are drawn in it
    @Environment(\.accessibilityReduceMotion) private var reduceMotion   // Reduce Motion: the state change is instant, no 0.15 s ease

    var body: some View {
        let notes = shape == .bar
        let view = hocketLivePartView(lane: lane, notes: notes, rules: rules, live: live)
        let spec = hocketGlyphSpec(lane: lane, partOff: !on, view: view)
        let size = EuclideousTabGlyphView.size(shape)
        let radius: CGFloat = notes ? 1.5 : 2
        return ZStack(alignment: .topLeading) {
            switch spec.body {
            case .offLook: EuclideousTabGlyphView(shape: shape, on: false, fill: fill)
            case .filled(let c): EuclideousTabGlyphView(shape: shape, on: true, fill: Color(c))
            case .outline(let c): RoundedRectangle(cornerRadius: radius).strokeBorder(Color(c), lineWidth: HocketGlyphSpec.outlineWidth).frame(width: size.width, height: size.height)
            }
            if let ring = spec.carriedRing {
                RoundedRectangle(cornerRadius: radius + HocketGlyphSpec.ringGap).strokeBorder(ground, lineWidth: HocketGlyphSpec.ringGap).padding(-HocketGlyphSpec.ringGap).frame(width: size.width, height: size.height)
                RoundedRectangle(cornerRadius: radius + HocketGlyphSpec.ringGap + HocketGlyphSpec.ringWidth).strokeBorder(Color(ring), lineWidth: HocketGlyphSpec.ringWidth)
                    .padding(-(HocketGlyphSpec.ringGap + HocketGlyphSpec.ringWidth)).frame(width: size.width, height: size.height)
            }
            if let disc = spec.awayDisc {
                let d = HocketGlyphSpec.disc
                Circle().fill(Color(disc)).frame(width: d, height: d)
                    .overlay(Circle().strokeBorder(ground, lineWidth: HocketGlyphSpec.discRing).padding(-HocketGlyphSpec.discRing).frame(width: d, height: d))
                    .offset(x: size.width + HocketGlyphSpec.discBeyond - d / 2, y: size.height + HocketGlyphSpec.discBelow - d / 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: HocketGlyphSpec.easeSeconds), value: spec)
    }
}

/// §10.9 — the hocket state appended after "on" in a lane tab's / MIX pad's VoiceOver label ("Notes, on, resting"). It OBSERVES the live model, so it follows the turn without the page body re-running.
struct HocketPartAX: ViewModifier {
    let base: String
    let lane: Int
    let notes: Bool
    let partOff: Bool
    let rules: [HocketRule]
    @ObservedObject var live: HocketLiveModel
    func body(content: Content) -> some View {
        let view = hocketLivePartView(lane: lane, notes: notes, rules: rules, live: live)
        let state = partOff ? nil : HocketAX.partState(view)
        return content.accessibilityLabel(state.map { base + ", " + $0 } ?? base)
    }
}
extension View {
    /// The part's VoiceOver label with its hocket state when a rule is lit (and the plain label otherwise — the view tree is untouched for a document with no rules).
    @ViewBuilder func hocketPartAX(base: String, lane: Int, notes: Bool, partOff: Bool, rules: [HocketRule], live: HocketLiveModel?) -> some View {
        if let live, rules.contains(where: { $0.isLit }) {
            modifier(HocketPartAX(base: base, lane: lane, notes: notes, partOff: partOff, rules: rules, live: live))
        } else {
            accessibilityLabel(base)
        }
    }
}
