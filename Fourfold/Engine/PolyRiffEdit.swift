//  PolyRiffEdit.swift
//  POLY RIFF ferry (2026-10-29), slice 2: the pure maths behind the POLY grid — how a touch edits it (create, stretch either way, shorten, remove) and where its cells are.
//  Foundation only, on purpose (the macOS test target compiles this file directly): the view paints these frames and calls these functions, and decides nothing else.
//
//  The gesture (Paul: "touch a cell and drag right or left horizontally … it will extend the length of the note; otherwise the behaviour is the same"):
//   · touch an EMPTY cell — a note of length 1 appears there; dragging horizontally stretches it between the touched column and the finger, to the right or to the left;
//   · touch a cell a note COVERS (its head or a tail cell) — lifting without moving takes the note away (a tap toggles, as in MONO); dragging keeps the end of the note FARTHEST from the touch where it is
//     and moves the other end with the finger (it may pass the fixed end and flip direction, like a selection handle), so a note can be shortened as well as stretched;
//   · the rank never changes during a drag (a vertical move is ignored), a note never runs into another note at its rank or off the grid, and its length is at least 1.

import Foundation
import CoreGraphics

struct EuclideousPolyDrag: Equatable {
    /// The rank the touch began on — fixed for the whole drag.
    let rank: Int
    /// The column the touch began on.
    let touchCol: Int
    /// The end of the note that stays put: the touched column for a new note, the end FARTHER from the touch for an existing one.
    let fixedCol: Int
    /// The touch began on a note (rather than creating one).
    let existing: Bool
    /// The note as it stands now.
    var current: EuclideousPolyNote
    /// The finger has been over a column other than the one it touched down on.
    var moved = false

    /// Touch down on (col, rank): returns the drag and the riff with a new length-1 note there when the cell was empty.
    static func begin(_ riff: EuclideousPolyRiff, col: Int, rank: Int) -> (drag: EuclideousPolyDrag, riff: EuclideousPolyRiff) {
        let c = max(0, min(EuclideousPolyMetrics.columns - 1, col)), r = max(1, min(EuclideousPolyMetrics.ranks, rank))
        let base = riff.normalized
        if let n = base.note(covering: c, rank: r) {
            let tail = n.col + n.len - 1
            let far = (c - n.col) >= (tail - c) ? n.col : tail                    // the farther end stays; on a tie the tail follows the finger
            return (EuclideousPolyDrag(rank: r, touchCol: c, fixedCol: far, existing: true, current: n), base)
        }
        let fresh = EuclideousPolyNote(col: c, rank: r, len: 1)
        return (EuclideousPolyDrag(rank: r, touchCol: c, fixedCol: c, existing: false, current: fresh), EuclideousPolyRiff(notes: base.notes + [fresh]).normalized)
    }

    /// The finger is over `fingerCol`: the note spans the fixed end and the finger, clear of its neighbours at this rank.
    func update(_ riff: EuclideousPolyRiff, fingerCol: Int) -> (drag: EuclideousPolyDrag, riff: EuclideousPolyRiff) {
        let f = max(0, min(EuclideousPolyMetrics.columns - 1, fingerCol))
        var d = self
        if f != touchCol { d.moved = true }
        let others = riff.normalized.notes.filter { !($0.rank == rank && $0.col == current.col) }
        var lo = 0, hi = EuclideousPolyMetrics.columns - 1
        for o in others where o.rank == rank {
            if o.col + o.len - 1 < fixedCol { lo = max(lo, o.col + o.len) }
            else if o.col > fixedCol { hi = min(hi, o.col - 1) }
        }
        let a = max(lo, min(fixedCol, f)), b = min(hi, max(fixedCol, f))
        d.current = EuclideousPolyNote(col: a, rank: rank, len: max(1, b - a + 1))
        return (d, EuclideousPolyRiff(notes: others + [d.current]).normalized)
    }

    /// Lift: a touch that began on a note and never moved takes that note away; anything else leaves the riff as it is.
    func end(_ riff: EuclideousPolyRiff) -> EuclideousPolyRiff {
        guard existing, !moved else { return riff }
        return EuclideousPolyRiff(notes: riff.normalized.notes.filter { !($0.rank == rank && $0.col == current.col) }).normalized
    }
}

extension EuclideousPolyRiff {
    /// VoiceOver's "make the note longer / shorter": the note covering (`col`, `rank`) gets `delta` more (or fewer) columns at its tail end, never fewer than 1, never into the next note at its rank or off the grid. A cell no note covers changes nothing.
    func resized(noteAt col: Int, rank: Int, by delta: Int) -> EuclideousPolyRiff {
        guard let n = normalized.note(covering: col, rank: rank) else { return self }
        let tail = n.col + n.len - 1
        let started = EuclideousPolyDrag.begin(self, col: tail, rank: rank)     // touched on its tail: the head is the end that stays
        return started.drag.update(started.riff, fingerCol: max(n.col, tail + delta)).riff
    }
    /// VoiceOver activation of a cell (and a plain tap): a note covering it goes, otherwise a length-1 note appears — the same rule a touch follows, with no drag.
    func toggled(col: Int, rank: Int) -> EuclideousPolyRiff {
        let started = EuclideousPolyDrag.begin(self, col: col, rank: rank)
        return started.drag.end(started.riff)
    }
    /// The highest rank of a note STARTING on `col` — or, on a column where none starts, of a note still sounding through it (0 = nothing): what an arrow's seat shows.
    func seatRank(col: Int) -> Int {
        let n = normalized.notes
        if let top = n.filter({ $0.col == col }).map({ $0.rank }).max() { return top }
        return n.filter { col > $0.col && col < $0.col + $0.len }.map { $0.rank }.max() ?? 0
    }
    /// The notes STARTING on `col` — rank and length, lowest rank first (the order the Router strikes them in).
    func startingNotes(at col: Int) -> [(rank: Int, len: Int)] { normalized.notes.filter { $0.col == col }.sorted { $0.rank < $1.rank }.map { (rank: $0.rank, len: $0.len) } }
    /// The ranks of the notes STARTING on `col`, highest first (the lane strip draws one chip each).
    func ranksStarting(at col: Int) -> [Int] { normalized.notes.filter { $0.col == col }.map { $0.rank }.sorted(by: >) }
    /// Per column, the highest rank STARTING there (0 = a rest column) — what the grid's own picture and the editing code read; a hit's strike set (which depends on the way the walk is moving) is `PolyRiffSnap.triggerMask`.
    var topRanks: [Int] {
        var out = [Int](repeating: 0, count: EuclideousPolyMetrics.columns)
        for n in normalized.notes { out[n.col] = max(out[n.col], n.rank) }
        return out
    }
}

// MARK: - the POLY grid's frames

/// The POLY grid's column width inside a panel `maxWidth` wide: the note-label column (the MONO decision, so the labels do not change width between the modes), the sp4 gap, the sp8 padding on both sides and
/// 2 pt between the sixteen columns. ≈ 18.8 pt at the 380.67 reference.
func euclideousPolyCellW(maxWidth: CGFloat) -> CGFloat {
    let n = CGFloat(EuclideousPolyMetrics.columns)
    let label = euclideousRiffNoteLabelW(maxWidth: maxWidth)
    let gridW = max(1, maxWidth - (label + 4))
    return max(1, (gridW - 8 * 2 - EuclideousPolyMetrics.colGap * (n - 1)) / n)
}
extension EuclideousPolyMetrics {
    static let colGap: CGFloat = 2
}
/// The riff panel's inside in POLY: the MONO layout's rows, rails and label column with sixteen narrower columns (2 pt apart) — and cells as TALL as their rows (MONO caps a cell's height at its width to keep it square, which at
/// 16 columns would shrink the grid to 70 % of the panel).
func euclideousPolyPanelLayout(box: CGSize) -> EuclideousRiffPanelLayout {
    var l = euclideousRiffPanelLayout(box: box)
    l.columns = EuclideousPolyMetrics.columns
    l.colGap = EuclideousPolyMetrics.colGap
    l.cellW = euclideousPolyCellW(maxWidth: box.width)
    l.cellH = max(1, l.rowH)
    return l
}

/// Where a touch at `point` (in the grid's own coordinates, 0,0 = its top-left) lands: the column and rank, clamped to the grid.
func euclideousPolyCellAt(_ point: CGPoint, layout l: EuclideousRiffPanelLayout) -> (col: Int, rank: Int) {
    let col = Int((point.x / max(1, l.cellW + l.colGap)).rounded(.down))
    let row = Int((point.y / max(1, l.cellH + EuclideousRiffPanelMetrics.rowGap)).rounded(.down))
    return (max(0, min(l.columns - 1, col)), 8 - max(0, min(7, row)))
}
