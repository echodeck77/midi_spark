//  RestartEditorUI.swift — RESTART UNITS ferry (2026-11-04), slices C and D: everything the restart TILES and the restart EDITOR show or do, as pure functions (Foundation + CoreGraphics only) — the tile's text, look and
//  VoiceOver label; the editor's frames at any size; each tap's edit; the 16-cell timeline; the VoiceOver strings. The views (`EuclideousPage.swift`) only paint what this computes and call these for a tap, so the tests read the
//  numbers the screen is built from.

import Foundation
import CoreGraphics

// MARK: - the tile (§6, §9.1)

/// What a restart tile shows for one part of one lane. `kind` rhythm / melody; `ownLane` 0…3.
struct EuclideousRestartTileSpec: Equatable {
    /// §6.1: a rhythm tile is set when its chain is active; a melody tile when its chain is active or WITH RHYTHM is on.
    var isSet: Bool
    /// The value: the links joined with U+00B7, "RHYTHM" for a melody tile whose chain is inactive with WITH RHYTHM on, otherwise "FREE".
    var valueText: String
    /// BAR / PASS / RIFF / HIT — only for an active chain of 1–3 links.
    var unitText: String?
    /// The lane whose 7 × 7 square the tile wears: an active chain whose unit reads a source other than the lane itself.
    var sourceLane: Int?
    /// MELODY only: the link glyph — shown when WITH RHYTHM is on AND the melody chain is active (§4.2). An inactive chain with WITH RHYTHM reads "RHYTHM" with no glyph.
    var showsLinkGlyph: Bool
    /// The lane whose colour the outer fill takes: the source lane when `sourceLane` is set, else the lane's own.
    var fillLane: Int
    /// The text as it reads, for tests and the layout check: "2·1·1 PASS", "RHYTHM", "FREE".
    var text: String { unitText.map { valueText + " " + $0 } ?? valueText }
}
func euclideousRestartTileSpec(rhythm: Bool, settings s: EuclideousRestartSettings, ownLane: Int) -> EuclideousRestartTileSpec {
    let own = max(0, min(3, ownLane))
    let chain = rhythm ? s.rhythm : s.melody
    let active = rhythm ? s.rhythmActive : s.melodyActive
    let readsSource = active && (rhythm ? s.rhythmUnit.readsSource : s.melodyUnit.readsSource)
    let source = rhythm ? s.rhythmSource : s.melodySource
    let withRhythm = !rhythm && s.withRhythm
    let value: String
    if active { value = chain.links.map { String($0) }.joined(separator: "\u{B7}") } else if withRhythm { value = "RHYTHM" } else { value = "FREE" }
    let unit: String? = active && chain.count <= 3 ? (rhythm ? s.rhythmUnit.rawValue : s.melodyUnit.rawValue) : nil
    let src: Int? = readsSource && source != own ? max(0, min(3, source)) : nil
    // §4.2: the link glyph shows only when WITH RHYTHM is on AND the melody chain is active (value = the links). An inactive chain with WITH RHYTHM reads "RHYTHM" with no glyph.
    return EuclideousRestartTileSpec(isSet: active || withRhythm, valueText: value, unitText: unit, sourceLane: src, showsLinkGlyph: withRhythm && active, fillLane: src ?? own)
}

/// §6.2's fit rule, from the page's own type: monospaced heavy glyphs are ≈ 0.6 em wide plus tracking. The right-hand group is (link glyph 10) + (source square 7) + value (13 pt) + unit (8 pt, tracked 0.08 em), sp3 apart; the name is
/// the arrow (8) + 3 + "RHYTHM" / "MELODY" (8 pt, tracked 0.1 em — §4.1 dropped the " RESTART"). Drop the unit first, then truncate the name; never shrink.
struct EuclideousRestartTileFit: Equatable {
    var showsUnit: Bool
    var nameTruncates: Bool
    var groupWidth: CGFloat
    var nameWidth: CGFloat
}
func euclideousRestartTileFit(spec: EuclideousRestartTileSpec, name: String, tileWidth: CGFloat) -> EuclideousRestartTileFit {
    func mono(_ s: String, size: CGFloat, tracking: CGFloat) -> CGFloat { CGFloat(s.count) * (0.6 * size + tracking) }
    let avail = max(0, tileWidth - 20)                       // 10 pt either side
    let nameW = 8 + 3 + mono(name, size: 8, tracking: 0.8)   // §4.1: the name is "RHYTHM" / "MELODY" alone (no " RESTART")
    var items: [CGFloat] = []
    if spec.showsLinkGlyph { items.append(10) }
    if spec.sourceLane != nil { items.append(7) }
    items.append(mono(spec.valueText, size: 13, tracking: 0))
    func width(withUnit: Bool) -> CGFloat {
        var all = items
        if withUnit, let u = spec.unitText { all.append(mono(u, size: 8, tracking: 0.64)) }
        return all.reduce(0, +) + 3 * CGFloat(max(0, all.count - 1))
    }
    let hasUnit = spec.unitText != nil
    let showsUnit = hasUnit && nameW + 4 + width(withUnit: true) <= avail          // the unit goes first when the group does not fit beside the full name
    let g = width(withUnit: showsUnit)
    return EuclideousRestartTileFit(showsUnit: showsUnit, nameTruncates: nameW + 4 + g > avail, groupWidth: g, nameWidth: nameW)
}

/// §9.1: the tile's VoiceOver label from the resolved settings. `lane` numbers are 1-based in speech.
func euclideousRestartTileLabel(rhythm: Bool, settings s: EuclideousRestartSettings, ownLane: Int) -> String {
    let own = max(0, min(3, ownLane))
    let head = rhythm ? "Rhythm restarts" : "Melody restarts"
    let chain = rhythm ? s.rhythm : s.melody
    let active = rhythm ? s.rhythmActive : s.melodyActive
    let withRhythm = !rhythm && s.withRhythm
    guard active else { return withRhythm ? "\(head) with the rhythm" : "\(head), free" }
    let unit = rhythm ? s.rhythmUnit.word : s.melodyUnit.word
    let readsSource = rhythm ? s.rhythmUnit.readsSource : s.melodyUnit.readsSource
    let source = rhythm ? s.rhythmSource : s.melodySource
    func plural(_ n: Int) -> String { n == 1 ? unit : (unit == "pass" ? "passes" : unit + "s") }
    let other = readsSource && source != own
    let tail = other ? " of lane \(source + 1)" : ""
    var body: String
    if chain.count == 1 {
        let n = chain.link(0)
        if n == 1 { body = "every \(unit)\(tail)" } else { body = "every \(n) \(plural(n))\(tail)" }
    } else {
        let parts = chain.links.map { Int($0) }
        body = "after \(parts[0]) \(plural(parts[0]))\(tail), then " + parts.dropFirst().map { String($0) }.joined(separator: ", then ") + ", repeating"
    }
    return "\(head) \(body)" + (withRhythm ? ", and with the rhythm" : "")
}

// MARK: - the editor's frames (§7.4, §7.6)

// RESTARTS EDITOR V2 (2026-11-06) §2.2: the switches are gone — a FREE pill at the head of row 1 shows a chain is inactive, and a dedicated LINK ROW between the sections carries the melody's WITH RHYTHM (a link button in the label column + a line that
// lights the lane colour). Sections: RHYTHM y32–106, link row y108–128, MELODY y130–204 at the reference (338.5 × 208); rows within a section are row1 y0–24, row2 y28–56, row3 y60–74. Count chips are fixed 44 × 28 and the + box 28 × 28 (no empty slots).
enum EuclideousRestartEditorMetricsV2 {
    static let pad: CGFloat = 8
    static let headerTop: CGFloat = 8, headerH: CGFloat = 20, gapAfterHeader: CGFloat = 4
    static let sectionH: CGFloat = 74, sectionHNoTimeline: CGFloat = 56
    static let gapRhythmToLink: CGFloat = 2, linkRowH: CGFloat = 20, gapLinkToMelody: CGFloat = 2, bottomPad: CGFloat = 4
    static let referenceHeight: CGFloat = 208, compactHeight: CGFloat = 172
    static let labelX: CGFloat = 8, labelW: CGFloat = 56, blockX: CGFloat = 68
    static let row1H: CGFloat = 24, row2Top: CGFloat = 28, row2H: CGFloat = 28, row3Top: CGFloat = 60, row3H: CGFloat = 14
    // row 1 — FREE pill · three unit chips · four source squares
    static let freePillW: CGFloat = 40, freePillH: CGFloat = 24, freeToChipsGap: CGFloat = 8
    static let chipW: CGFloat = 40, chipGap: CGFloat = 4
    static let sourceHitW: CGFloat = 18, sourceHitGap: CGFloat = 4, sourceGlyph: CGFloat = 12
    // row 2 — count chips (only the real links) + a 28 pt add box (only when < 4 links)
    static let countChipW: CGFloat = 44, countChipH: CGFloat = 28, countChipGap: CGFloat = 4, addBoxW: CGFloat = 28
    // the link row's button, in the label column
    static let linkButtonW: CGFloat = 34, linkButtonH: CGFloat = 20
    static let cellGap: CGFloat = 2, cellH: CGFloat = 14, cellCount = 16
    /// The x of the first unit chip (after the FREE pill): 116 at the reference.
    static var chipStartX: CGFloat { blockX + freePillW + freeToChipsGap }
    /// The four source squares' span (right-aligned to the content's trailing edge): 84 pt.
    static var sourcesSpan: CGFloat { 4 * sourceHitW + 3 * sourceHitGap }
}
struct EuclideousRestartSectionFramesV2: Equatable {
    var top: CGFloat
    var labelColumn: CGRect                 // row 1 label (the name), editor coordinates
    var freePill: CGRect                    // 40 × 24, at x 68
    var chips: [CGRect]                     // 3 unit chips
    var sources: [CGRect]                   // 4 hit areas (18 × 24), right-aligned
    var countChips: [CGRect]                // 4 fixed 44 × 28 positions; the view draws `count` of them, then the + box at countChips[count]
    var axisLabel: CGRect?                  // nil when the timeline is dropped
    var cells: [CGRect]                     // 16 timeline cells (empty when dropped)
    /// The + box (28 × 28) when there are `count` (< 4) links — at count-chip slot `count`, left-aligned, 28 wide.
    func addBox(count: Int) -> CGRect? {
        guard count >= 0, count < 4 else { return nil }
        let r = countChips[count]
        return CGRect(x: r.minX, y: r.minY, width: EuclideousRestartEditorMetricsV2.addBoxW, height: r.height)
    }
}
struct EuclideousRestartEditorFramesV2: Equatable {
    var size: CGSize
    var header: CGRect
    var rhythm: EuclideousRestartSectionFramesV2
    var melody: EuclideousRestartSectionFramesV2
    /// The link row between the two sections (§2.2): the WITH RHYTHM button in the label column and the tie line across the right block.
    var linkButton: CGRect
    var linkLine: CGRect
    var showsTimelines: Bool
    /// The right block's width (x 68 to the content's trailing edge): 262.5 at the reference.
    var rightWidth: CGFloat
    /// §7.6: does row 1 fit (the FREE pill, three chips and four source squares need 260 pt of right block)? Reported by the page's floors; nothing shrinks.
    var row1Fits: Bool
    /// Does the bottom edge clip (the editor is under 172)?
    var clipsBottom: Bool
}
func euclideousRestartEditorFramesV2(size: CGSize) -> EuclideousRestartEditorFramesV2 {
    typealias M = EuclideousRestartEditorMetricsV2
    let contentRight = max(M.blockX, size.width - M.pad)
    let rw = contentRight - M.blockX
    let timelines = size.height >= M.referenceHeight
    let sectionH = timelines ? M.sectionH : M.sectionHNoTimeline
    let slack = timelines ? size.height - M.referenceHeight : 0
    let rhythmTop = M.headerTop + M.headerH + M.gapAfterHeader + slack / 2
    let linkTop = rhythmTop + sectionH + M.gapRhythmToLink
    let melodyTop = linkTop + M.linkRowH + M.gapLinkToMelody + slack / 2
    func section(top: CGFloat) -> EuclideousRestartSectionFramesV2 {
        let freePill = CGRect(x: M.blockX, y: top, width: M.freePillW, height: M.freePillH)
        let chips = (0..<3).map { CGRect(x: M.chipStartX + CGFloat($0) * (M.chipW + M.chipGap), y: top, width: M.chipW, height: M.row1H) }
        let srcX = contentRight - M.sourcesSpan
        let sources = (0..<4).map { i in CGRect(x: srcX + CGFloat(i) * (M.sourceHitW + M.sourceHitGap), y: top, width: M.sourceHitW, height: M.row1H) }
        let countChips = (0..<4).map { CGRect(x: M.blockX + CGFloat($0) * (M.countChipW + M.countChipGap), y: top + M.row2Top, width: M.countChipW, height: M.countChipH) }
        let cellW = (rw - 30) / 16
        let cells: [CGRect] = timelines ? (0..<M.cellCount).map { CGRect(x: M.blockX + CGFloat($0) * (cellW + M.cellGap), y: top + M.row3Top, width: cellW, height: M.cellH) } : []
        return EuclideousRestartSectionFramesV2(
            top: top, labelColumn: CGRect(x: M.labelX, y: top, width: M.labelW, height: M.row1H), freePill: freePill, chips: chips, sources: sources, countChips: countChips,
            axisLabel: timelines ? CGRect(x: M.labelX, y: top + M.row3Top, width: M.labelW, height: M.row3H) : nil, cells: cells)
    }
    let needed = M.headerTop + M.headerH + M.gapAfterHeader + sectionH + M.gapRhythmToLink + M.linkRowH + M.gapLinkToMelody + sectionH + M.bottomPad
    let linkButton = CGRect(x: M.labelX, y: linkTop + (M.linkRowH - M.linkButtonH) / 2, width: M.linkButtonW, height: M.linkButtonH)
    let linkLine = CGRect(x: M.blockX, y: linkTop + M.linkRowH / 2 - 1, width: rw, height: 2)
    return EuclideousRestartEditorFramesV2(size: size, header: CGRect(x: M.pad, y: M.headerTop, width: max(0, size.width - 2 * M.pad), height: M.headerH),
                                           rhythm: section(top: rhythmTop), melody: section(top: melodyTop), linkButton: linkButton, linkLine: linkLine,
                                           showsTimelines: timelines, rightWidth: rw,
                                           row1Fits: rw >= 260 - 1e-9, clipsBottom: size.height < needed - 1e-9)
}

// MARK: - what a tap does (§7.4) — one undo step each

enum EuclideousRestartEdit: Equatable {
    case unit(rhythm: Bool, index: Int)       // §2.2 order — RHYTHM chips: PASS, BAR, RIFF · MELODY chips: HIT, PASS, BAR
    case source(rhythm: Bool, lane: Int)
    case toggleOn(rhythm: Bool)               // the FREE pill: on ↔ off (appends a 1 when turning an empty chain on)
    case withRhythm
    case tapLink(rhythm: Bool, slot: Int)     // §3: steps the value, WRAPPING 8 → 1 (never removes)
    case setLink(rhythm: Bool, slot: Int, value: Int)  // §3: a vertical drag sets a value directly (snapped to the unit's ladder)
    case addLink(rhythm: Bool)
    case removeLink(rhythm: Bool, slot: Int)  // §3: a long press (or VoiceOver's "Remove link") — ONE edit; never the only link
}
/// §3: the value a vertical drag of a count chip lands on — `startValue` stepped through the unit's ladder, 6 pt to begin and 12 pt a step (up increases), clamped to the ladder's ends. A pure function so the drag's arithmetic is tested, not the gesture.
func euclideousRestartCountChipDragValue(startValue: Int, translationY: CGFloat, hit: Bool) -> Int {
    let ladder = euclideousRestartLinkLadder(hit: hit)
    let start = ladder.firstIndex(of: UInt8(clamping: max(0, startValue))) ?? 0
    let d = -translationY                                     // up (negative translation) increases
    let steps = abs(d) < 6 ? 0 : Int((abs(d) - 6) / 12) + 1
    let idx = max(0, min(ladder.count - 1, start + (d < 0 ? -steps : steps)))
    return Int(ladder[idx])
}
/// Is lane `lane`'s source square unavailable (§7.4: the lane itself on RHYTHM PASS)?
func euclideousRestartSourceUnavailable(rhythm: Bool, line l: EuclidLine, ownLane: Int, square: Int) -> Bool {
    rhythm && l.restartRhythmUnitResolved == .pass && square == max(0, min(3, ownLane))
}
/// Applies one tap to a lane. `pin` is what an unpinned lane's chains resolve to (the migration) — stored first, in the same step (§3.5). Returns whether anything changed; a tap that changes nothing leaves the line exactly as it was, pin included,
/// so the funnel records no step and writes nothing (adversarial review 2026-11-04: the pin alone used to count as an edit).
@discardableResult
func euclideousApplyRestartEdit(_ e: EuclideousRestartEdit, to l: inout EuclidLine, lane: Int, pin: (rhythm: EuclideousRestartChain, melody: EuclideousRestartChain)?) -> Bool {
    var pinned = l
    if !pinned.usesRestartChains, let p = pin { euclideousPinRestartChains(&pinned, p.rhythm, p.melody) }
    var work = pinned
    euclideousApplyRestartEditCore(e, to: &work, lane: lane)
    guard work != pinned else { return false }
    l = work
    return true
}
/// `.removeLink` must not reactivate a chain, so a switch that was never touched (nil — it reads on exactly when the chain holds a link) is made explicit before the links change under it.
private func fixSwitch(_ l: inout EuclidLine, rhythm: Bool) {
    if rhythm { if l.restartRhythmOn == nil { l.restartRhythmOn = l.restartRhythmOnResolved } }
    else if l.restartMelodyOn == nil { l.restartMelodyOn = l.restartMelodyOnResolved }
}
/// §3: any FREE-row edit turns the chain LIVE in the same step — the switch on, a 1 appended if it had no links. (Replaces RESTART UNITS §7.5's "a link edit never turns a switch on" for every edit but `.removeLink`.)
private func turnChainLive(_ l: inout EuclidLine, rhythm: Bool) {
    if rhythm {
        l.restartRhythmOn = true
        if l.restartRhythmChainResolved.isFree { l.restartRhythmBars = [1] }
    } else {
        l.restartMelodyOn = true
        if l.restartMelodyChainResolved.isFree { l.restartMelodyPasses = [1] }
    }
}
private func euclideousApplyRestartEditCore(_ e: EuclideousRestartEdit, to l: inout EuclidLine, lane: Int) {
    let own = max(0, min(3, lane))
    switch e {
    case .unit(let rhythm, let index):
        if rhythm {
            let units: [EuclideousRhythmRestartUnit] = [.pass, .bar, .riff]   // §2.2 order: short → long (PASS · BAR · RIFF)
            guard index >= 0, index < 3, l.restartRhythmUnitResolved != units[index] else { return }
            l.restartRhythmUnit = units[index]
            if units[index] == .pass, (l.restartRhythmSource.map { max(0, min(3, $0)) } ?? own) == own { l.restartRhythmSource = (own + 1) % 4 }   // PASS never counts the lane itself: the source moves to the next lane in the same step
        } else {
            let units: [EuclideousMelodyRestartUnit] = [.hit, .pass, .bar]   // §2.2 order: short → long (HIT · PASS · BAR)
            guard index >= 0, index < 3, l.restartMelodyUnitResolved != units[index] else { return }
            if l.restartMelodyUnitResolved == .hit {   // leaving HIT: 5 → 6 and 7 → 8 (those values are not valid for the other units)
                l.restartMelodyPasses = l.restartMelodyPasses.map { $0.map { $0 == 5 ? 6 : ($0 == 7 ? 8 : $0) } }
            }
            l.restartMelodyUnit = units[index]
        }
        turnChainLive(&l, rhythm: rhythm)   // §3: choosing a unit on a FREE row wakes it (a 1 is appended if it had no links)
    case .source(let rhythm, let square):
        guard square >= 0, square < 4, !euclideousRestartSourceUnavailable(rhythm: rhythm, line: l, ownLane: lane, square: square) else { return }
        if rhythm { guard l.restartRhythmUnitResolved.readsSource, l.restartRhythmSourceResolved(ownLane: lane) != square else { return }; l.restartRhythmSource = square == own ? nil : square }
        else { guard l.restartMelodyUnitResolved.readsSource, l.restartMelodySourceResolved(ownLane: lane) != square else { return }; l.restartMelodySource = square == own ? nil : square }
        turnChainLive(&l, rhythm: rhythm)   // §3
    case .toggleOn(let rhythm):
        if rhythm {
            let turningOn = !l.restartRhythmOnResolved
            l.restartRhythmOn = turningOn
            if turningOn, l.restartRhythmChainResolved.isFree { l.restartRhythmBars = [1] }   // turning on an empty chain also appends a 1
        } else {
            let turningOn = !l.restartMelodyOnResolved
            l.restartMelodyOn = turningOn
            if turningOn, l.restartMelodyChainResolved.isFree { l.restartMelodyPasses = [1] }
        }
    case .withRhythm:
        l.restartMelodyWithRhythm = !l.restartMelodyWithRhythmResolved
    case .tapLink(let rhythm, let slot):
        let hit = !rhythm && l.restartMelodyUnitResolved == .hit
        var links = (rhythm ? l.restartRhythmChainResolved : l.restartMelodyChainResolved).links
        guard slot >= 0, slot < links.count else { return }
        let ladder = euclideousRestartLinkLadder(hit: hit)
        if let i = ladder.firstIndex(of: links[slot]) { links[slot] = ladder[(i + 1) % ladder.count] }   // §3: wrap 8 → 1, never remove
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
        turnChainLive(&l, rhythm: rhythm)   // §3: a tap on a FREE row's kept link wakes it
    case .setLink(let rhythm, let slot, let value):
        let hit = !rhythm && l.restartMelodyUnitResolved == .hit
        var links = (rhythm ? l.restartRhythmChainResolved : l.restartMelodyChainResolved).links
        guard slot >= 0, slot < links.count else { return }
        let ladder = euclideousRestartLinkLadder(hit: hit)
        let snapped = ladder.contains(UInt8(clamping: max(0, value))) ? UInt8(clamping: value) : (ladder.min(by: { abs(Int($0) - value) < abs(Int($1) - value) }) ?? links[slot])
        guard snapped != links[slot] else { return }
        links[slot] = snapped
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
        turnChainLive(&l, rhythm: rhythm)
    case .addLink(let rhythm):
        var links = (rhythm ? l.restartRhythmChainResolved : l.restartMelodyChainResolved).links
        guard links.count < 4 else { return }
        links.append(1)
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
        turnChainLive(&l, rhythm: rhythm)   // §3: + on a FREE row wakes it
    case .removeLink(let rhythm, let slot):
        var links = (rhythm ? l.restartRhythmChainResolved : l.restartMelodyChainResolved).links
        guard slot >= 0, slot < links.count, links.count > 1 else { return }   // §3: never remove the only link
        fixSwitch(&l, rhythm: rhythm)   // a removal must not reactivate a switched-off chain
        links.remove(at: slot)          // at least one link always remains (the count > 1 guard)
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
    }
}

// MARK: - the 16-cell timeline (§7.4 row 3)

struct EuclideousRestartTimelineCell: Equatable {
    var isMark: Bool
    /// true = the source colour at 34 %, false = 16 % (a run between restarts; the window's first cell starts high, the shade switches at each later mark). §2.2 brightened these from 26 % / 12 %.
    var shadeHigh: Bool
}
struct EuclideousRestartTimeline: Equatable {
    var windowStart: Int                 // the first unit of the 16-unit window, counted from 0
    var axisLabel: String                // §2.2: the UNIT only — "BAR" / "PASS" / "RIFF" / "HIT" (the window range is spoken, not drawn)
    var cells: [EuclideousRestartTimelineCell]
    /// The cell holding the current unit (nil when it is outside the window — it never is, the window is chosen to hold it).
    var currentCell: Int?
    var active: Bool
    /// The static VoiceOver text.
    var spoken: String
}
/// The window holding unit `current` (counted from 0), the cells (marks at the chain's running totals, cycling), the axis label and the spoken marks. An inactive chain draws every cell flat and speaks "No restarts".
func euclideousRestartTimeline(chain: EuclideousRestartChain, active: Bool, unitWord: String, current: Int, rhythm: Bool) -> EuclideousRestartTimeline {
    let cur = max(0, current)
    let w = (cur / 16) * 16
    let total = max(1, chain.total)
    var cells: [EuclideousRestartTimelineCell] = []
    var high = true
    var marks: [Int] = []
    for i in 0..<16 {
        let u = w + i
        let r = ((u % total) + total) % total
        let isMark = active && (0..<chain.count).contains { chain.runningTotal($0) == r }
        if isMark, i > 0 { high.toggle() }
        cells.append(EuclideousRestartTimelineCell(isMark: isMark, shadeHigh: high))
        if isMark { marks.append(u + 1) }
    }
    let unit = unitWord.uppercased()
    let label = unit                                                // §2.2: the unit only; the window range lives in `spoken`
    var spoken = "No restarts"
    if active, !marks.isEmpty {
        let plural = unitWord == "pass" ? "passes" : unitWord + "s"
        spoken = "\(rhythm ? "Rhythm" : "Melody") restarts at \(plural) " + marks.prefix(4).map { String($0) }.joined(separator: ", ") + (marks.count > 4 ? ", …" : "")
    }
    return EuclideousRestartTimeline(windowStart: w, axisLabel: label, cells: cells, currentCell: cur - w, active: active, spoken: spoken)
}

/// §7.4: the current unit, from the schedule's lane data at beat `beat`. BAR: the bar holding it; PASS: the source lane's pass index; RIFF: the source lane's riff completions before it (both kinds); HIT: the lane's hits played up to now,
/// minus one, never below 0 (cell k is hit k + 1: a mark on cell k is the hit that restarts with k hits played before it). `set` nil (no schedule yet) reads 0.
func euclideousRestartCurrentUnit(rhythm: Bool, settings s: EuclideousRestartSettings, ownLane: Int, beat: Double, barBeats: Double, set: EuclideousRestartScheduleSet?) -> Int {
    let unit = rhythm ? s.rhythmUnit.rawValue : s.melodyUnit.rawValue
    let source = rhythm ? s.rhythmSource : s.melodySource
    switch unit {
    case "BAR": return max(0, Int(((beat + 1e-9) / max(1e-9, barBeats)).rounded(.down)))
    case "PASS": return Int(max(0, set?.lane(source)?.passIndex(beat: beat) ?? 0))
    case "RIFF": return Int(max(0, set?.lane(source)?.riffCompletions(before: beat + 1e-9) ?? 0))
    default:
        guard let lane = set?.lane(max(0, min(3, ownLane))) else { return 0 }
        let tick = Int64((beat / lane.data.sub).rounded(.down))
        return Int(max(0, lane.hitsBefore(tick: tick + 1) - 1))
    }
}

// MARK: - VoiceOver (§9.2)

enum EuclideousRestartEditorAX {
    static func dialog(lane: Int) -> String { "Restarts for lane \(lane + 1)" }
    static let rhythmGroup = "Rhythm restarts", melodyGroup = "Melody restarts"
    static let close = "Close restarts"
    static func unitChip(rhythm: Bool, index: Int) -> String {
        let words = rhythm ? ["passes", "bars", "riffs"] : ["hits", "passes", "bars"]   // §2.2 order
        return "Count \(words[max(0, min(2, index))])"
    }
    static func source(square: Int, unavailable: Bool) -> String { "Lane \(square + 1)" + (unavailable ? ", unavailable" : "") }
    /// §5: the FREE pill — "Rhythm free, on" when the chain is inactive (the pill lit). A toggle: tapping turns the chain on / off.
    static func freePill(rhythm: Bool, free: Bool) -> String { "\(rhythm ? "Rhythm" : "Melody") free, \(free ? "on" : "off")" }
    /// §5: the link-row button — "Melody restarts with the rhythm, on".
    static func withRhythm(on: Bool) -> String { "Melody restarts with the rhythm, \(on ? "on" : "off")" }
    static func link(rhythm: Bool, slot: Int, value: Int, unitWord: String) -> String {
        let plural = value == 1 ? unitWord : (unitWord == "pass" ? "passes" : unitWord + "s")
        return "\(rhythm ? "Rhythm" : "Melody") link \(slot + 1), \(value) \(plural)"
    }
    static let linkHint = "Double-tap for the next length"
    static let removeLink = "Remove link"
    static func addLink(rhythm: Bool) -> String { "Add a \(rhythm ? "rhythm" : "melody") link" }
    static let tileHint = "Double-tap to edit"
}
