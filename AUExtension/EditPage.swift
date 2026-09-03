//  EditPage.swift
//  The EDIT-spike-page surface, extracted from AudioUnitViewController.swift as an extension of DiagView
//  (mode row · selection set · inspector · chain · chop · triggers · cell library). Pure relocation — no behaviour
//  change. @State lives in DiagView (AudioUnitViewController.swift); these are its methods/computed views.

import SwiftUI

/// The ADD/EDIT SELECTION as ONE cohesive value (extracted 2026-08-07 from five scattered @State vars). It owns the
/// selected cells, the per-session bookkeeping (which cells were BORN here → deleted on deselect; which were ADOPTED →
/// their originals stashed for restore), and the selection undo/redo history. The DOCUMENT effects (create/clone/
/// delete/restore, and applying a restored doc on undo) stay with the caller — this owns the STATE and the pure
/// transitions only. Lives view-side (GridPos is a SwiftUI type), so it's build-verified, not unit-tested.
struct EditSelection {
    private(set) var cells: [GridPos] = []
    private(set) var born: Set<GridPos> = []             // created this session → deselect deletes
    private(set) var adoptStash: [GridPos: Cell] = [:]   // adopted → original, so deselect restores
    private var undoStack: [(sel: [GridPos], doc: PluginState)] = []
    private var redoStack: [(sel: [GridPos], doc: PluginState)] = []

    var anchor: GridPos? { cells.first }
    var isEmpty: Bool { cells.isEmpty }
    var count: Int { cells.count }
    var asSet: Set<GridPos> { Set(cells) }
    var targets: [(col: Int, row: Int)] { cells.map { (col: $0.col, row: $0.row) } }
    func contains(_ p: GridPos) -> Bool { cells.contains(p) }
    func wasBorn(_ p: GridPos) -> Bool { born.contains(p) }
    func stashed(_ p: GridPos) -> Cell? { adoptStash[p] }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // --- state transitions (the caller performs the matching document effects) ---
    mutating func add(_ p: GridPos) { if !cells.contains(p) { cells.append(p) } }
    mutating func markBorn(_ p: GridPos) { born.insert(p) }
    mutating func stash(_ p: GridPos, _ original: Cell) { adoptStash[p] = original }
    mutating func remove(_ p: GridPos) { cells.removeAll { $0 == p }; born.remove(p); adoptStash[p] = nil }
    mutating func reset() { cells = []; born = []; adoptStash = [:]; clearHistory() }

    // --- selection undo/redo: snapshot before a change; undo/redo return the document to restore (if any) ---
    mutating func recordUndo(_ doc: PluginState) { undoStack.append((cells, doc)); redoStack.removeAll() }
    mutating func clearHistory() { undoStack.removeAll(); redoStack.removeAll() }
    mutating func undo(currentDoc: PluginState) -> PluginState? {
        guard let prev = undoStack.popLast() else { return nil }
        redoStack.append((cells, currentDoc)); cells = prev.sel; return prev.doc
    }
    mutating func redo(currentDoc: PluginState) -> PluginState? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append((cells, currentDoc)); cells = next.sel; return next.doc
    }
}


extension DiagView {
    /// Remove a cell from the group and REVERT it to its original state: a cell created this session is deleted;
    /// a populated cell adopted into the group is restored from its pre-adopt stash.
    func syncSingleModeActivation() {
        // Drives the LADDER active rung from the selection (LADDER factory presets set ladderMode; the old in-grid tap
        // machinery is gone). NOT on the DRAG&DROP page — there the selection is the whole colour (2026-08-09 bug).
        guard ladderMode, let au else { return }
        var topByColumn: [Int: Int] = [:]
        for p in sel.cells { topByColumn[p.col] = min(topByColumn[p.col] ?? p.row, p.row) }
        guard !topByColumn.isEmpty else { return }
        for (col, row) in topByColumn { au.setActiveRow(col, row) }
        refreshFromDocument()
    }

    // MODE ROW §5 — the grid's own column keys ARE the loop control (one row, not two): a TAP toggles the column in
    // the SAME `laneMask` the PERFORM column-hold drives (one loop mechanism, two surfaces). BUG FIX (Paul, device
    // 2026-08-05): the EDIT page drives the ONE perform mirror `setLane` (was a separate `editLoopMask`), so the loop
    // is page-independent — it keeps playing and shows its glyph on the GRID page too. Toggled keys show the LOOP glyph.

    // The grid instance for the spike page — the same GridView component. In EDIT mode a tap builds the selection
    // set (white ring) AND auto-selects the tapped cell's TWINS (user 2026-08-07: they JOIN the selection — the
    // advertise-pulse is gone; deselect one to decouple it). A long-press drops the ANCHOR; CLEAR marks show a red ✕.
    // CELL MACHINE (feat/EditPageSpike): the selected cell's processor CHAIN as a VERTICAL STACK of slot boxes,
    // each 50% of screen width, head first, plus [+ ADD] (≤ 8 slots). Stage 1 renders the HEAD; slots 2…8 are
    // stored + editable but not yet executed (serial run is Phase 2). Reuses ProcessorBox in `slotMode`.
    func cellChain(_ cell: Cell) -> [ProcessorSlot] {         // the cell's effective chain — the engine's 3-tier resolution
        let resolved: [ProcessorSlot]
        if let p = cell.processors { resolved = p }                   // per-cell OVERRIDE (incl. an EXPLICIT empty chain = passthrough)
        else {
            let c = docColours.first { $0.colourID == cell.colourID }
            if let t = c?.templateChain, !t.isEmpty { resolved = t }  // colour TEMPLATE (the per-colour machine — matches the builder)
            else { return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())] }   // legacy A face (a real slot)
        }
        // A DELETED-EMPTY chain is stored as the passthrough representation — a single BYPASSED PASSGATE — because an
        // empty `templateChain` would be read as "no template" and fall back to the colour's A-face (the arp would
        // reappear). For DISPLAY/editing, unwrap that placeholder to EMPTY so the flow diagram invites "+ ADD
        // PROCESSOR" instead of showing a stray passgate. (user 2026-08-10: "delete an arp → replaced with a passgate")
        if resolved.count == 1, resolved[0].type == .passgate, resolved[0].bypassed { return [] }
        return resolved
    }
    func deleteLibraryCellNamed(_ name: String) {   // CellBrowser onDelete (live)
        au?.deleteLibraryCell(name: name); cellLibraryList = au?.libraryCellSummaries() ?? []
    }
}
