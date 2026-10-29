//  LaneViewStripPainter.swift
//  TAB STRIP ferry (2026-10-29): the page's one tab strip — RHYTHM · RIFF · NOTES · LISTEN in one segmented control, MIX on its own, then the dice and the padlock (the page passes those two tiles in: they read the page's mode state).
//  Every frame, state and word comes from LaneViewStrip.swift (`euclideousLaneStripLayout`, `…SegmentContent`, `…Glyphs`, `…GlyphLook`, `…Label`); this file only paints them. SwiftUI-only on purpose (GridUI seam rule).
//  (The "strip" here is the lane area's tab strip — not the lane card's comet strip, and not the bottom-right panel's tab row or the riff panel's riff tabs.)

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}

/// One cluster glyph, plain: a filled shape in a lane's colour, or a 1 pt inner outline with no fill. Used whenever no hocket rule is lit (the page keeps the plain drawing then — nothing observes the live model).
struct EuclideousLaneStripGlyphView: View {
    let shape: EuclideousGlyphShape
    let look: EuclideousLaneStripGlyphLook
    let laneColours: [Color]
    var body: some View {
        let s = EuclideousLaneStripMetrics.glyphSize(shape)
        return drawn.frame(width: s.width, height: s.height)
    }
    @ViewBuilder private var drawn: some View {
        switch shape {
        case .none: EmptyView()
        case .square: filled(RoundedRectangle(cornerRadius: EuclideousLaneStripMetrics.squareRadius))
        case .bar: filled(RoundedRectangle(cornerRadius: EuclideousLaneStripMetrics.barRadius))
        case .circle: filled(Circle())
        }
    }
    @ViewBuilder private func filled<S: InsettableShape>(_ s: S) -> some View {
        if let lane = look.filledLane { s.fill(laneColours[max(0, min(laneColours.count - 1, lane))]) }
        else if let o = look.outline { s.strokeBorder(Color(o), lineWidth: EuclideousLaneStripMetrics.outlineWidth) }
    }
}

/// A RIFF square / NOTES bar with a hocket rule lit: the part's hocket state (playing · resting · away · carrying, `hocketGlyphSpec`) drawn at the strip's size — the tab-row glyph's looks at 2/3 scale (the 9 pt square became 6; the
/// ring, the away disc and their widths scale with it). An OFF part shows the strip's off outline (a carried line still wears its ring). A leaf that OBSERVES the live model, like the tab-row glyph it replaces.
struct EuclideousLaneStripHocketGlyph: View {
    let shape: EuclideousGlyphShape          // .square (RIFF) or .bar (NOTES)
    let glyph: EuclideousTabGlyph
    let selected: Bool
    let lane: Int
    let laneColours: [Color]
    let rules: [HocketRule]
    @ObservedObject var live: HocketLiveModel
    let ground: Color                         // the segment's fill: the rings are drawn in it
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scale: CGFloat = 2.0 / 3.0

    var body: some View {
        typealias M = EuclideousLaneStripMetrics
        let notes = shape == .bar
        let view = hocketLivePartView(lane: lane, notes: notes, rules: rules, live: live)
        let spec = hocketGlyphSpec(lane: lane, partOff: !glyph.on, view: view)
        let size = M.glyphSize(shape)
        let radius: CGFloat = notes ? M.barRadius : M.squareRadius
        let k = Self.scale
        let ringGap = HocketGlyphSpec.ringGap * k, ringWidth = HocketGlyphSpec.ringWidth * k
        return ZStack(alignment: .topLeading) {
            switch spec.body {
            case .offLook: EuclideousLaneStripGlyphView(shape: shape, look: euclideousLaneStripGlyphLook(EuclideousTabGlyph(shape: shape, on: false, fill: glyph.fill), selected: selected), laneColours: laneColours)
            case .filled(let c): RoundedRectangle(cornerRadius: radius).fill(Color(c)).frame(width: size.width, height: size.height)
            case .outline(let c): RoundedRectangle(cornerRadius: radius).strokeBorder(Color(c), lineWidth: HocketGlyphSpec.outlineWidth * k).frame(width: size.width, height: size.height)
            }
            if let ring = spec.carriedRing {
                RoundedRectangle(cornerRadius: radius + ringGap).strokeBorder(ground, lineWidth: ringGap).padding(-ringGap).frame(width: size.width, height: size.height)
                RoundedRectangle(cornerRadius: radius + ringGap + ringWidth).strokeBorder(Color(ring), lineWidth: ringWidth).padding(-(ringGap + ringWidth)).frame(width: size.width, height: size.height)
            }
            if let disc = spec.awayDisc {
                let d = HocketGlyphSpec.disc * k
                Circle().fill(Color(disc)).frame(width: d, height: d)
                    .overlay(Circle().strokeBorder(ground, lineWidth: HocketGlyphSpec.discRing * k).padding(-HocketGlyphSpec.discRing * k).frame(width: d, height: d))
                    .offset(x: size.width + HocketGlyphSpec.discBeyond * k - d / 2, y: size.height + HocketGlyphSpec.discBelow * k - d / 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: HocketGlyphSpec.easeSeconds), value: spec)
    }
}

/// The strip itself, 28 tall, in its own coordinates (0,0 = its top-left). `dice` and `padlock` are the page's tiles, already 36 × 44 touch targets (their drawing, taps, states and VoiceOver are the page's); they are placed on
/// the layout's target frames. The page offsets this view to the lane area's top.
struct EuclideousLaneViewStrip: View {
    typealias M = EuclideousLaneStripMetrics
    let width: CGFloat
    let tab: EuclideousPageTab
    let lines: [EuclidLine]
    let laneColours: [Color]            // lane100 of lanes 1–4
    let hocketRules: [HocketRule]
    let hocketLive: HocketLiveModel
    let dice: AnyView
    let padlock: AnyView
    let onSelect: (EuclideousPageTab) -> Void

    var body: some View {
        let L = euclideousLaneStripLayout(width: width)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: M.containerRadius).fill(Color(M.container)).frame(width: L.tabControl.width, height: L.tabControl.height)
            ForEach(0..<4, id: \.self) { i in segment(i, L) }
            mixSegment(L)
            dice.frame(width: M.tileTargetWidth, height: M.targetHeight).offset(x: L.diceTarget.minX, y: L.diceTarget.minY)
            padlock.frame(width: M.tileTargetWidth, height: M.targetHeight).offset(x: L.padlockTarget.minX, y: L.padlockTarget.minY)
        }
        .frame(width: width, height: M.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(euclideousLaneStripGroupLabel)
    }

    // MARK: one segment of the tab control

    private func segment(_ i: Int, _ L: EuclideousLaneStripLayout) -> some View {
        let t = EuclideousPageTab(rawValue: i) ?? .rhythm
        let sel = tab == t
        let seg = L.segments[i], target = L.segmentTargets[i]
        let glyphs = euclideousLaneStripGlyphs(tab: t, lines: lines)
        let shape = euclideousLaneStripShape(t)
        let showCluster = L.clustersVisible && shape != .none && glyphs.count == 4
        let ground = Color(sel ? M.selectedFill : M.container)
        return ZStack(alignment: .topLeading) {
            if sel { RoundedRectangle(cornerRadius: M.segmentRadius).fill(Color(M.selectedFill)).frame(width: seg.width, height: seg.height).offset(x: seg.minX, y: seg.minY) }
            HStack(spacing: M.labelClusterGap) {
                label(t.label, selected: sel)
                if showCluster { cluster(t, shape: shape, glyphs: glyphs, selected: sel, ground: ground) }
            }
            .frame(width: seg.width, height: seg.height).offset(x: seg.minX, y: seg.minY)
            .allowsHitTesting(false).accessibilityHidden(true)
            Color.clear.frame(width: target.width, height: target.height).contentShape(Rectangle())
                .onTapGesture { onSelect(t) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(euclideousLaneStripLabel(tab: t, glyphs: glyphs))
                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : [.isButton])
                .offset(x: target.minX, y: target.minY)
        }
    }
    private func mixSegment(_ L: EuclideousLaneStripLayout) -> some View {
        let sel = tab == .mix
        let seg = L.mixSegment, target = L.mixTarget
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: M.containerRadius).fill(Color(M.container)).frame(width: L.mix.width, height: L.mix.height).offset(x: L.mix.minX, y: L.mix.minY)
            if sel { RoundedRectangle(cornerRadius: M.segmentRadius).fill(Color(M.selectedFill)).frame(width: seg.width, height: seg.height).offset(x: seg.minX, y: seg.minY) }
            label(EuclideousPageTab.mix.label, selected: sel).frame(width: seg.width, height: seg.height).offset(x: seg.minX, y: seg.minY)
                .allowsHitTesting(false).accessibilityHidden(true)
            Color.clear.frame(width: target.width, height: target.height).contentShape(Rectangle())
                .onTapGesture { onSelect(.mix) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(euclideousLaneStripLabel(tab: .mix, glyphs: []))
                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : [.isButton])
                .offset(x: target.minX, y: target.minY)
        }
    }

    private func label(_ text: String, selected: Bool) -> some View {
        Text(text).font(.system(size: M.labelFont, weight: .heavy, design: .monospaced)).tracking(M.labelFont * M.labelTracking)
            .foregroundColor(Color(selected ? M.selectedText : M.unselectedText)).lineLimit(1).truncationMode(.tail)
    }

    private func cluster(_ t: EuclideousPageTab, shape: EuclideousGlyphShape, glyphs: [EuclideousTabGlyph], selected: Bool, ground: Color) -> some View {
        let hocket = (shape == .square || shape == .bar) && hocketRules.contains(where: { $0.isLit })
        return HStack(spacing: M.glyphGap) {
            ForEach(0..<4, id: \.self) { lane in
                if hocket {
                    EuclideousLaneStripHocketGlyph(shape: shape, glyph: glyphs[lane], selected: selected, lane: lane, laneColours: laneColours, rules: hocketRules, live: hocketLive, ground: ground)
                } else {
                    EuclideousLaneStripGlyphView(shape: shape, look: euclideousLaneStripGlyphLook(glyphs[lane], selected: selected), laneColours: laneColours)
                }
            }
        }
        .fixedSize()
    }
}
