//  PlayAsRowsUI.swift — PLAY AS ROWS ferry (2026-11-11): the NOTES tab's layout (§5, §6) and the pop-up tile pictures (§7), as PURE functions of the content size. The tab is seven rows — RANKS · WHEN RIFF · ORDER · VOICES · SPREAD ·
//  BASS · EMIT+OCT — 28 tall, sp6 apart (§5.2: 7×28 + 6×6 = 232 ≤ the 233 content area, so they fit at both references). The × mode (§6.5) grows the RANKS row to tiles + 2ND + 3RD (92) and pushes the rows below past the card's bottom,
//  where they are hidden, not compressed. Frames are in the tab's content coordinates; the views draw the row content (labels, chips, tiles) inside these frames. Testable in FourfoldTests (Foundation + CoreGraphics only).

import CoreGraphics

// Amendment 1 (2026-11-13) §A10: seven rows — RANKS · WHEN RIFF · ORDER · VOICES · SPREAD · BASS · EMIT+OCT — 28 tall, 5 apart (7×28 + 6×5 = 226 ≤ the ≈229 content area), label column 55. The × mode is gone (§A2.4): the RANKS row is
// just the eight tiles + a REPEAT button, and counts/timings are edited in the REPEAT pop-up (§A3), so no row ever grows the card or is hidden. Frames are in the tab's content coordinates.
struct EuclideousPlayAsRowsLayout: Equatable {
    static let rowH: CGFloat = 28, gap: CGFloat = 5, subGap: CGFloat = 4
    static let labelW: CGFloat = 55, chanceW: CGFloat = 88
    static let tile: CGFloat = 26, tileGap: CGFloat = 3          // §A2.2: 26 pt tiles, 3 apart
    static let repeatW: CGFloat = 56                             // §A2.5: the RANKS row's REPEAT button (right-aligned)
    static let bassSwitchW: CGFloat = 30, bassPillW: CGFloat = 44

    var content: CGRect = .zero
    var ranks: CGRect = .zero                       // the RANKS row
    var rankLabel: CGRect = .zero                   // §A2.1: the RANKS label in the label column
    var rankTiles: [CGRect] = []                    // the eight 1…8 tiles (after the label)
    var repeatButton: CGRect = .zero                // §A2.5
    var whenRow: CGRect = .zero, orderRow: CGRect = .zero, voicesRow: CGRect = .zero, spreadRow: CGRect = .zero, bassRow: CGRect = .zero, emitRow: CGRect = .zero
    var fits: Bool = true

    /// A row's label column (the leading `labelW`) in its own coordinates offset by the row's origin.
    static func labelFrame(_ row: CGRect) -> CGRect { CGRect(x: row.minX, y: row.minY, width: labelW, height: row.height) }
    /// The control area after the label.
    static func controlFrame(_ row: CGRect, trailingInset: CGFloat = 0) -> CGRect {
        CGRect(x: row.minX + labelW + subGap, y: row.minY, width: max(1, row.width - labelW - subGap - trailingInset), height: row.height)
    }
}

/// §A10: the NOTES tab's seven row frames. No × mode (Amendment 1 §A2.4), so nothing is hidden and every row is present. `fits` is false only if the seven rows overflow `contentAreaH` (the page scales rather than reflows, so at
/// the reference they fit; the flag is for reporting).
func euclideousPlayAsRowsLayout(contentAreaH: CGFloat, fullWidth: CGFloat) -> EuclideousPlayAsRowsLayout {
    typealias L = EuclideousPlayAsRowsLayout
    let w = max(1, fullWidth)
    var out = EuclideousPlayAsRowsLayout(content: CGRect(x: 0, y: 0, width: w, height: contentAreaH))

    // RANKS row: the label, eight 26 pt tiles, then REPEAT right-aligned. The tiles (and REPEAT) are centred in the 28 pt row.
    out.ranks = CGRect(x: 0, y: 0, width: w, height: L.rowH)
    out.rankLabel = CGRect(x: 0, y: 0, width: L.labelW, height: L.rowH)
    let tilesX = L.labelW + L.subGap
    let tileY = (L.rowH - L.tile) / 2
    var tiles: [CGRect] = []
    for i in 0..<8 { tiles.append(CGRect(x: tilesX + CGFloat(i) * (L.tile + L.tileGap), y: tileY, width: L.tile, height: L.tile)) }
    out.rankTiles = tiles
    out.repeatButton = CGRect(x: w - L.repeatW, y: tileY, width: L.repeatW, height: L.tile)

    // The six rows below, 28 tall, 5 apart.
    var y: CGFloat = L.rowH
    func nextRow() -> CGRect { y += L.gap; let r = CGRect(x: 0, y: y, width: w, height: L.rowH); y += L.rowH; return r }
    out.whenRow = nextRow(); out.orderRow = nextRow(); out.voicesRow = nextRow()
    out.spreadRow = nextRow(); out.bassRow = nextRow(); out.emitRow = nextRow()
    out.fits = (7 * L.rowH + 6 * L.gap) <= contentAreaH + 0.5
    return out
}

// MARK: - Amendment 1 §A3 — the REPEAT pop-up's grid (card-body scoped)

/// §A3.2: the REPEAT pop-up grid — a label column (`labelW`) then eight equal rank columns 4 apart, each cell `cellH` tall. The pop-up body is `bodyW × bodyH` (the card's tab-body size less the pop-up's own 6 pt inset + title + PASS
/// band). Rows top→bottom: header (rank numbers), ×, 2ND, 3RD. The frames are in the grid's own coordinates (the view offsets the whole grid below the title). `pass`/`passLabel` is the §A3.3 PASS band under a divider.
struct EuclideousRepeatPopupLayout: Equatable {
    static let labelW: CGFloat = 48, colGap: CGFloat = 4, cellH: CGFloat = 32, rowGap: CGFloat = 4
    static let titleH: CGFloat = 30, passH: CGFloat = 26, dividerGap: CGFloat = 8
    var gridLabel: [CGRect] = []       // the four row labels (header has none → index 0 unused/zero)
    var cells: [[CGRect]] = []         // [row 0…3][rank 0…7]; row 0 header, 1 ×, 2 second, 3 third
    var passLabel: CGRect = .zero
    var passArea: CGRect = .zero
    var divider: CGRect = .zero
}

func euclideousRepeatPopupLayout(bodyW: CGFloat, bodyH: CGFloat) -> EuclideousRepeatPopupLayout {
    typealias R = EuclideousRepeatPopupLayout
    var out = EuclideousRepeatPopupLayout()
    let w = max(1, bodyW)
    let colsX = R.labelW + R.colGap
    let colW = max(1, (w - colsX - 7 * R.colGap) / 8)
    var y = R.titleH
    for row in 0..<4 {
        var rowCells: [CGRect] = []
        for c in 0..<8 { rowCells.append(CGRect(x: colsX + CGFloat(c) * (colW + R.colGap), y: y, width: colW, height: R.cellH)) }
        out.cells.append(rowCells)
        out.gridLabel.append(CGRect(x: 0, y: y, width: R.labelW, height: R.cellH))
        y += R.cellH + R.rowGap
    }
    out.divider = CGRect(x: 0, y: y + R.dividerGap / 2, width: w, height: 1)
    let passY = y + R.dividerGap
    out.passLabel = CGRect(x: 0, y: passY, width: R.labelW, height: R.passH)
    out.passArea = CGRect(x: colsX, y: passY, width: max(1, w - colsX), height: R.passH)
    return out
}

/// §A3.2: which REPEAT-grid cells are LIVE (editable). The header is always shown; a × cell is live iff its rank is lit; a 2ND/3RD cell is live iff the rank is lit AND its count is at least 2 / 3. A dead cell draws #131518 and ignores
/// taps (test 4). `row`: 0 header, 1 ×, 2 second, 3 third.
func euclideousRepeatCellLive(litOrder: EuclideousLitOrder, counts: UInt16, rank: Int, row: Int) -> Bool {
    guard rank >= 1, rank <= 8 else { return false }
    if row == 0 { return true }                                   // the header (rank number) is shown for every rank; lit/unlit is only its colour
    guard litOrder.contains(rank - 1) else { return false }       // the ×/2ND/3RD cells are dead for an unlit rank
    let cnt = min(3, Int((counts >> UInt16(2 * (rank - 1))) & 0b11) + 1)
    switch row {
    case 1: return true          // × (count) — any lit rank
    case 2: return cnt >= 2
    case 3: return cnt >= 3
    default: return false
    }
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

/// §A4.1 / §A1.3: a chip wears the 1 pt lane outline only when it is the chip playing now (and the transport runs). `activeChip` comes from `euclideousRowsActiveChip` on the live hit ordinal.
func euclideousNotesChipOutlined(chipIndex: Int, activeChip: Int, playing: Bool) -> Bool { playing && chipIndex == activeChip }

/// §A9: the ONE opacity of the NOTES tab body — PLAY STACK off is 42 % and never stacks with another dim (§A9.2); if only ANSWER-pause applies it keeps its own `shadowDim`; otherwise full. The PLAY buttons live outside the body and never dim.
func euclideousNotesTabBodyOpacity(notesOn: Bool, shadowing: Bool, shadowDim: Double) -> Double {
    if !notesOn { return 0.42 }
    if shadowing { return shadowDim }
    return 1.0
}
