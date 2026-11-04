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
    /// MELODY only: the link glyph (WITH RHYTHM on).
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
    return EuclideousRestartTileSpec(isSet: active || withRhythm, valueText: value, unitText: unit, sourceLane: src, showsLinkGlyph: withRhythm, fillLane: src ?? own)
}

/// §6.2's fit rule, from the page's own type: monospaced heavy glyphs are ≈ 0.6 em wide plus tracking. The right-hand group is (link glyph 10) + (source square 7) + value (13 pt) + unit (8 pt, tracked 0.08 em), sp3 apart; the name is
/// the arrow (8) + 3 + "<NAME> RESTART" (8 pt, tracked 0.1 em). Drop the unit first, then truncate the name; never shrink.
struct EuclideousRestartTileFit: Equatable {
    var showsUnit: Bool
    var nameTruncates: Bool
    var groupWidth: CGFloat
    var nameWidth: CGFloat
}
func euclideousRestartTileFit(spec: EuclideousRestartTileSpec, name: String, tileWidth: CGFloat) -> EuclideousRestartTileFit {
    func mono(_ s: String, size: CGFloat, tracking: CGFloat) -> CGFloat { CGFloat(s.count) * (0.6 * size + tracking) }
    let avail = max(0, tileWidth - 20)                       // 10 pt either side
    let nameW = 8 + 3 + mono("\(name) RESTART", size: 8, tracking: 0.8)
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

enum EuclideousRestartEditorMetricsV2 {
    static let pad: CGFloat = 8
    static let headerTop: CGFloat = 8, headerH: CGFloat = 20
    static let sectionH: CGFloat = 78, sectionHNoTimeline: CGFloat = 60, sectionGap: CGFloat = 8
    static let referenceHeight: CGFloat = 208, compactHeight: CGFloat = 172
    static let labelX: CGFloat = 8, labelW: CGFloat = 56, blockX: CGFloat = 68
    static let row1H: CGFloat = 24, row2Top: CGFloat = 28, row2H: CGFloat = 32, row3Top: CGFloat = 64, row3H: CGFloat = 14
    static let chipW: CGFloat = 40, chipGap: CGFloat = 4
    static let sourceHitW: CGFloat = 18, sourceHitGap: CGFloat = 4, sourceGlyph: CGFloat = 12
    static let switchW: CGFloat = 34, switchH: CGFloat = 20, switchHitH: CGFloat = 24
    static let slotGap: CGFloat = 4, withRhythmW: CGFloat = 52, withRhythmH: CGFloat = 32, withRhythmX: CGFloat = 12
    static let cellGap: CGFloat = 2, cellH: CGFloat = 14, cellCount = 16
    /// The gap between the source squares and the switch at the reference (288 → 296.5).
    static let sourcesToSwitchGap: CGFloat = 8.5
}
struct EuclideousRestartSectionFramesV2: Equatable {
    var top: CGFloat
    var labelColumn: CGRect                 // row 1 label (the name), editor coordinates
    var chips: [CGRect]                     // 3
    var sources: [CGRect]                   // 4 hit areas (18 × 24)
    var switchTrack: CGRect                 // 34 × 20, centred in a 34 × 24 hit area
    var switchHit: CGRect
    var withRhythm: CGRect?                 // MELODY only (52 × 32)
    var slots: [CGRect]                     // 4 link slots
    var axisLabel: CGRect?                  // nil when the timeline is dropped
    var cells: [CGRect]                     // 16 timeline cells (empty when dropped)
}
struct EuclideousRestartEditorFramesV2: Equatable {
    var size: CGSize
    var header: CGRect
    var rhythm: EuclideousRestartSectionFramesV2
    var melody: EuclideousRestartSectionFramesV2
    var showsTimelines: Bool
    /// The right block's width (x 68 to the content's trailing edge): 262.5 at the reference.
    var rightWidth: CGFloat
    /// §7.6: does row 1 fit (the three chips, the four source squares and the switch need 262 pt)? Reported by the page's floors; nothing shrinks.
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
    let rhythmTop = M.headerTop + M.headerH + M.sectionGap + slack / 2
    let melodyTop = rhythmTop + sectionH + M.sectionGap + slack / 2
    func section(top: CGFloat, melody: Bool) -> EuclideousRestartSectionFramesV2 {
        let chips = (0..<3).map { CGRect(x: M.blockX + CGFloat($0) * (M.chipW + M.chipGap), y: top, width: M.chipW, height: M.row1H) }
        let switchX = contentRight - M.switchW
        let sources = (0..<4).map { i in CGRect(x: switchX - M.sourcesToSwitchGap - (4 * M.sourceHitW + 3 * M.sourceHitGap) + CGFloat(i) * (M.sourceHitW + M.sourceHitGap), y: top, width: M.sourceHitW, height: M.row1H) }
        let slotW = (rw - 12) / 4
        let slots = (0..<4).map { CGRect(x: M.blockX + CGFloat($0) * (slotW + M.slotGap), y: top + M.row2Top, width: slotW, height: M.row2H) }
        let cellW = (rw - 30) / 16
        let cells: [CGRect] = timelines ? (0..<M.cellCount).map { CGRect(x: M.blockX + CGFloat($0) * (cellW + M.cellGap), y: top + M.row3Top, width: cellW, height: M.cellH) } : []
        return EuclideousRestartSectionFramesV2(
            top: top, labelColumn: CGRect(x: M.labelX, y: top, width: M.labelW, height: M.row1H), chips: chips, sources: sources,
            switchTrack: CGRect(x: switchX, y: top + (M.row1H - M.switchH) / 2, width: M.switchW, height: M.switchH), switchHit: CGRect(x: switchX, y: top + (M.row1H - M.switchHitH) / 2, width: M.switchW, height: M.switchHitH),
            withRhythm: melody ? CGRect(x: M.withRhythmX, y: top + M.row2Top, width: M.withRhythmW, height: M.withRhythmH) : nil, slots: slots,
            axisLabel: timelines ? CGRect(x: M.labelX, y: top + M.row3Top, width: M.labelW, height: M.row3H) : nil, cells: cells)
    }
    let needed = M.headerTop + M.headerH + 2 * (M.sectionGap + sectionH) + M.pad
    return EuclideousRestartEditorFramesV2(size: size, header: CGRect(x: M.pad, y: M.headerTop, width: max(0, size.width - 2 * M.pad), height: M.headerH),
                                           rhythm: section(top: rhythmTop, melody: false), melody: section(top: melodyTop, melody: true), showsTimelines: timelines, rightWidth: rw,
                                           row1Fits: rw >= 262 - 1e-9, clipsBottom: size.height < needed - 1e-9)
}

// MARK: - what a tap does (§7.4) — one undo step each

enum EuclideousRestartEdit: Equatable {
    case unit(rhythm: Bool, index: Int)       // RHYTHM chips: BAR, PASS, RIFF · MELODY chips: PASS, BAR, HIT
    case source(rhythm: Bool, lane: Int)
    case toggleOn(rhythm: Bool)
    case withRhythm
    case tapLink(rhythm: Bool, slot: Int)
    case addLink(rhythm: Bool)
}
/// Is lane `lane`'s source square unavailable (§7.4: the lane itself on RHYTHM PASS)?
func euclideousRestartSourceUnavailable(rhythm: Bool, line l: EuclidLine, ownLane: Int, square: Int) -> Bool {
    rhythm && l.restartRhythmUnitResolved == .pass && square == max(0, min(3, ownLane))
}
/// Applies one tap to a lane. `pin` is what an unpinned lane's chains resolve to (the migration) — stored first, in the same step (§3.5). Returns whether anything changed (a funnel records no step otherwise).
@discardableResult
func euclideousApplyRestartEdit(_ e: EuclideousRestartEdit, to l: inout EuclidLine, lane: Int, pin: (rhythm: EuclideousRestartChain, melody: EuclideousRestartChain)?) -> Bool {
    let before = l
    if !l.usesRestartChains, let p = pin { euclideousPinRestartChains(&l, p.rhythm, p.melody) }
    let own = max(0, min(3, lane))
    switch e {
    case .unit(let rhythm, let index):
        if rhythm {
            let units: [EuclideousRhythmRestartUnit] = [.bar, .pass, .riff]
            guard index >= 0, index < 3, l.restartRhythmUnitResolved != units[index] else { return resolved(before, l) }
            l.restartRhythmUnit = units[index]
            if units[index] == .pass, (l.restartRhythmSource.map { max(0, min(3, $0)) } ?? own) == own { l.restartRhythmSource = (own + 1) % 4 }   // PASS never counts the lane itself: the source moves to the next lane in the same step
        } else {
            let units: [EuclideousMelodyRestartUnit] = [.pass, .bar, .hit]
            guard index >= 0, index < 3, l.restartMelodyUnitResolved != units[index] else { return resolved(before, l) }
            if l.restartMelodyUnitResolved == .hit {   // leaving HIT: 5 → 6 and 7 → 8 (those values are not valid for the other units)
                l.restartMelodyPasses = l.restartMelodyPasses.map { $0.map { $0 == 5 ? 6 : ($0 == 7 ? 8 : $0) } }
            }
            l.restartMelodyUnit = units[index]
        }
    case .source(let rhythm, let square):
        guard square >= 0, square < 4, !euclideousRestartSourceUnavailable(rhythm: rhythm, line: l, ownLane: lane, square: square) else { return resolved(before, l) }
        if rhythm { guard l.restartRhythmUnitResolved.readsSource, l.restartRhythmSourceResolved(ownLane: lane) != square else { return resolved(before, l) }; l.restartRhythmSource = square }
        else { guard l.restartMelodyUnitResolved.readsSource, l.restartMelodySourceResolved(ownLane: lane) != square else { return resolved(before, l) }; l.restartMelodySource = square }
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
        guard slot >= 0, slot < links.count else { return resolved(before, l) }
        let ladder = euclideousRestartLinkLadder(hit: hit)
        if let i = ladder.firstIndex(of: links[slot]), i + 1 < ladder.count { links[slot] = ladder[i + 1] }
        else {
            links.remove(at: slot)
            if links.isEmpty { if rhythm { l.restartRhythmOn = false } else { l.restartMelodyOn = false } }   // removing the last link also turns the switch off
        }
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
    case .addLink(let rhythm):
        var links = (rhythm ? l.restartRhythmChainResolved : l.restartMelodyChainResolved).links
        guard links.count < 4 else { return resolved(before, l) }
        links.append(1)
        if rhythm { l.restartRhythmBars = links } else { l.restartMelodyPasses = links }
    }
    return resolved(before, l)
}
/// Did anything the lane RESOLVES to change? (A pin alone — nil → the same chains — is not an edit.)
private func resolved(_ a: EuclidLine, _ b: EuclidLine) -> Bool { a != b }

// MARK: - the 16-cell timeline (§7.4 row 3)

struct EuclideousRestartTimelineCell: Equatable {
    var isMark: Bool
    /// true = the source colour at 26 %, false = 12 % (a run between restarts; the window's first cell starts high, the shade switches at each later mark).
    var shadeHigh: Bool
}
struct EuclideousRestartTimeline: Equatable {
    var windowStart: Int                 // the first unit of the 16-unit window, counted from 0
    var axisLabel: String                // "BAR 1–16", "PASS 17–32", "RIFF 1–16", "HIT 33–48"
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
    let label = "\(unit) \(w + 1)\u{2013}\(w + 16)"
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
        let words = rhythm ? ["bars", "passes", "riffs"] : ["passes", "bars", "hits"]
        return "Count \(words[max(0, min(2, index))])"
    }
    static func source(square: Int, unavailable: Bool) -> String { "Lane \(square + 1)" + (unavailable ? ", unavailable" : "") }
    static func switchLabel(rhythm: Bool, on: Bool) -> String { "\(rhythm ? "Rhythm" : "Melody") restarts, \(on ? "on" : "off")" }
    static func withRhythm(on: Bool) -> String { "Restart with the rhythm, \(on ? "on" : "off")" }
    static func link(rhythm: Bool, slot: Int, value: Int, unitWord: String) -> String {
        let plural = value == 1 ? unitWord : (unitWord == "pass" ? "passes" : unitWord + "s")
        return "\(rhythm ? "Rhythm" : "Melody") link \(slot + 1), \(value) \(plural)"
    }
    static let linkHint = "Double-tap for the next length"
    static let removeLink = "Remove link"
    static func addLink(rhythm: Bool) -> String { "Add a \(rhythm ? "rhythm" : "melody") link" }
    static let tileHint = "Double-tap to edit"
}
