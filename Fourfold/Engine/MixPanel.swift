//  MixPanel.swift — MIX ROWS (2026-11-03): the pure numbers behind the MIX panel, Foundation-only so `MixPanelTests` reach all of it. Selecting MIX in the tab strip puts ONE panel where the four lane cards sit: four lane BANDS
//  (play · rhythm strip · SOLO along the top, an 8-rank pool down the left, a RIFF row and a NOTES row) and an EMITTER column (A–D) with Bézier lines from each routed row. Every frame, look, value and string the views draw comes from here (the
//  playbook's rule: ONE function for the draw code and the tests); the views in `MixPanelViews.swift` only paint it. All frames are in PANEL coordinates (origin = the lane area's top-left).
//
//  What reuses what: the strip's steps/hits come from the lane card's own plan (`euclideousStripLegs` / `EuclideousStripHit`), the pool chips from `euclideousRankChips`, the notes the rolls/lines/chips draw from `NoteRollModel` (card back §5.2,
//  now carrying each note's pool rank), the slider fields from the card backs' pad writers (`euclideousSliderCommit`, the PIN of the notes layer included). Nothing here touches the engine.

import Foundation

// MARK: - §2 layout

enum EuclideousMixRowsMetrics {
    static let emitterColumnW: CGFloat = 76, bandGap: CGFloat = 8, bandInset: CGFloat = 8
    static let leftColW: CGFloat = 60, rightX: CGFloat = 68
    static let topRowH: CGFloat = 24, soloW: CGFloat = 120, topGap: CGFloat = 6, badge: CGFloat = 24
    static let playTarget = CGSize(width: 60, height: 32), soloTarget = CGSize(width: 120, height: 36)
    static let poolTop: CGFloat = 32, riffRowTop: CGFloat = 36, partRowGap: CGFloat = 6
    static let toggleW: CGFloat = 48, sliderW: CGFloat = 62, sliderGap: CGFloat = 4, outsW: CGFloat = 120, outW: CGFloat = 30, colGap: CGFloat = 6
    static let rowChrome: CGFloat = 514      // everything in a part row but the roll: 68 + 48 + 6 + 6 + 260 + 6 + 120
    static let emitterD: CGFloat = 36, emitterX: CGFloat = 40
    static let lineBend1: CGFloat = 23, lineBend2: CGFloat = 18.5
    static let floorRoll: CGFloat = 96, floorRowH: CGFloat = 40, floorBandH: CGFloat = 120
}

enum EuclideousMixRowsFloor: Equatable, Hashable { case roll, row, band }

/// One part row's frames (panel coordinates). `sliders` are VEL, GATE, TRANS, OCT; `outButtons` A…D.
struct EuclideousMixRowFrames: Equatable {
    var frame: CGRect, toggle: CGRect, roll: CGRect
    var sliders: [CGRect]
    var outs: CGRect
    var outButtons: [CGRect]
    var centreY: CGFloat { frame.midY }
}
struct EuclideousMixBandFrames: Equatable {
    var frame: CGRect, inner: CGRect
    var play: CGRect, playTarget: CGRect
    /// The rhythm strip's frame for a lane WITHOUT the lock badge, and with it (the badge sits sp6 before SOLO and the strip ends sp6 before it).
    var strip: CGRect, stripWithBadge: CGRect
    var solo: CGRect, soloTarget: CGRect, badge: CGRect
    var pool: CGRect
    var riff: EuclideousMixRowFrames, notes: EuclideousMixRowFrames
    func row(notes isNotes: Bool) -> EuclideousMixRowFrames { isNotes ? notes : riff }
}
struct EuclideousMixRowsLayout: Equatable {
    var size: CGSize
    var bandW: CGFloat, bandH: CGFloat, innerW: CGFloat, innerH: CGFloat, rowH: CGFloat, rollW: CGFloat
    var bands: [EuclideousMixBandFrames]
    var emitterColumn: CGRect
    var emitters: [CGRect]
    /// Floors this size falls under (roll width 96, row height 40, band height 120). The panel is still drawn at the formula's values.
    var floors: [EuclideousMixRowsFloor]
}

/// §2: the whole panel from its size. Bands at x 0…W−76, four of them sp8 apart; inner coordinates start 8 in.
func euclideousMixRowsLayout(size: CGSize) -> EuclideousMixRowsLayout {
    typealias M = EuclideousMixRowsMetrics
    let bandW = size.width - M.emitterColumnW
    let bandH = (size.height - 3 * M.bandGap) / 4
    let innerW = bandW - 2 * M.bandInset, innerH = bandH - 2 * M.bandInset
    let rowH = (innerH - 42) / 2
    let rollW = innerW - M.rowChrome
    func row(inner o: CGPoint, top: CGFloat) -> EuclideousMixRowFrames {
        let y = o.y + top
        let frame = CGRect(x: o.x + M.rightX, y: y, width: innerW - M.rightX, height: rowH)
        let toggle = CGRect(x: frame.minX, y: y, width: M.toggleW, height: rowH)
        let roll = CGRect(x: toggle.maxX + M.colGap, y: y, width: max(0, rollW), height: rowH)   // a panel too narrow for a roll (a floor flag) draws it empty, never with a negative width; everything after it stays at the formula's x
        var sliders: [CGRect] = []
        var x = toggle.maxX + M.colGap + rollW + M.colGap   // from the formula's roll width, not the clamped one
        for _ in 0..<4 { sliders.append(CGRect(x: x, y: y, width: M.sliderW, height: rowH)); x += M.sliderW + M.sliderGap }
        let outs = CGRect(x: sliders[3].maxX + M.colGap, y: y, width: M.outsW, height: rowH)
        let buttons = (0..<4).map { CGRect(x: outs.minX + CGFloat($0) * M.outW, y: y, width: M.outW, height: rowH) }
        return EuclideousMixRowFrames(frame: frame, toggle: toggle, roll: roll, sliders: sliders, outs: outs, outButtons: buttons)
    }
    var bands: [EuclideousMixBandFrames] = []
    for n in 0..<4 {
        let frame = CGRect(x: 0, y: CGFloat(n) * (bandH + M.bandGap), width: bandW, height: bandH)
        let o = CGPoint(x: frame.minX + M.bandInset, y: frame.minY + M.bandInset)
        let inner = CGRect(x: o.x, y: o.y, width: innerW, height: innerH)
        let soloX = o.x + innerW - M.soloW
        let badge = CGRect(x: soloX - M.topGap - M.badge, y: o.y, width: M.badge, height: M.topRowH)
        let stripX = o.x + M.rightX
        let strip = CGRect(x: stripX, y: o.y, width: max(0, soloX - M.topGap - stripX), height: M.topRowH)   // a panel too narrow for a strip (the floor list says so) draws it empty, never with a negative width
        let stripWithBadge = CGRect(x: stripX, y: o.y, width: max(0, badge.minX - M.topGap - stripX), height: M.topRowH)
        let play = CGRect(x: o.x, y: o.y, width: M.leftColW, height: M.topRowH)
        let playTarget = CGRect(x: o.x, y: o.y, width: M.playTarget.width, height: M.playTarget.height)
        let solo = CGRect(x: soloX, y: o.y, width: M.soloW, height: M.topRowH)
        let soloTarget = CGRect(x: soloX, y: o.y, width: M.soloTarget.width, height: M.soloTarget.height)
        let pool = CGRect(x: o.x, y: o.y + M.poolTop, width: M.leftColW, height: innerH - M.poolTop)
        bands.append(EuclideousMixBandFrames(frame: frame, inner: inner, play: play, playTarget: playTarget, strip: strip, stripWithBadge: stripWithBadge, solo: solo, soloTarget: soloTarget, badge: badge, pool: pool,
                                             riff: row(inner: o, top: M.riffRowTop), notes: row(inner: o, top: 42 + rowH)))
    }
    let column = CGRect(x: bandW, y: 0, width: M.emitterColumnW, height: size.height)
    // emitter n: 36 pt circle at x 40…76 of the column, centred between lane n's two part rows (band top + 8 + 36 + rowH + 3)
    let emitters = (0..<4).map { n -> CGRect in
        let cy = bands[n].frame.minY + M.bandInset + M.riffRowTop + rowH + 3
        return CGRect(x: column.minX + M.emitterX, y: cy - M.emitterD / 2, width: M.emitterD, height: M.emitterD)
    }
    var floors: [EuclideousMixRowsFloor] = []
    if rollW < M.floorRoll { floors.append(.roll) }
    if rowH < M.floorRowH { floors.append(.row) }
    if bandH < M.floorBandH { floors.append(.band) }
    return EuclideousMixRowsLayout(size: size, bandW: bandW, bandH: bandH, innerW: innerW, innerH: innerH, rowH: rowH, rollW: rollW, bands: bands, emitterColumn: column, emitters: emitters, floors: floors)
}

/// The panel's size inside the page: the lane cards' 2×2 bounding box — the lane strip's width by two cards and the gap between them.
func euclideousMixRowsPanelSize(stripWidth: CGFloat, laneBox: CGSize) -> CGSize { CGSize(width: stripWidth, height: 2 * laneBox.height + 8) }

// MARK: - §5.3 the sliders

enum EuclideousMixSliderKind: Int, CaseIterable {
    case velocity, gate, transpose, octave
    var label: String { ["VEL", "GATE", "TRANS", "OCT"][rawValue] }
    var range: ClosedRange<Int> { [1...127, 1...99, -7...7, -2...2][rawValue] }
    var isBipolar: Bool { self == .transpose || self == .octave }
    var defaultValue: Int { [100, 90, 0, 0][rawValue] }
    var spokenName: String { ["velocity", "gate", "transpose", "octave"][rawValue] }
}
enum EuclideousMixSliderMetrics {
    static let inset: CGFloat = 6, radius: CGFloat = 8, trackH: CGFloat = 3, trackUp: CGFloat = 6, thumb: CGFloat = 10, thumbRing: CGFloat = 2, tickW: CGFloat = 1, tickH: CGFloat = 8
    static let labelSize: CGFloat = 7, valueSize: CGFloat = 9
}
struct EuclideousMixSliderGeometry: Equatable {
    var track: CGRect, fill: CGRect, thumb: CGRect
    /// Bipolar tracks (TRANS, OCT) carry a tick at the centre (value 0).
    var tick: CGRect?
}
/// 0…1 along the track for a value (min → 0, max → 1).
func euclideousMixSliderFraction(kind: EuclideousMixSliderKind, value: Int) -> CGFloat {
    let r = kind.range
    return CGFloat(max(r.lowerBound, min(r.upperBound, value)) - r.lowerBound) / CGFloat(r.upperBound - r.lowerBound)
}
func euclideousMixSliderGeometry(tile: CGRect, kind: EuclideousMixSliderKind, value: Int) -> EuclideousMixSliderGeometry {
    typealias S = EuclideousMixSliderMetrics
    let track = CGRect(x: tile.minX + S.inset, y: tile.maxY - S.trackUp - S.trackH, width: tile.width - 2 * S.inset, height: S.trackH)
    let t = euclideousMixSliderFraction(kind: kind, value: value)
    let thumbX = track.minX + t * track.width
    let thumb = CGRect(x: thumbX - S.thumb / 2, y: track.midY - S.thumb / 2, width: S.thumb, height: S.thumb)
    if kind.isBipolar {
        let cx = track.midX
        let fill = CGRect(x: min(cx, thumbX), y: track.minY, width: abs(thumbX - cx), height: track.height)
        return EuclideousMixSliderGeometry(track: track, fill: fill, thumb: thumb, tick: CGRect(x: cx - S.tickW / 2, y: track.midY - S.tickH / 2, width: S.tickW, height: S.tickH))
    }
    return EuclideousMixSliderGeometry(track: track, fill: CGRect(x: track.minX, y: track.minY, width: thumbX - track.minX, height: track.height), thumb: thumb, tick: nil)
}
/// "100", "90%", "+2", "0", "−1" (U+2212).
func euclideousMixSliderText(kind: EuclideousMixSliderKind, value: Int) -> String {
    switch kind {
    case .velocity: return "\(value)"
    case .gate: return "\(value)%"
    case .transpose, .octave: return euclideousMixOctaveText(value)
    }
}
/// A horizontal drag moves the value RELATIVE to where it started, the track's width spanning the full range; every kind lands on a whole number (TRANS and OCT snap as the drag crosses each step).
func euclideousMixSliderDrag(kind: EuclideousMixSliderKind, startValue: Int, translation: CGFloat, trackWidth: CGFloat) -> Int {
    let r = kind.range
    guard trackWidth > 0 else { return startValue }
    let v = (Double(startValue) + Double(translation / trackWidth) * Double(r.upperBound - r.lowerBound)).rounded()
    return max(r.lowerBound, min(r.upperBound, Int(v)))
}
/// VoiceOver adjustable: one step up or down (VEL by 1, GATE by 1%, TRANS and OCT by a step), clamped.
func euclideousMixSliderStep(kind: EuclideousMixSliderKind, value: Int, up: Bool) -> Int { max(kind.range.lowerBound, min(kind.range.upperBound, value + (up ? 1 : -1))) }
/// What a part's slider shows now.
func euclideousMixSliderValue(of line: EuclidLine, kind: EuclideousMixSliderKind, notes: Bool) -> Int {
    switch kind {
    case .velocity: return notes ? line.notesVelocityResolved : line.velocityAbsoluteResolved
    case .gate: return max(1, min(99, Int(((notes ? line.notesGateResolved : line.gateResolved) * 100).rounded())))
    case .transpose: return max(-7, min(7, notes ? line.notesOutTransposeResolved : line.riffOutTransposeResolved))
    case .octave: return euclideousMixOctave(of: line, notes: notes)
    }
}
/// The ONE place a slider writes a lane. VEL and GATE go through the card backs' own path — RIFF through the RHYTHM sliders' commit (so the first edit PINS the notes layer, card back 6.3), NOTES straight into the notes layer's own fields;
/// OCT goes into the part's own octave field (NOT `euclideousSetNotesOctave`, which also switches NOTES on: a slider on an OFF part must not turn it on); TRANS into the out-transpose, stored as nil at 0.
func euclideousMixSliderWrite(_ line: inout EuclidLine, kind: EuclideousMixSliderKind, notes: Bool, value: Int) {
    let v = max(kind.range.lowerBound, min(kind.range.upperBound, value))
    switch kind {
    case .velocity:
        if notes { line.notesVelocity = v } else { let snap = line; euclideousSliderCommit(.velocity, &line, snapshot: snap, newValue: Double(v)) }
    case .gate:
        let g = Double(v) / 100
        if notes { line.notesGate = max(0.01, min(euclideousLaneGateMax, g)) } else { let snap = line; euclideousSliderCommit(.gate, &line, snapshot: snap, newValue: g) }
    case .transpose:
        if notes { line.notesOutTranspose = v == 0 ? nil : v } else { line.riffOutTranspose = v == 0 ? nil : v }
    case .octave:
        if notes { line.octave = v } else { line.riffOctave = v }
    }
}
/// Double tap: VEL 100, GATE 90% (a new lane's values; RIFF through the sliders' own double-tap default, pin included), TRANS and OCT 0.
func euclideousMixSliderReset(_ line: inout EuclidLine, kind: EuclideousMixSliderKind, notes: Bool) {
    switch kind {
    case .velocity: if notes { line.notesVelocity = 100 } else { euclideousSliderDoubleTapDefault(.velocity, &line) }
    case .gate: if notes { line.notesGate = 0.9 } else { euclideousSliderDoubleTapDefault(.gate, &line) }
    case .transpose, .octave: euclideousMixSliderWrite(&line, kind: kind, notes: notes, value: 0)
    }
}

// MARK: - §3.3 the rhythm strip

/// One step of the strip: a hit or not. MIX ROWS AMENDMENT 1 (2026-11-04): a hit wears NO number on MIX (the per-pass riff-column numbers were the busiest thing on the page); the card's own strip keeps its numbers.
struct EuclideousMixStripStep: Equatable { var isHit: Bool }
func euclideousMixStripSteps(hits: [EuclideousStripHit]) -> [EuclideousMixStripStep] {
    hits.map { EuclideousMixStripStep(isHit: $0.kind != .rhythmRest) }
}
enum EuclideousMixStripMetrics {
    static let cellH: CGFloat = 24, gap: CGFloat = 2, radius: CGFloat = 3, bottomLine: CGFloat = 2, alignedColumns = 16
    /// AMENDMENT 1: an empty step #25272D (was #1C1E23), the current step on an empty step #2E3138 (was #3A3E47).
    static let emptyHex: UInt32 = 0x25272D, hitAlpha = 0.25, currentEmptyHex: UInt32 = 0x2E3138
}
/// MIX STRIP (dev Settings toggle, not saved): FIT spreads a lane's steps across the strip; ALIGNED draws every lane on a 16-column grid so steps line up across lanes (a lane over 16 steps falls back to FIT).
enum EuclideousMixStripMode: String, CaseIterable { case fit = "FIT", aligned = "ALIGNED" }
let euclideousMixStripModeKey = "fourfold.mixStripMode"
/// The cells' frames (panel coordinates) for `steps` steps in a strip frame.
func euclideousMixStripCells(strip: CGRect, steps: Int, mode: EuclideousMixStripMode) -> [CGRect] {
    typealias S = EuclideousMixStripMetrics
    let n = max(1, steps)
    let columns = (mode == .aligned && n <= S.alignedColumns) ? S.alignedColumns : n
    let w = (strip.width - CGFloat(columns - 1) * S.gap) / CGFloat(columns)
    return (0..<n).map { CGRect(x: strip.minX + CGFloat($0) * (w + S.gap), y: strip.minY, width: w, height: strip.height) }
}
struct EuclideousMixCellLook: Equatable {
    var fill: EuclideousStripColumnFill      // .lane(alpha:) over the band, or a solid hex
    var bottomLine: Bool                     // a 2 pt lane-colour line along the bottom
}
/// §3.3 as amended (AMENDMENT 1): empty #25272D · hit lane100 at 25 % + the bottom line · the CURRENT step (transport running): a hit fills solid lane100, an empty step #2E3138. No numbers, no outline anywhere.
func euclideousMixCellLook(isHit: Bool, isCurrent: Bool) -> EuclideousMixCellLook {
    typealias S = EuclideousMixStripMetrics
    switch (isHit, isCurrent) {
    case (false, false): return EuclideousMixCellLook(fill: .solid(hex: S.emptyHex), bottomLine: false)
    case (false, true): return EuclideousMixCellLook(fill: .solid(hex: S.currentEmptyHex), bottomLine: false)
    case (true, false): return EuclideousMixCellLook(fill: .lane(alpha: S.hitAlpha), bottomLine: true)
    case (true, true): return EuclideousMixCellLook(fill: .lane(alpha: 1), bottomLine: false)
    }
}
/// The step the lane is on (a buffer index), from the card's own `raw` position (ticks in its pass): nil while the transport is stopped. PING-PONG's `raw` runs 0…2n−1 and reads back along the buffer, as the card does.
func euclideousMixStripCurrent(raw: Double, steps n: Int, dir: EuclidDir, running: Bool) -> Int? {
    guard running, n > 0 else { return nil }
    let cl = euclidCycleLen(dir, n: n)
    let wrapped = raw - Double(cl) * (raw / Double(cl)).rounded(.down)
    let k = min(cl - 1, max(0, Int(wrapped.rounded(.down))))
    return min(n - 1, max(0, euclidReadIndex(k, n: n, dir: dir)))
}
func euclideousMixStripSpoken(hits: Int, steps: Int) -> String { "Rhythm, \(hits) \(hits == 1 ? "hit" : "hits") in \(steps) \(steps == 1 ? "step" : "steps")" }

// MARK: - §4 the pool

struct EuclideousMixPoolChip: Equatable {
    var rank: Int
    /// The pool's note name for the rank; nil when the pool is empty (the rank alone, the chip at 40 %).
    var name: String?
    var lit: Bool
    var faded: Bool
}
enum EuclideousMixPoolMetrics {
    static let radius: CGFloat = 3, gap: CGFloat = 2, fadedAlpha = 0.4
    static let idleHex: UInt32 = 0x1F2127, idleTextHex: UInt32 = 0xC9CDD4, litTextHex: UInt32 = 0x0D0F14
}
/// §A3: where a chip's two text runs start — the rank (raised), then the name after `rankGap` — left-aligned `style.inset` in. The text style itself (sizes, weights, the rank's 70 %) is `EuclideousRankLabelStyle.mixChip`, the riff grid label's own values at the chip's size.
/// `rankWidth` is the measured width of the rank run; a chip with no name (an empty pool) draws the rank alone.
struct EuclideousMixChipTextLayout: Equatable {
    var rankX: CGFloat
    var nameX: CGFloat
    /// How far above the name's baseline the rank's baseline sits.
    var rankRaise: CGFloat
}
func euclideousMixChipTextLayout(frame: CGRect, rankWidth: CGFloat, style: EuclideousRankLabelStyle) -> EuclideousMixChipTextLayout {
    EuclideousMixChipTextLayout(rankX: frame.minX + style.inset, nameX: frame.minX + style.inset + rankWidth + style.rankGap, rankRaise: style.rankRaise)
}
/// Eight chips, rank 8 at the top: chipH = (poolH − 14) ÷ 8, 2 pt apart.
func euclideousMixPoolFrames(area: CGRect) -> [CGRect] {
    typealias P = EuclideousMixPoolMetrics
    let h = (area.height - 7 * P.gap) / 8
    return (0..<8).map { CGRect(x: area.minX, y: area.minY + CGFloat($0) * (h + P.gap), width: area.width, height: h) }
}
/// The chips top to bottom (rank 8 … 1), from the ONE pool derivation NOW, the NOTES keys and the grid's labels use (`euclideousRankChips`); `lit` bit r−1 = rank r sounding.
func euclideousMixPoolChips(sortedPool: [Int], lit: UInt8, name: (Int) -> String) -> [EuclideousMixPoolChip] {
    euclideousRankChips(sortedPool: sortedPool, litMask: lit, name: name).reversed().map { s in
        EuclideousMixPoolChip(rank: s.rank, name: s.empty ? nil : s.name, lit: s.lit, faded: s.empty)
    }
}
/// A note is "sounding now" from its note-on until its note-off (held, with no end yet, until one arrives).
func euclideousMixNoteSounds(_ n: NoteRollNote, at now: Double) -> Bool { n.onBeat <= now && (n.endBeat.map { $0 > now } ?? true) }
/// §4.3: the ranks sounding in a lane — either part, silent notes included — as a bit mask (bit r−1).
func euclideousMixLitRanks(parts: [[NoteRollNote]], nowBeat: Double) -> UInt8 {
    var m: UInt8 = 0
    for part in parts { for n in part where n.rank >= 1 && n.rank <= 8 && euclideousMixNoteSounds(n, at: nowBeat) { m |= UInt8(1) << UInt8(n.rank - 1) } }
    return m
}
func euclideousMixPoolSpoken(litNames: [String]) -> String { litNames.isEmpty ? "Pool, silent" : "Pool, sounding " + litNames.joined(separator: ", ") }

// MARK: - §5.5 the roll

enum EuclideousMixRollLook: Equatable { case sounding, ended, silent }
struct EuclideousMixRollNoteFrame: Equatable { var rect: CGRect; var look: EuclideousMixRollLook; var rank: Int }
struct EuclideousMixRoll: Equatable {
    var notes: [EuclideousMixRollNoteFrame]
    var playheadX: CGFloat
    /// The y of the 1 pt lines between the eight rank rows.
    var rowLines: [CGFloat]
}
enum EuclideousMixRollMetrics {
    static let radius: CGFloat = 6, noteRadius: CGFloat = 1.5, noteInset: CGFloat = 1.5, minNoteH: CGFloat = 2.5, minNoteW: CGFloat = 1.5
    static let groundHex: UInt32 = 0x131519, lineHex: UInt32 = 0x262930, playheadHex: UInt32 = 0xF2F4F7, playheadAlpha = 0.55, playheadW: CGFloat = 1.5
    static let endedAlpha = 0.6, silentBorderAlpha = 0.55
}
/// §5.5: the last bar of the page clock, left to right. A note sits at (its note-on's time within the bar) × width, as long as note-on → note-off (to the playhead while it sounds), clipped at the right edge and never wrapped, drawn until the playhead
/// comes round to its note-on's position a bar later — then it is wiped.
func euclideousMixRoll(notes: [NoteRollNote], nowBeat: Double, barBeats: Double, size: CGSize) -> EuclideousMixRoll {
    typealias R = EuclideousMixRollMetrics
    let bar = max(1e-9, barBeats)
    let rowH = size.height / 8
    func frac(_ b: Double) -> Double { let f = b / bar; return f - f.rounded(.down) }
    var out: [EuclideousMixRollNoteFrame] = []
    for n in notes where n.onBeat <= nowBeat && nowBeat - n.onBeat < bar {
        let end = n.endBeat ?? nowBeat
        let x = CGFloat(frac(n.onBeat)) * size.width
        let w = max(R.minNoteW, min(size.width - x, CGFloat(max(0, end - n.onBeat) / bar) * size.width))
        let rank = max(1, min(8, Int(n.rank)))
        let h = max(R.minNoteH, rowH - R.noteInset)
        let y = CGFloat(8 - rank) * rowH + (rowH - h) / 2
        let look: EuclideousMixRollLook = n.outs == 0 ? .silent : (euclideousMixNoteSounds(n, at: nowBeat) ? .sounding : .ended)
        out.append(EuclideousMixRollNoteFrame(rect: CGRect(x: x, y: y, width: w, height: h), look: look, rank: rank))
    }
    return EuclideousMixRoll(notes: out, playheadX: CGFloat(frac(nowBeat)) * size.width, rowLines: (1..<8).map { CGFloat($0) * rowH })
}
/// "Riff playing" / "Riff silent": playing = a note of this part sounds now.
func euclideousMixRollPlaying(notes: [NoteRollNote], nowBeat: Double) -> Bool { notes.contains { euclideousMixNoteSounds($0, at: nowBeat) } }

// MARK: - §6–7 the emitters and the lines

enum EuclideousMixLineMetrics {
    static let idleWidth: CGFloat = 1.25, activeWidth: CGFloat = 2, idleAlpha = 0.4, activeAlpha = 1.0, fadeSeconds = 0.150, originDot: CGFloat = 6
    static let emitterRing: CGFloat = 3, emitterLetter: CGFloat = 14   // AMENDMENT 1: no light — the emitter is its ring, fill and letter
    static let emitterIdleHex: UInt32 = 0x1F2127, inkHex: UInt32 = 0x0D0F14
}
struct EuclideousMixLineGeometry: Equatable {
    var part: Int, output: Int, lane: Int
    var from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint
}
/// §7.1–7.2: a line for each part that is ON, to each emitter its mask holds: from (bandW, row centre) to (bandW + 40, the emitter's centre), a cubic with control points (bandW + 23, y0) and (bandW + 18.5, y1). `masks` and `partOn`
/// are indexed by part (2·lane + notes). A part that is off or routed nowhere draws none.
func euclideousMixLines(layout: EuclideousMixRowsLayout, masks: [UInt8], partOn: [Bool]) -> [EuclideousMixLineGeometry] {
    typealias M = EuclideousMixRowsMetrics
    var out: [EuclideousMixLineGeometry] = []
    for part in 0..<8 {
        guard part < masks.count, part < partOn.count, partOn[part] else { continue }
        let lane = part / 2, notes = part % 2 == 1
        let y0 = layout.bands[lane].row(notes: notes).centreY
        for o in 0..<4 where masks[part] & (UInt8(1) << UInt8(o)) != 0 {
            let y1 = layout.emitters[o].midY
            out.append(EuclideousMixLineGeometry(part: part, output: o, lane: lane, from: CGPoint(x: layout.bandW, y: y0), c1: CGPoint(x: layout.bandW + M.lineBend1, y: y0),
                                                 c2: CGPoint(x: layout.bandW + M.lineBend2, y: y1), to: CGPoint(x: layout.bandW + M.emitterX, y: y1)))
        }
    }
    return out
}
/// The origin dots: one at (bandW, row centre) for each part that draws a line.
func euclideousMixOriginDots(lines: [EuclideousMixLineGeometry]) -> [(part: Int, lane: Int, at: CGPoint)] {
    var seen = Set<Int>(), out: [(part: Int, lane: Int, at: CGPoint)] = []
    for l in lines where !seen.contains(l.part) { seen.insert(l.part); out.append((l.part, l.lane, l.from)) }
    return out
}
/// §7.3: 1 while a note of the part leaving through `output` sounds, then 1 → 0 linearly over 150 ms after its note-off. Silent notes (no output bit) activate nothing. `tempo` converts the beats since the off to seconds.
func euclideousMixLineActivity(notes: [NoteRollNote], output: Int, nowBeat: Double, tempo: Double) -> Double {
    let bit = UInt8(1) << UInt8(max(0, min(3, output)))
    var latestEnd = -Double.infinity
    for n in notes where n.outs & bit != 0 && n.onBeat <= nowBeat {
        guard let e = n.endBeat, e <= nowBeat else { return 1 }
        latestEnd = max(latestEnd, e)
    }
    guard latestEnd.isFinite else { return 0 }
    let age = (nowBeat - latestEnd) * 60 / max(1, tempo)
    return max(0, min(1, 1 - age / EuclideousMixLineMetrics.fadeSeconds))
}
/// An emitter is active while ANY note (any lane) leaves through it.
func euclideousMixEmitterActivity(parts: [[NoteRollNote]], output: Int, nowBeat: Double, tempo: Double) -> Double {
    parts.reduce(0) { max($0, euclideousMixLineActivity(notes: $1, output: output, nowBeat: nowBeat, tempo: tempo)) }
}
/// Idle 1.25 pt at 40 % → active 2 pt at 100 %, by the activity.
func euclideousMixLineLook(activity: Double) -> (width: CGFloat, alpha: Double) {
    typealias L = EuclideousMixLineMetrics
    let a = max(0, min(1, activity))
    return (L.idleWidth + (L.activeWidth - L.idleWidth) * CGFloat(a), L.idleAlpha + (L.activeAlpha - L.idleAlpha) * a)
}
/// Active lines draw above idle ones: the lines' draw order by activity, stable.
func euclideousMixLineDrawOrder(activities: [Double]) -> [Int] { activities.indices.sorted { activities[$0] != activities[$1] ? activities[$0] < activities[$1] : $0 < $1 } }
struct EuclideousMixEmitterLook: Equatable {
    /// 0 = the idle fill #1F2127, 1 = filled in the output's colour (the fade between).
    var fill: Double
    var letterIsInk: Bool
}
func euclideousMixEmitterLook(activity: Double) -> EuclideousMixEmitterLook {
    let a = max(0, min(1, activity))
    return EuclideousMixEmitterLook(fill: a, letterIsInk: a >= 0.5)
}

// MARK: - §5.4 the A–D toggles

/// The output colour of A…D: lane 1's colour for A, lane 2's for B … (the emitter circles' convention).
func euclideousMixOutputColour(_ output: Int) -> HocketColor { HocketPalette.lane100(output) }

// MARK: - §10 VoiceOver

enum EuclideousMixAX {
    static let panel = "Mix"
    static func lane(_ i: Int) -> String { "Lane \(i + 1)" }
    static func part(notes: Bool) -> String { notes ? "Notes" : "Riff" }
    static func toggle(notes: Bool, on: Bool) -> String { "\(part(notes: notes)), \(on ? "on" : "off")" }
    static func roll(notes: Bool, playing: Bool) -> String { "\(part(notes: notes)) \(playing ? "playing" : "silent")" }
    static func slider(kind: EuclideousMixSliderKind, notes: Bool, value: Int) -> String { "\(part(notes: notes)) \(kind.spokenName) \(euclideousMixSliderText(kind: kind, value: value))" }
    static func out(notes: Bool, output: Int, on: Bool) -> String { "\(part(notes: notes)) to \(euclideousJackLetters[max(0, min(3, output))]), \(on ? "on" : "off")" }
    static func emitter(output: Int, active: Bool) -> String { "Output \(euclideousJackLetters[max(0, min(3, output))]), \(active ? "active" : "idle")" }
    static let reset = "Reset"
}
