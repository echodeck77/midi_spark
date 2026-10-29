//  LaneViewStrip.swift
//  TAB STRIP ferry (2026-10-29): the pure functions behind the page's one tab strip — the segmented RHYTHM · RIFF · NOTES · LISTEN control, MIX on its own, then the dice and the padlock — and the page's one tab value.
//  Foundation only, on purpose (the macOS test target compiles this file directly): every frame, colour, state and word the strip draws is decided — and tested — here; the views paint these and nothing else.
//
//  The strip sits in the lane area, 28 tall, above the four lane cards. All four cards show the one selected tab; MIX shows their backs. A strip is NOT the bottom-right panel's tab row or the riff panel's riff tabs (those keep their names).
//  Where the ferry's numbers disagree with each other the layout follows its rule: the landscape strip spans the lane area (769.33 at the 1190 reference, flush with lane 2's right edge), not the ferry's 753.33 (Paul, asked).

import Foundation

// MARK: - the page's one tab

/// The tab all four lane cards show. MIX is the fifth: whatever is lit is what you see.
enum EuclideousPageTab: Int, CaseIterable, Equatable {
    case rhythm = 0, riff = 1, notes = 2, listen = 3, mix = 4
    /// The page opens on RHYTHM, never on MIX (the tab is not saved, so every open is this).
    static let opening: EuclideousPageTab = .rhythm
    /// The front tab this page tab shows on the cards; nil for MIX (the backs).
    var front: EuclideousTabKind? { self == .mix ? nil : EuclideousTabKind(rawValue: rawValue) }
    var isMix: Bool { self == .mix }
    var spokenName: String {
        switch self { case .rhythm: return "Rhythm"; case .riff: return "Riff"; case .notes: return "Notes"; case .listen: return "Listen"; case .mix: return "Mix" }
    }
    var label: String { spokenName.uppercased() }
}

/// What a tap on the strip does: nothing when the segment is already selected; otherwise the new tab, and whether the cards turn over (the flip) — exactly when one of the two tabs is MIX.
struct EuclideousPageTabChange: Equatable {
    var tab: EuclideousPageTab
    var flips: Bool
}
func euclideousPageTabTap(current: EuclideousPageTab, tapped: EuclideousPageTab) -> EuclideousPageTabChange? {
    guard tapped != current else { return nil }
    return EuclideousPageTabChange(tab: tapped, flips: current.isMix != tapped.isMix)
}
/// Which tab a random card's selector starts on when random mode begins: the page tab, or RHYTHM when the page tab is LISTEN (random mode throws RHYTHM, RIFF or NOTES) or MIX.
func euclideousRandomStartTab(_ tab: EuclideousPageTab) -> EuclideousRandomTab {
    switch tab { case .rhythm: return .rhythm; case .riff: return .riff; case .notes: return .notes; case .listen, .mix: return .rhythm }
}

// MARK: - the strip's frames

enum EuclideousLaneStripMetrics {
    static let height: CGFloat = 28
    static let containerInset: CGFloat = 3, containerRadius: CGFloat = 8
    static let segmentHeight: CGFloat = 22, segmentRadius: CGFloat = 6, segmentGap: CGFloat = 3
    static let mixWidth: CGFloat = 78
    static let tileSize: CGFloat = 28, tilePlateRadius: CGFloat = 8, tileGlyph: CGFloat = 16
    static let tileTargetWidth: CGFloat = 36, targetHeight: CGFloat = 44
    static let sp4: CGFloat = 4, sp8: CGFloat = 8
    /// The dice's marching-ants ring round its 28 plate (the header's was 40 round a 36 plate).
    static let diceRingSize: CGFloat = 32, diceRingRadius: CGFloat = 10
    /// Below this a segment hides the four glyph clusters (all four together) before any label truncates.
    static let segmentFloor: CGFloat = 96
    static let labelFont: CGFloat = 10, labelTracking: CGFloat = 0.12, monoAdvance: CGFloat = 0.66   // SF Mono Heavy measures ≈ 0.66 em an advance on device (the card back's label metric)
    static let labelClusterGap: CGFloat = 8
    static let glyphGap: CGFloat = 4
    static let squareSize = CGSize(width: 6, height: 6), squareRadius: CGFloat = 1.5
    static let barSize = CGSize(width: 3, height: 8), barRadius: CGFloat = 1
    static let circleSize = CGSize(width: 6, height: 6)
    static let outlineWidth: CGFloat = 1
    static let container = HocketColor(0x1F2127), selectedFill = HocketColor(0xDFE3EA), selectedText = HocketColor(0x0D0F14), unselectedText = HocketColor(0xAAB0BA)
    static let outlineOnSelected = HocketColor(0x8A909A), outlineOnUnselected = HocketColor(0x4A4E57)
    static func labelWidth(_ chars: Int) -> CGFloat { CGFloat(chars) * labelFont * (monoAdvance + labelTracking) }
    static func glyphSize(_ shape: EuclideousGlyphShape) -> CGSize {
        switch shape { case .square: return squareSize; case .bar: return barSize; case .circle: return circleSize; case .none: return .zero }
    }
}
/// The width of one tab's four-glyph cluster: four glyphs, 4 pt apart.
func euclideousLaneStripClusterWidth(_ shape: EuclideousGlyphShape) -> CGFloat {
    typealias M = EuclideousLaneStripMetrics
    guard shape != .none else { return 0 }
    return M.glyphSize(shape).width * 4 + M.glyphGap * 3
}

struct EuclideousLaneStripLayout: Equatable {
    var bounds: CGRect                   // (0, 0, width, 28) — strip coordinates throughout
    var tabControl: CGRect               // the container of the four segments
    var segments: [CGRect]               // RHYTHM, RIFF, NOTES, LISTEN — the drawn segments (22 tall)
    var segmentTargets: [CGRect]         // each its width by 44 tall, centred on the segment
    var mix: CGRect                      // MIX's container (78 × 28)
    var mixSegment: CGRect               // the one drawn segment inside it
    var mixTarget: CGRect                // 78 × 44
    var dice: CGRect, padlock: CGRect    // 28 × 28 plates
    var diceTarget: CGRect, padlockTarget: CGRect   // 36 × 44, centred on the plate
    /// The four glyph clusters show only while every segment is at least 96 wide.
    var clustersVisible: Bool
    var segmentWidth: CGFloat { segments.first?.width ?? 0 }
    var belowFloor: Bool { segmentWidth < EuclideousLaneStripMetrics.segmentFloor }
}
/// The strip's frames for a lane area `width` wide (landscape: columns 1–2; portrait: the page): the tab control takes what MIX (78), the dice and the padlock (28 each) and their gaps (sp8, sp8, sp4) leave.
/// Landscape reference 769.33 → control 615.33, segments 150.08; portrait 782 → 628, 153.25.
func euclideousLaneStripLayout(width: CGFloat) -> EuclideousLaneStripLayout {
    typealias M = EuclideousLaneStripMetrics
    let w = max(1, width)
    let padlockX = w - M.tileSize
    let diceX = padlockX - M.sp4 - M.tileSize
    let mixX = diceX - M.sp8 - M.mixWidth
    let controlW = max(1, mixX - M.sp8)
    let control = CGRect(x: 0, y: 0, width: controlW, height: M.height)
    let segW = max(1, (controlW - 2 * M.containerInset - 3 * M.segmentGap) / 4)
    let segY = (M.height - M.segmentHeight) / 2
    var segs: [CGRect] = [], targets: [CGRect] = []
    for i in 0..<4 {
        let r = CGRect(x: M.containerInset + CGFloat(i) * (segW + M.segmentGap), y: segY, width: segW, height: M.segmentHeight)
        segs.append(r)
        targets.append(CGRect(x: r.minX, y: r.midY - M.targetHeight / 2, width: r.width, height: M.targetHeight))
    }
    let mix = CGRect(x: mixX, y: 0, width: M.mixWidth, height: M.height)
    let mixSeg = CGRect(x: mix.minX + M.containerInset, y: segY, width: M.mixWidth - 2 * M.containerInset, height: M.segmentHeight)
    let mixTarget = CGRect(x: mix.minX, y: mixSeg.midY - M.targetHeight / 2, width: M.mixWidth, height: M.targetHeight)
    let dice = CGRect(x: diceX, y: 0, width: M.tileSize, height: M.tileSize)
    let padlock = CGRect(x: padlockX, y: 0, width: M.tileSize, height: M.tileSize)
    func target(_ tile: CGRect) -> CGRect { CGRect(x: tile.midX - M.tileTargetWidth / 2, y: tile.midY - M.targetHeight / 2, width: M.tileTargetWidth, height: M.targetHeight) }
    return EuclideousLaneStripLayout(bounds: CGRect(x: 0, y: 0, width: w, height: M.height), tabControl: control, segments: segs, segmentTargets: targets, mix: mix, mixSegment: mixSeg, mixTarget: mixTarget,
                                     dice: dice, padlock: padlock, diceTarget: target(dice), padlockTarget: target(padlock), clustersVisible: segW >= M.segmentFloor)
}

/// Where one segment's label and glyph cluster sit: the two as ONE group, sp8 apart, centred in the segment (a segment with no cluster, or with clusters hidden, centres its label alone). The label's frame is its estimated
/// text box; the view draws the same group with a centred stack.
struct EuclideousLaneStripSegmentContent: Equatable {
    var label: CGRect
    var cluster: CGRect?          // nil: RHYTHM, or the clusters are hidden
    var glyphs: [CGRect]          // the four glyph frames (empty when there is no cluster)
}
func euclideousLaneStripSegmentContent(segment: CGRect, tab: EuclideousPageTab, clustersVisible: Bool) -> EuclideousLaneStripSegmentContent {
    typealias M = EuclideousLaneStripMetrics
    let shape = euclideousLaneStripShape(tab)
    let labelW = min(segment.width, M.labelWidth(tab.label.count))
    let hasCluster = clustersVisible && shape != .none
    let clusterW = hasCluster ? euclideousLaneStripClusterWidth(shape) : 0
    let groupW = labelW + (hasCluster ? M.labelClusterGap + clusterW : 0)
    let x0 = segment.midX - groupW / 2
    let label = CGRect(x: x0, y: segment.midY - M.labelFont / 2, width: labelW, height: M.labelFont)
    guard hasCluster else { return EuclideousLaneStripSegmentContent(label: label, cluster: nil, glyphs: []) }
    let g = M.glyphSize(shape)
    let cx = label.maxX + M.labelClusterGap
    var frames: [CGRect] = []
    for i in 0..<4 { frames.append(CGRect(x: cx + CGFloat(i) * (g.width + M.glyphGap), y: segment.midY - g.height / 2, width: g.width, height: g.height)) }
    return EuclideousLaneStripSegmentContent(label: label, cluster: CGRect(x: cx, y: segment.midY - g.height / 2, width: clusterW, height: g.height), glyphs: frames)
}

// MARK: - the glyph clusters

/// The shape a tab's cluster draws: RIFF square, NOTES bar, LISTEN circle; RHYTHM and MIX have none. (The same shapes as the lane tab-row glyphs had, at the strip's size.)
func euclideousLaneStripShape(_ tab: EuclideousPageTab) -> EuclideousGlyphShape {
    switch tab { case .riff: return .square; case .notes: return .bar; case .listen: return .circle; case .rhythm, .mix: return .none }
}
/// The four lanes' glyph states for a tab — one call of the clarity pass's glyph-state function per lane (`euclideousTabGlyph`, Derivations.swift), never a second derivation. Empty for RHYTHM and MIX.
func euclideousLaneStripGlyphs(tab: EuclideousPageTab, lines: [EuclidLine]) -> [EuclideousTabGlyph] {
    guard let kind = tab.front, euclideousLaneStripShape(tab) != .none else { return [] }
    return (0..<4).map { lane in euclideousTabGlyph(tab: kind, line: lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all), lane: lane) }
}
/// How one strip glyph draws: filled in a lane's colour (`filledLane`: its own lane, or — LISTEN following a source — the source's), or a 1 pt inner outline with no fill (#8A909A on the selected segment, #4A4E57 on an unselected one).
struct EuclideousLaneStripGlyphLook: Equatable {
    var filledLane: Int?
    var outline: HocketColor?
}
func euclideousLaneStripGlyphLook(_ glyph: EuclideousTabGlyph, selected: Bool) -> EuclideousLaneStripGlyphLook {
    typealias M = EuclideousLaneStripMetrics
    guard glyph.on else { return EuclideousLaneStripGlyphLook(filledLane: nil, outline: selected ? M.outlineOnSelected : M.outlineOnUnselected) }
    switch glyph.fill { case .lane(let n): return EuclideousLaneStripGlyphLook(filledLane: n, outline: nil) }
}

// MARK: - VoiceOver (U+2019 for apostrophes — none here)

/// "Lane view" is the strip's group label.
let euclideousLaneStripGroupLabel = "Lane view"
/// A segment's spoken name: "Rhythm"; "Riff, lanes 1, 2 and 4 on" / "Riff, all on" / "Riff, all off" (NOTES likewise); "Listen, lane 3 following lane 2" (several: "…, lane 1 following lane 2 and lane 3 following lane 4") /
/// "Listen, all off"; "Mix". `glyphs` are the four lanes' states for the tab (empty for RHYTHM and MIX).
func euclideousLaneStripLabel(tab: EuclideousPageTab, glyphs: [EuclideousTabGlyph]) -> String {
    let name = tab.spokenName
    guard euclideousLaneStripShape(tab) != .none, glyphs.count == 4 else { return name }
    let onLanes = glyphs.enumerated().filter { $0.element.on }.map { $0.offset + 1 }
    func joined(_ parts: [String]) -> String {
        switch parts.count { case 0: return ""; case 1: return parts[0]; case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts.last! }
    }
    if onLanes.isEmpty { return "\(name), all off" }
    if tab == .listen {
        let follows = glyphs.enumerated().filter { $0.element.on }.map { (lane, g) -> String in
            if case .lane(let src) = g.fill { return "lane \(lane + 1) following lane \(src + 1)" }
            return "lane \(lane + 1)"
        }
        return "\(name), \(follows.joined(separator: " and "))"
    }
    if onLanes.count == 4 { return "\(name), all on" }
    let nums = joined(onLanes.map(String.init))
    return "\(name), \(onLanes.count == 1 ? "lane" : "lanes") \(nums) on"
}
