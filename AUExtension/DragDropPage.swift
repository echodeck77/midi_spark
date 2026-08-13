import SwiftUI
// The DRAG&DROP page (and all its drag/palette/grid/machinery/dice code) was REMOVED (user 2026-08-13) — the BUILD
// page superseded it. This file now holds ONLY the colour-management cluster still shared with BUILD (ddSelectColour/
// ddCreateColour/ddColourShown/ddColourIsPlaced/ddRepresentativeCell/ddEngageSolo/ddEnsureSelection/ddSelectedColourID
// + their internals) and `ddZone` (used by EditPage's flowDiagram).

// Drop-zone frames for ddZone (still used by EditPage's flowDiagram to measure the last processor slot).
struct DDZonePref: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension DiagView {
    // A cell/swatch reports its frame (in "dd" space) so a drag's end point can be hit-tested to a landing.
    func ddZone(_ key: String) -> some View {   // internal so flowDiagram (EditPage.swift) can measure the last processor slot for the action-box line
        GeometryReader { g in Color.clear.preference(key: DDZonePref.self, value: [key: g.frame(in: .named("dd"))]) }
    }
    var ddSelectedColourID: String? {
        if ddColourSel >= 0 && ddColourSel < colourIDs.count { return colourIDs[ddColourSel] }
        return editingCell?.colourID
    }
    // LANDSCAPE header (user 2026-08-10): the colour's EXAMPLE CELL (swatch) + its name GOLD, with the cell COUNT to
    // the right — sits ABOVE the palette grid, lined up with the top of the grid.
    func ddColourIsPlaced(_ id: String) -> Bool {      // internal: shared with the BUILD page
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { return true } }
        return false
    }
    /// A palette slot shows a colour when it's been CREATED (defined flag) or has placed cells; else it's a "+" slot.
    func ddColourShown(_ i: Int) -> Bool {             // internal: shared with the BUILD page
        (i < docColours.count && docColours[i].defined == true) || ddColourIsPlaced(colourIDs[i])
    }
    /// Tap a "+" slot → CREATE a new colour (mark it defined; its default machine is the colour's own head). It shows
    /// as a swatch, selected; drag it onto the grid to place + edit (no cells yet, so the machinery invites a place).
    func ddCreateColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        au?.editDocument { doc in if i < doc.colours.count { doc.colours[i].defined = true } }
        refreshFromDocument()
        ddColourSel = i
        ddScopeToColour(colourIDs[i], anchor: nil)
    }
    func ddRepresentativeCell(_ id: String) -> Cell? {   // internal: shared with the BUILD page
        for c in 0..<8 { for r in 0..<8 { if let cell = scene.cellAt(c, r), cell.colourID == id { return cell } } }
        return nil
    }
    private func ddColourCells(_ id: String) -> [GridView.GridPos] {
        var out: [GridView.GridPos] = []
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { out.append(GridView.GridPos(col: c, row: r)) } }
        return out
    }
    /// THE PER-COLOUR MODEL (user 2026-08-09): a colour IS a machine — selecting one scopes the edit to EVERY cell of
    /// that colour, so every machinery edit (add/remove/params/split) applies colour-wide. The anchor cell just drives
    /// what the flow diagram DISPLAYS. `editPointedCell`/`editChop`/`{add,edit,remove}SlotCells` all fan out to `sel`.
    private func ddScopeToColour(_ id: String, anchor: (Int, Int)?) {
        let cells = ddColourCells(id)
        sel.reset(); for p in cells { sel.add(p) }
        if let a = anchor { selCol = a.0; selRow = a.1 }
        else if let first = cells.first { selCol = first.col; selRow = first.row }
        else { selCol = -1; selRow = -1 }
        if ddSolo { ddEngageSolo() }   // PLAY: THIS CELL follows the selection
        ddCaptureStickyRouting()   // remember the last-chosen receiver + emitters (the default for the next fresh cell)
    }
    /// STICKY ROUTING (user 2026-08-10): a fresh cell inherits the LAST receiver + emitters chosen on the page (else
    /// the model default R1 + Emitter A). Captured from the anchor cell on select + after a routing edit.
    /// Engage PLAY: THIS CELL for the current selection. A PLACED cell freezes on its grid slot; an UNPLACED colour
    /// (no cell yet) plays via a SYNTHETIC preview cell at an empty slot (its sticky receiver + emitters + machine).
    /// If neither is possible (no colour selected, or the grid is full for a preview) the toggle springs back off.
    func ddEngageSolo() {
        if selCol >= 0, selRow >= 0 { au?.setColourSolo(col: selCol, row: selRow); return }
        if let cid = ddSelectedColourID, au?.setColourSoloPreview(colourID: cid, inputReceiver: ddStickyReceiver, buses: Array(ddStickyBuses)) == true { return }
        ddSolo = false; au?.clearColourSolo()
    }
    func ddCaptureStickyRouting() {
        guard let c = editingCell else { return }
        ddStickyReceiver = c.inputReceiver ?? 0
        ddStickyBuses = c.buses.isEmpty ? [.a] : c.buses
    }
    /// The placed cells of a colour — the cross-file-visible read `editPointedCell` uses to detect an unplaced colour.
    func ddColourCellsPublic(_ id: String) -> [GridView.GridPos] { ddColourCells(id) }
    /// UNPLACED-colour routing: apply a cell mutation to a synthetic cell carrying the current sticky routing, then
    /// read the result back into the sticky — so a receiver/emitter tap on a not-yet-placed colour sticks + shows.
    func ddApplyStickyRoutingMutation(_ id: String, _ mutate: (inout Cell) -> Void) {
        var c = Cell(colourID: id)
        c.inputReceiver = ddStickyReceiver
        c.buses = ddStickyBuses
        mutate(&c)
        ddStickyReceiver = c.inputReceiver ?? 0
        ddStickyBuses = c.buses
    }
    /// Select a palette colour → scope the machinery to the whole colour (anchored on its first placed cell). No
    /// placed cell → nothing to edit yet (place it via a row selector or a drag).
    func ddSelectColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        ddColourSel = i
        ddScopeToColour(colourIDs[i], anchor: nil)
    }
    /// Open the DRAG&DROP page with a colour selected: keep a valid current selection, else fall back to GOLD (the
    /// default colour that's always present). Re-scopes so the selection picks up any newly-placed cells. (user 2026-08-09)
    func ddEnsureSelection() {
        let valid = ddColourSel >= 0 && ddColourSel < colourIDs.count && ddColourShown(ddColourSel)
        ddSelectColour(valid ? ddColourSel : (colourIDs.firstIndex(of: "gold") ?? 0))
    }
}
