//  PlayAsRowsUI.swift — PLAY AS ROWS ferry (2026-11-11): the NOTES tab's layout (§5, §6) and the pop-up tile pictures (§7), as PURE functions of the content size. The tab is seven rows — RANKS · WHEN RIFF · ORDER · VOICES · SPREAD ·
//  BASS · EMIT+OCT — 28 tall, sp6 apart (§5.2: 7×28 + 6×6 = 232 ≤ the 233 content area, so they fit at both references). The × mode (§6.5) grows the RANKS row to tiles + 2ND + 3RD (92) and pushes the rows below past the card's bottom,
//  where they are hidden, not compressed. Frames are in the tab's content coordinates; the views draw the row content (labels, chips, tiles) inside these frames. Testable in FourfoldTests (Foundation + CoreGraphics only).

import CoreGraphics

struct EuclideousPlayAsRowsLayout: Equatable {
    static let rowH: CGFloat = 28, gap: CGFloat = 6, subGap: CGFloat = 4
    static let labelW: CGFloat = 48, chanceW: CGFloat = 88
    static let tile: CGFloat = 28, tileGap: CGFloat = 4, xGap: CGFloat = 8
    static let shiftW: CGFloat = 64, bassSwitchW: CGFloat = 30, bassPillW: CGFloat = 44

    var content: CGRect = .zero
    var ranks: CGRect = .zero                       // the RANKS tiles row (not counting 2ND/3RD)
    var rankTiles: [CGRect] = []                    // the eight 1…8 tiles (content coords)
    var xButton: CGRect = .zero
    var secondRow: CGRect?, thirdRow: CGRect?       // the 2ND / 3RD rows, present only while × is on
    var secondCells: [CGRect] = [], thirdCells: [CGRect] = []
    var secondLabel: CGRect = .zero, thirdLabel: CGRect = .zero
    // the six rows below RANKS; nil if hidden (pushed past the card's bottom in × mode)
    var whenRow: CGRect?, orderRow: CGRect?, voicesRow: CGRect?, spreadRow: CGRect?, bassRow: CGRect?, emitRow: CGRect?
    var fits: Bool = true
    var hidden: [String] = []                       // the names of the rows hidden in × mode (§6.5 reporting)

    /// A row's label column (the leading `labelW`) in its own coordinates offset by the row's origin.
    static func labelFrame(_ row: CGRect) -> CGRect { CGRect(x: row.minX, y: row.minY, width: labelW, height: row.height) }
    /// The control area after the label.
    static func controlFrame(_ row: CGRect, trailingInset: CGFloat = 0) -> CGRect {
        CGRect(x: row.minX + labelW + subGap, y: row.minY, width: max(1, row.width - labelW - subGap - trailingInset), height: row.height)
    }
}

/// §5.2 / §6: the NOTES tab's row frames. `cross` is the RANKS row's × (count-edit) mode. A row pushed past `contentAreaH` is dropped (its frame is nil) and named in `hidden` (§6.5). `fits` is false when the normal (× off) rows
/// overflow — the caller then scrolls them (the INPUTS fallback); in × mode the overflow is clipped by design, so `fits` ignores the 2ND/3RD expansion.
func euclideousPlayAsRowsLayout(contentAreaH: CGFloat, fullWidth: CGFloat, cross: Bool) -> EuclideousPlayAsRowsLayout {
    typealias L = EuclideousPlayAsRowsLayout
    let w = max(1, fullWidth)
    var out = EuclideousPlayAsRowsLayout(content: CGRect(x: 0, y: 0, width: w, height: contentAreaH))

    // RANKS row: eight tiles from x0, then the × button sp8 after them.
    out.ranks = CGRect(x: 0, y: 0, width: w, height: L.rowH)
    var tiles: [CGRect] = []
    for i in 0..<8 { tiles.append(CGRect(x: CGFloat(i) * (L.tile + L.tileGap), y: 0, width: L.tile, height: L.tile)) }
    out.rankTiles = tiles
    let tilesRight = 8 * L.tile + 7 * L.tileGap
    out.xButton = CGRect(x: tilesRight + L.xGap, y: 0, width: L.tile, height: L.tile)

    var y: CGFloat = L.rowH   // the bottom of the RANKS tiles

    if cross {
        // §6.5: 2ND then 3RD, eight cells each, lined up with the tiles; the label sits in the × column.
        let y2 = y + L.subGap
        out.secondRow = CGRect(x: 0, y: y2, width: w, height: L.rowH)
        out.secondCells = tiles.map { CGRect(x: $0.minX, y: y2, width: L.tile, height: L.tile) }
        out.secondLabel = CGRect(x: out.xButton.minX, y: y2, width: L.tile + 8, height: L.rowH)
        let y3 = y2 + L.rowH + L.subGap
        out.thirdRow = CGRect(x: 0, y: y3, width: w, height: L.rowH)
        out.thirdCells = tiles.map { CGRect(x: $0.minX, y: y3, width: L.tile, height: L.tile) }
        out.thirdLabel = CGRect(x: out.xButton.minX, y: y3, width: L.tile + 8, height: L.rowH)
        y = y3 + L.rowH
    }

    // The six rows below, in order. In × mode they start after the (taller) RANKS block; a row whose top is at or past the content bottom is hidden.
    let names = ["WHEN RIFF", "ORDER", "VOICES", "SPREAD", "BASS", "EMIT"]
    var frames: [CGRect?] = []
    for n in names {
        y += L.gap
        if y >= contentAreaH { frames.append(nil); out.hidden.append(n); y += L.rowH; continue }
        frames.append(CGRect(x: 0, y: y, width: w, height: L.rowH))
        y += L.rowH
    }
    out.whenRow = frames[0]; out.orderRow = frames[1]; out.voicesRow = frames[2]
    out.spreadRow = frames[3]; out.bassRow = frames[4]; out.emitRow = frames[5]
    // fits is about the NORMAL layout (× off): the seven rows' total vs the content area.
    let normalTotal = 7 * L.rowH + 6 * L.gap
    out.fits = normalTotal <= contentAreaH + 0.5
    return out
}

// MARK: - §7 the row pop-ups' tile pictures (no numbers on any picture)

/// §7.1: the ORDER pop-up's tiles, in order (four columns: UP, DOWN, BOUNCE, SHUFFLE, OUTSIDE IN, INSIDE OUT, AS ADDED).
let euclideousOrderTileOrder: [EuclideousOrderMode] = [.up, .down, .bounce, .shuffle, .outsideIn, .insideOut, .asAdded]
/// §7.1: a tile's picture — dots on four faint lines (the bottom line lowest = level 1), at these levels left to right. The view places dot i at x = (i + 0.5) / count, y from `level` (1 = bottom, 4 = top).
func euclideousOrderTileLevels(_ m: EuclideousOrderMode) -> [Int] {
    switch m {
    case .up:        return [1, 2, 3, 4, 1, 2]
    case .down:      return [4, 3, 2, 1, 4, 3]
    case .bounce:    return [1, 2, 3, 4, 3, 2]
    case .shuffle:   return [3, 1, 4, 2, 4, 1]
    case .outsideIn: return [1, 4, 2, 3, 1, 4]
    case .insideOut: return [3, 2, 4, 1, 3, 2]
    case .asAdded:   return [2, 4, 1, 3]
    }
}
/// §7.2: the VOICES pop-up's tiles, in order (1, 2, 3, ALL, GROW).
let euclideousVoicesTileOrder: [EuclideousVoicesMode] = [.one, .two, .three, .all, .grow]
/// §7.2: a tile's picture as columns, each a stack of four dots with the lowest `n` lit (so the view draws four dots per column and fills the bottom `n`). 1/2/3/ALL are one column lit 1/2/3/4; GROW is four columns lit 1, 2, 3, 4.
func euclideousVoicesTileColumns(_ m: EuclideousVoicesMode) -> [Int] {
    switch m {
    case .one:   return [1]
    case .two:   return [2]
    case .three: return [3]
    case .all:   return [4]
    case .grow:  return [1, 2, 3, 4]
    }
}
/// §7.3: the SPREAD pop-up's tiles, in order (TOGETHER, STRUM, RUN).
let euclideousSpreadTileOrder: [EuclideousSpreadMode] = [.together, .strum, .run]
/// §7.3: three dots' (x, y) positions in the unit square (x left→right = time, y top). TOGETHER stacks them on one beat (x 0.5), STRUM steps each a little later, RUN spreads them across the tile.
func euclideousSpreadTileDots(_ m: EuclideousSpreadMode) -> [(x: Double, y: Double)] {
    switch m {
    case .together: return [(0.5, 0.25), (0.5, 0.5), (0.5, 0.75)]
    case .strum:    return [(0.35, 0.25), (0.5, 0.5), (0.65, 0.75)]
    case .run:      return [(0.2, 0.5), (0.5, 0.5), (0.8, 0.5)]
    }
}

// MARK: - §9 VoiceOver / value text

func euclideousOrderModeName(_ m: EuclideousOrderMode) -> String { m.rawValue }
func euclideousVoicesModeName(_ m: EuclideousVoicesMode) -> String { m == .one ? "1" : m == .two ? "2" : m == .three ? "3" : m.rawValue }
func euclideousSpreadModeName(_ m: EuclideousSpreadMode) -> String { m.rawValue }
/// §5.4: the SHIFT button's value text — the start, or (with drift on) start and step ("1 · +1").
func euclideousShiftValueText(start: Int, driftOn: Bool, step: Int) -> String { driftOn ? "\(start) · \(step >= 0 ? "+" : "")\(step)" : "\(start)" }

// MARK: - Amendment 1 (2026-11-13) §A1 — the ONE selection colour rule (the whole NOTES tab + its pop-ups)

/// §A1: a selected control's FILL — either the lane accent (A1.1) or a fixed hex (A1.2/A1.4). The lane colour is applied at draw time; the pure rule only says WHICH.
enum EuclideousNotesSelFill: Equatable { case lane; case hex(UInt32) }

/// §A1: fill + label colour + the lane-colour outline for any control on the NOTES tab, from (selected, switched on, playing). The one rule §A1.5 demands every control use.
struct EuclideousNotesSelLook: Equatable {
    var fill: EuclideousNotesSelFill
    var labelHex: UInt32
    var laneOutline: Bool   // §A1.3: the 1 pt lane-colour outline — only the control playing now (callers pass playing only for that one)
}

/// §A1.1-§A1.5: ONE function. Selected + on ⇒ lane fill, #1B1D22 ink (A1.1). Selected + off ⇒ #33363D, #AAB0BA (A1.4, "idle-selected" — e.g. BASS's chosen mode while its switch is off). Unselected ⇒ #24262C, #8D939D (A1.2);
/// a segment control draws "no fill" over its #24262C container, which is identical. The lane outline is drawn only when `playing` (A1.3).
func euclideousNotesSelLook(selected: Bool, switchedOn: Bool, playing: Bool) -> EuclideousNotesSelLook {
    let look: EuclideousNotesSelLook
    if selected && switchedOn {
        look = EuclideousNotesSelLook(fill: .lane, labelHex: 0x1B1D22, laneOutline: playing)          // A1.1
    } else if selected {
        look = EuclideousNotesSelLook(fill: .hex(0x33363D), labelHex: 0xAAB0BA, laneOutline: playing) // A1.4 idle-selected
    } else {
        look = EuclideousNotesSelLook(fill: .hex(0x24262C), labelHex: 0x8D939D, laneOutline: playing) // A1.2
    }
    return look
}

// MARK: - Amendment 1 §A3.3 — the REPEAT pop-up's PASS row (what the current ORDER chip will play)

/// §A3.3: the pass of ranks the current ORDER chip plays, BEFORE SHIFT — exactly the §2 builder (`euclideousRowsBuildPass`) with shift/drift off. The PASS row draws one chip per entry, with a centred dot at each round break
/// (`euclideousRowsRoundBreaks`). `passIndex` only matters for SHUFFLE (a fresh per-pass permutation); non-SHUFFLE is static, so the caller passes 0 while stopped and the live pass index while playing a SHUFFLE chip.
func euclideousRowsDisplayPass(litOrder: EuclideousLitOrder, bassOn: Bool, order: EuclideousOrderMode,
                               counts: UInt16, secondLater: UInt8, thirdLater: UInt8, lane: Int, passIndex: Int) -> EuclideousRowsPass {
    let rip = euclideousRowsRanksInPlay(litOrder: litOrder, bassOn: bassOn)
    return euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, counts: counts, secondLater: secondLater, thirdLater: thirdLater,
                                   passIndex: passIndex, lane: lane, shiftStart: 0, driftOn: false, driftStep: 0)
}

/// §A3.3: the indices into the display pass where a round boundary falls (a centred dot goes there). Round sizes follow the §2.3 layout (copy 1 → round 1; copy 2/3 → round 1/2/3 per the AGAIN/LATER bits), independent of SHIFT and
/// of the ORDER key (so no `passIndex`). BOUNCE mirrors the whole pass (§2.4), which makes "rounds" meaningless, so it returns no breaks.
func euclideousRowsRoundBreaks(litOrder: EuclideousLitOrder, bassOn: Bool, order: EuclideousOrderMode,
                               counts: UInt16, secondLater: UInt8, thirdLater: UInt8) -> [Int] {
    guard order != .bounce else { return [] }
    let rip = euclideousRowsRanksInPlay(litOrder: litOrder, bassOn: bassOn)
    func cnt(_ r: Int) -> Int { min(3, Int((counts >> UInt16(2 * (r - 1))) & 0b11) + 1) }
    func roundOfCopy2(_ r: Int) -> Int { (secondLater >> UInt8(r - 1)) & 1 != 0 ? 2 : 1 }
    func roundOfCopy3(_ r: Int) -> Int { roundOfCopy2(r) + ((thirdLater >> UInt8(r - 1)) & 1 != 0 ? 1 : 0) }
    var sizes = [0, 0, 0]
    // the ranks in play are asc ∪ added (both drop the bass rank); iterate asc (it holds every one, each once).
    for i in 0..<rip.asc.count {
        let r = rip.asc[i]; let c = cnt(r)
        sizes[0] += 1
        if c >= 2 { sizes[roundOfCopy2(r) - 1] += 1 }
        if c >= 3 { sizes[roundOfCopy3(r) - 1] += 1 }
    }
    var breaks: [Int] = []
    if sizes[1] > 0 { breaks.append(sizes[0]) }
    if sizes[2] > 0 { breaks.append(sizes[0] + sizes[1]) }
    return breaks
}

// MARK: - Amendment 1 §A6 — the SHIFT badge

/// §A6.2: the SHIFT badge shows only while start ≠ 0 or drift is on; otherwise the ORDER row's right end is empty. Its text is "SHIFT " + `euclideousShiftValueText`.
func euclideousShiftBadgeShown(start: Int, driftOn: Bool) -> Bool { start != 0 || driftOn }
