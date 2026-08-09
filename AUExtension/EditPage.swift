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
    private(set) var cells: [GridView.GridPos] = []
    private(set) var born: Set<GridView.GridPos> = []             // created this session → deselect deletes
    private(set) var adoptStash: [GridView.GridPos: Cell] = [:]   // adopted → original, so deselect restores
    private var undoStack: [(sel: [GridView.GridPos], doc: PluginState)] = []
    private var redoStack: [(sel: [GridView.GridPos], doc: PluginState)] = []

    var anchor: GridView.GridPos? { cells.first }
    var isEmpty: Bool { cells.isEmpty }
    var count: Int { cells.count }
    var asSet: Set<GridView.GridPos> { Set(cells) }
    var targets: [(col: Int, row: Int)] { cells.map { (col: $0.col, row: $0.row) } }
    func contains(_ p: GridView.GridPos) -> Bool { cells.contains(p) }
    func wasBorn(_ p: GridView.GridPos) -> Bool { born.contains(p) }
    func stashed(_ p: GridView.GridPos) -> Cell? { adoptStash[p] }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // --- state transitions (the caller performs the matching document effects) ---
    mutating func add(_ p: GridView.GridPos) { if !cells.contains(p) { cells.append(p) } }
    mutating func markBorn(_ p: GridView.GridPos) { born.insert(p) }
    mutating func stash(_ p: GridView.GridPos, _ original: Cell) { adoptStash[p] = original }
    mutating func remove(_ p: GridView.GridPos) { cells.removeAll { $0 == p }; born.remove(p); adoptStash[p] = nil }
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

/// THE DIN ICON (design ferry SPEC-din-icon, 2026-08-07) — the 5-pin DIN-180° MIDI plug, custom Shapes. `DINPins`
/// draws the FIVE pins (clock 2·4·6·8·10, the 180° arc facing the notch); `DINPlug` is the FILLED disc with the
/// key NOTCH + pins knocked out (fill even-odd). Use `dinMark(...)` to render either variant. A mark, not a status
/// — inked in the ink/dim tokens, never hue-tinted.
struct DINPins: Shape {   // the FIVE pins as bold round DOTS (stylised, user 2026-08-07) at clock 2·4·6·8·10
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let pinRad = 0.55 * r, dot = 0.145 * r
        var p = Path()
        for deg in stride(from: 60.0, through: 300.0, by: 60.0) {
            let a = CGFloat(deg) * .pi / 180
            let px = c.x + pinRad * sin(a), py = c.y - pinRad * cos(a)
            p.addEllipse(in: CGRect(x: px - dot, y: py - dot, width: 2 * dot, height: 2 * dot))
        }
        return p
    }
}
struct DINPlug: Shape {   // the FILLED variant: disc − notch − pins (fill even-odd)
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))              // socket disc
        p.addRect(CGRect(x: c.x - 0.14 * r, y: c.y - 0.95 * r, width: 0.28 * r, height: 0.18 * r)) // key notch (subtracted)
        p.addPath(DINPins().path(in: rect))                                                        // pins (subtracted)
        return p
    }
}
/// Render the DIN mark in either variant. FILLED = the solid plug (notch/pins are holes). OUTLINE = a stroked ring +
/// filled pins + a small key tab at 12:00 (headers, cog rows). `ink` follows the surrounding context.
@ViewBuilder func dinMark(outline: Bool = false, ink: Color, size: CGFloat) -> some View {
    if outline {
        ZStack {
            Circle().strokeBorder(ink, lineWidth: max(1.6, size * 0.11))   // heavier ring (stylised)
            DINPins().fill(ink)
        }
        .overlay(alignment: .top) { RoundedRectangle(cornerRadius: size * 0.05).fill(ink).frame(width: size * 0.30, height: size * 0.15) }   // the key tab
        .frame(width: size, height: size)
    } else {
        DINPlug().fill(ink, style: FillStyle(eoFill: true)).frame(width: size, height: size)
    }
}

extension DiagView {
    // MODE ROW — the selection set's helpers. The ANCHOR is `sel.anchor`: it drives the inspector (selCol/selRow)
    // and the breadcrumb, and is protected from a stray tap (long-press to drop). Edits write through to `sel`.
    var editSelTargets: [(col: Int, row: Int)] { sel.targets }
    func syncAnchor() {
        if let a = sel.anchor { selCol = a.col; selRow = a.row; brush = scene.cellAt(a.col, a.row)?.colourID ?? brush }
        else { selCol = -1; selRow = -1 }
    }
    /// Remove a cell from the group and REVERT it to its original state: a cell created this session is deleted;
    /// a populated cell adopted into the group is restored from its pre-adopt stash.
    func deselect(_ pos: GridView.GridPos) {
        recordSelectionUndo()                        // snapshot (selection, doc) before this deselect
        if sel.wasBorn(pos) {                         // created this session → delete it
            au?.editScene { $0.deleteCellSever(col: pos.col, row: pos.row) }; refreshFromDocument()
        } else if let orig = sel.stashed(pos) {       // adopted → restore its original
            au?.editScene { $0.setCell(pos.col, pos.row, orig) }; refreshFromDocument()
        }
        sel.remove(pos)                               // drops it from cells + born + stash
        syncAnchor()
    }
    /// A newborn cell (empty-tap in EDIT): born AUDIBLE — R1 → Emitter A, an EMPTY chain (passthrough). It defaults
    /// to a NEW colour (the first palette hue not already on the grid) so it reads as a fresh, independent cell.
    func newbornColour() -> String {
        let used = Set(scene.cells.flatMap { $0 }.compactMap { $0?.colourID })
        return colourIDs.first { !used.contains($0) } ?? colourIDs.first ?? brush
    }
    func newbornCell() -> Cell {
        var c = Cell(colourID: newbornColour())
        c.inputReceiver = 0            // R1
        c.buses = [.a]                 // Emitter A
        c.processors = []              // explicit EMPTY chain = passthrough
        return c
    }
    /// Grid long-press. ADD/EDIT: only the ANCHOR responds — it drops from the set (a newborn anchor is deleted).
    /// MUTE/CLEAR: a long-press does the SAME as a short press (fired once per press — the gesture repeats while held).
    func editGridLongPress(_ col: Int, _ row: Int) {
        guard editArmed, !longPressFired else { return }
        longPressFired = true
        let pos = GridView.GridPos(col: col, row: row)
        switch editMode {
        case .addEdit:
            guard sel.anchor == pos else { return }   // only the anchor responds to a long-press (drops + reverts)
            deselect(pos)
        case .mute, .clear:
            editModeTap(col, row)
        case .move:
            break
        }
    }
    func editGridLongEnd() { longPressFired = false }
    /// MUTE / CLEAR mode taps (occupied cells only). MUTE toggles the cell's mute IMMEDIATELY (its own undo step —
    /// the session is closed in MUTE mode). CLEAR toggles a transactional removal MARK (committed by APPLY).
    func editModeTap(_ col: Int, _ row: Int) {
        let pos = GridView.GridPos(col: col, row: row)
        switch editMode {
        case .mute:
            guard scene.cells[col][row] != nil else { return }
            au?.editScene { $0.cells[col][row]?.muted.toggle() }   // IMMEDIATE + undoable: MUTE is chrome (post-derivation suppression)
            refreshFromDocument()
        case .clear:
            if let removed = scene.cells[col][row] {              // occupied → remove NOW (stash it for re-tap reinstate)
                clearedStash[pos] = removed
                au?.editScene { $0.deleteCellSever(col: col, row: row) }; refreshFromDocument()
            } else if let stashed = clearedStash[pos] {           // empty slot we just cleared → reinstate it
                au?.editScene { $0.cells[col][row] = stashed }; clearedStash[pos] = nil; refreshFromDocument()
            }
        case .addEdit, .move:
            break                                                 // MOVE uses drag, not tap
        }
    }

    // MARK: - feat/EditPageSpike (2026-08-01) — an ALTERNATIVE grid-setup surface, opened by the existing EDIT
    // button (body branches to it while `editArmed`). A full-width GRID sits on top; tapping a POPULATED cell
    // selects it (via `tapCell`'s editArmed re-point) and reveals its controls below in signal-path order:
    // RECEIVER → PROCESSOR → EMITTERS. Reuses the cell-scoped builders (identitySection / processorPanels /
    // outputSection), all already wired to selCol/selRow/brush. Self-contained so the spike is easy to drop.
    // TOP-OF-PAGE play-scope toggle (user 2026-08-08): PLAY FROM GRID (normal) ↔ PLAY THIS CELL ONLY (solo the edit
    // selection while the transport plays — every other cell falls silent). Ephemeral; clears on leaving EDIT.
    /// A single ENABLE/DISABLE play-scope button (user 2026-08-09, was a 2-segment toggle) — lit = play THIS CELL
    /// only (solo), unlit = play from the whole grid. Lives beside the flow diagram.
    @ViewBuilder func playScopeButton() -> some View {
        let solo = playCellOnly
        Button {
            playCellOnly.toggle()
            if playCellOnly { au?.setEditSolo(editSelTargets) } else { au?.clearEditSolo() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: solo ? "speaker.wave.2.fill" : "square.grid.3x3.fill").font(.system(size: 11, weight: .heavy))
                Text(solo ? "PLAY: THIS CELL" : "PLAY: FROM GRID").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(solo ? .black : Self.editHue)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(solo ? Self.editHue : Self.editHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.editHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }

    /// THE CELL-EDIT PAGE — ONE non-scrolling panel (user 2026-08-09). LANDSCAPE: grid LEFT · flow diagram RIGHT ·
    /// the mode buttons in a row along the BOTTOM. PORTRAIT: grid TOP with the mode buttons in a slim column to its
    /// right · flow diagram in the BOTTOM half. No informational text; the play-scope is a single button by the flow.
    @ViewBuilder func editSpikePage(_ size: CGSize) -> some View {
        let landscape = size.width > size.height
        let gridW: CGFloat = landscape
            ? max(120, min(size.height - 96, (size.width * 0.46) / 1.3)) * 1.3   // landscape: bound by height & ~46% width
            : max(160, min(size.width - 152, (size.height * 0.46) * 1.3))          // portrait: top half, clear of the 122 button column
        let gridH = gridW / 1.3
        let cellH = max(16, min(46, (gridH - 30) / 9))

        if landscape {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    spikeGrid(cellH).frame(width: gridW, height: gridH)
                    flowRegion(width: size.width - gridW - 44)   // flow diagram + play-scope, on the right
                        .frame(maxWidth: .infinity, alignment: .top)
                }.frame(maxHeight: .infinity, alignment: .top)
                modeButtons(vertical: false)                                  // the mode buttons ALONG THE BOTTOM
            }.padding(12)
        } else {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    spikeGrid(cellH).frame(width: gridW, height: gridH)
                    modeButtons(vertical: true).frame(width: 122)             // slim mode-button column, right of the grid
                }.frame(maxWidth: .infinity, alignment: .leading)
                flowRegion(width: size.width - 24)               // flow diagram + play-scope, BOTTOM half
                    .frame(maxHeight: .infinity, alignment: .top)
            }.padding(12)
        }
    }
    /// The flow-diagram region: the play-scope button above the flow diagram (or a hint when no cell is selected).
    @ViewBuilder private func flowRegion(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if editMode == .addEdit, let cell = editingCell {
                playScopeButton()
                flowDiagram(cell, width: width)
            } else {
                Text(editMode == .addEdit ? "Select a cell to edit its chain" : "")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    /// The mode buttons (ADD/EDIT · MOVE · MUTE · CLEAR) + APPLY/CANCEL — laid as a bottom ROW (landscape) or a slim
    /// COLUMN (portrait). No guidance text (user 2026-08-09).
    @ViewBuilder func modeButtons(vertical: Bool) -> some View {
        let canCommit = !sel.isEmpty
        if vertical {
            VStack(spacing: 6) {
                modeChip("ADD/EDIT", .addEdit); modeChip("MOVE", .move); modeChip("MUTE", .mute); modeChip("CLEAR", .clear)
                if editMode == .addEdit {
                    Button { commitSession() } label: { transactChip("APPLY", enabled: canCommit, fill: true) }.buttonStyle(.plain).disabled(!canCommit)
                    Button { revertSession() } label: { transactChip("CANCEL", enabled: canCommit, fill: false) }.buttonStyle(.plain).disabled(!canCommit)
                }
            }
        } else {
            HStack(spacing: 8) {
                modeChip("ADD/EDIT", .addEdit); modeChip("MOVE", .move); modeChip("MUTE", .mute); modeChip("CLEAR", .clear)
                if editMode == .addEdit {
                    Spacer(minLength: 8)
                    Button { commitSession() } label: { transactChip("APPLY", enabled: canCommit, fill: true) }.buttonStyle(.plain).disabled(!canCommit)
                    Button { revertSession() } label: { transactChip("CANCEL", enabled: canCommit, fill: false) }.buttonStyle(.plain).disabled(!canCommit)
                }
            }
        }
    }
    private func sectionSeam() -> some View { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.vertical, 2) }
    func modeChip(_ label: String, _ mode: EditPageMode) -> some View {
        let on = editMode == mode
        return Button { setEditMode(mode) } label: {
            Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(on ? .black : Self.editHue)
                .frame(maxWidth: .infinity).frame(minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Self.editHue : Self.editHue.opacity(0.12)))
        }.buttonStyle(.plain)
    }
    func transactChip(_ label: String, enabled: Bool, fill: Bool) -> some View {
        let hue: Color = label == "CANCEL" ? Verb.delete.hue : Self.editHue
        return Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundColor(!enabled ? .white.opacity(0.22) : (fill ? .black : hue))
            .frame(minWidth: 62, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(fill && enabled ? hue : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(enabled ? hue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)))
    }

    /// Switch tap mode. Leaving ADD/EDIT commits any staged work (live-previewed edits persist); entering it opens a
    /// fresh baseline. MOVE/MUTE/CLEAR run with the session CLOSED (their edits are immediate + undo/redo). Leaving
    /// CLEAR drops its re-tap stash (undo/redo covers removals thereafter).
    func setEditMode(_ m: EditPageMode) {
        guard m != editMode else { return }
        if editMode == .addEdit { au?.applyEditSession() }
        sel.reset(); clearedStash = [:]; syncAnchor()
        editMode = m
        if m == .addEdit { au?.beginEditSession() }
        refreshFromDocument()
    }
    /// APPLY — commit the staged ADD/EDIT session as one undo step, then re-open a fresh baseline so editing continues.
    func commitSession() {
        au?.applyEditSession(); sel.reset(); syncAnchor()
        au?.beginEditSession(); refreshFromDocument()
    }
    /// CANCEL — revert everything staged since the session opened, then re-open a fresh baseline.
    func revertSession() {
        au?.cancelEditSession(); sel.reset(); syncAnchor()
        au?.beginEditSession(); refreshFromDocument()
    }

    /// SINGLE-mode editing (design ferry 2026-08-06): while in SINGLE (ladder) + ADD/EDIT, the SELECTION drives each
    /// column's ACTIVE rung — for every column that holds a selected cell, the TOPMOST (upper = smallest row index)
    /// selected cell becomes active (it plays) and the rest of that column mutes. Lower selected cells stay in the
    /// set (they keep the animated selection border) but read as muted (dormant, via the ladder). The activation
    /// writes `activeRow`, which rides the STANDING TRANSACTION — APPLY persists it, CANCEL reverts it with
    /// everything else (cancelEditSession restores the whole document). MULTI editing is untouched.
    func syncSingleModeActivation() {
        // NOT on the DRAG&DROP page: there the selection is the WHOLE colour, so deriving the active rung from it would
        // activate every column the colour occupies (user 2026-08-09 bug). The DD grid sets the rung via armLadderRung.
        guard ladderMode, editMode == .addEdit, activeTab != .dragDrop, let au else { return }
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
    func toggleLoopColumn(_ c: Int) { setLane(laneMask ^ (1 << UInt8(c))) }

    // The grid instance for the spike page — the same GridView component. In EDIT mode a tap builds the selection
    // set (white ring) AND auto-selects the tapped cell's TWINS (user 2026-08-07: they JOIN the selection — the
    // advertise-pulse is gone; deselect one to decouple it). A long-press drops the ANCHOR; CLEAR marks show a red ✕.
    @ViewBuilder func spikeGrid(_ cellHeight: CGFloat) -> some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn,
                 trueColumn: d.playing ? ((d.absoluteStep % 8) + 8) % 8 : -1, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: false,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onAuditionStart: editGridLongPress, onAuditionEnd: editGridLongEnd,
                 laneMask: laneMask, onColumnKey: toggleLoopColumn, holdLatch: false,
                 onMoveCell: editMode == .move ? moveCell : nil, moveMode: editMode == .move, flagNoDest: false, animateSelection: true,
                 showAddPlus: editMode == .addEdit && !sel.isEmpty,
                 cellHitAt: cellHitAt, cellHitVel: cellHitVel,   // SEAL comet feed
                 cellSounding: cellSounding, cellReleasedAt: cellReleasedAt,   // SEAL comet gate

                 whiteBorder: sel.asSet, ladderDim: ladderDim, verbInvite: nil,   // LADDER: dim dormant rungs + no playhead in EDIT too
                 routeFoci: [], routeIn: [], routeOut: [],
                 tapAltMask: tapAltMask, tapMuteMask: tapMuteMask,
                 strokeActive: false, onStroke: strokeCell, onStrokeEnd: endStroke)
    }
    /// MOVE mode — drag a cell to a new position; drop over a populated cell OVERWRITES it (the moved cell wins;
    /// the source is left empty). Immediate + undoable. (User 2026-08-07: overwrite, not swap.)
    func moveCell(_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) {
        guard from.col != to.col || from.row != to.row else { return }
        au?.editScene { s in
            let moved = s.cellAt(from.col, from.row)
            s.setCell(to.col, to.row, moved)          // overwrite the destination
            s.setCell(from.col, from.row, nil)        // clear the source
        }
        refreshFromDocument()
    }

    // CELL MACHINE (feat/EditPageSpike): the selected cell's processor CHAIN as a VERTICAL STACK of slot boxes,
    // each 50% of screen width, head first, plus [+ ADD] (≤ 8 slots). Stage 1 renders the HEAD; slots 2…8 are
    // stored + editable but not yet executed (serial run is Phase 2). Reuses ProcessorBox in `slotMode`.
    func cellChain(_ cell: Cell) -> [ProcessorSlot] {         // the cell's effective chain — the engine's 3-tier resolution
        if let p = cell.processors { return p }                       // per-cell OVERRIDE (incl. an EXPLICIT empty chain = passthrough)
        let c = docColours.first { $0.colourID == cell.colourID }
        if let t = c?.templateChain, !t.isEmpty { return t }          // colour TEMPLATE (the per-colour machine — matches the builder)
        return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())]   // legacy A face
    }
    @ViewBuilder func chainStack(_ cell: Cell, boxWidth: CGFloat) -> some View {
        let chain = cellChain(cell)
        VStack(alignment: .leading, spacing: 8) {
            twinHeader()
            if chain.isEmpty {                                   // MODE ROW: an EMPTY chain = passthrough — an INVITATION, never a "PASS" slot
                emptyChainInvitation(boxWidth: boxWidth)
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { i, slot in
                    slotBox(i, slot, cell: cell).frame(width: boxWidth)
                }
                if chain.count > 1 {   // the chain runs end-to-end for every tail type
                    Text("Chain runs in series, head→tail.")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if chain.count < 8 {                             // ADD MORE — a GHOST SLOT: a dim outlined box the width of a
                    VStack(alignment: .leading, spacing: 8) {    // processor window (the invitation grammar — the next empty slot waiting)
                        Text("+ ADD PROCESSOR").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(mainDestHue)
                        processorTypeRow(boxWidth: boxWidth - 20)
                    }
                    .padding(10).frame(width: boxWidth, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(mainDestHue.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .padding(.top, 4)
                }
            }
        }
    }
    // MODE ROW — the newborn/empty-chain invitation: the cell already SOUNDS (passthrough). A big, friendly emblem
    // TYPE SELECTOR; picking a type adds it as the first slot (across the whole selection).
    @ViewBuilder func emptyChainInvitation(boxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PASSING MIDI THROUGH UNTREATED — PICK A PROCESSOR TO SHAPE IT")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            processorTypeRow(boxWidth: boxWidth)
        }
    }
    // The big, bold processor TYPE selector — one emblem per type; tapping appends that type to the selection's
    // chain(s). Shared by the empty-cell invitation AND the "add another processor" control (not a default passgate).
    @ViewBuilder func processorTypeRow(boxWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(ProcessorType.allCases, id: \.self) { t in
                Button { chainAddSlot(type: t) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: emblemSymbol(t)).font(.system(size: 22, weight: .black))
                        Text(t.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundColor(mainDestHue).frame(maxWidth: .infinity).frame(height: 62)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(mainDestHue.opacity(0.45), lineWidth: 1.5))
                }.buttonStyle(.plain)
            }
        }.frame(width: boxWidth)
    }
    // MODE ROW — the selection header: how many cells this edit touches. Twins of the set PULSE on the grid to
    // invite inclusion (they are NOT auto-edited — the user taps to add them). No DETACH: the set is manual.
    @ViewBuilder func twinHeader() -> some View {
        let n = sel.count
        HStack(spacing: 8) {
            Text(n > 1 ? "\(n) SELECTED" : (n == 1 ? "1 SELECTED" : "—"))
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(n > 1 ? Self.editHue : .white.opacity(0.55))
            Spacer(minLength: 0)
        }
    }
    // The active edit SCOPE for machine edits. On the DRAG&DROP page a colour IS a machine — edits are GLOBAL, so they
    // write the colour's TEMPLATE chain (and clear every per-cell override across all scenes) → every cell of the
    // colour, in every scene, stays uniform. Elsewhere (the PROCESSORS tab's manual selection) edits apply per-cell.
    // (user 2026-08-09: processor settings must change uniformly across all instances of a colour.)
    private var editColourScoped: Bool { activeTab == .dragDrop }
    // On the DRAG&DROP page use the SELECTED palette colour (works even before the colour has a placed cell — its
    // machinery is always shown on a synthetic cell); elsewhere fall back to the anchor cell's colour.
    private var editScopeColourID: String? { (activeTab == .dragDrop ? ddSelectedColourID : nil) ?? editingCell?.colourID }
    func chainAddSlot(type: ProcessorType) {
        if editColourScoped, let cid = editScopeColourID { au?.addSlotColour(cid, type: type) } else { au?.addSlotCells(editSelTargets, type: type) }
        refreshFromDocument()
    }
    func chainSetType(slot i: Int, _ type: ProcessorType) {
        if editColourScoped, let cid = editScopeColourID { au?.setSlotTypeColour(cid, slot: i, type) } else { au?.setSlotTypeCells(editSelTargets, slot: i, type) }
        refreshFromDocument()
    }
    func chainToggleBypass(slot i: Int) {
        if editColourScoped, let cid = editScopeColourID { au?.toggleSlotBypassColour(cid, slot: i) } else { au?.toggleSlotBypassCells(editSelTargets, slot: i) }
        refreshFromDocument()
    }
    func chainRemoveSlot(slot i: Int) {
        if editColourScoped, let cid = editScopeColourID { au?.removeSlotColour(cid, slot: i) } else { au?.removeSlotCells(editSelTargets, slot: i) }
        refreshFromDocument()
    }
    func chainEditSlot(slot i: Int, _ mutate: @escaping (inout ProcessorSlot) -> Void) {
        if editColourScoped, let cid = editScopeColourID { au?.editSlotColour(cid, slot: i, mutate) } else { au?.editSlotCells(editSelTargets, slot: i, mutate) }
        refreshFromDocument()
    }
    func chainReplace(_ chain: [ProcessorSlot]) {
        if editColourScoped, let cid = editScopeColourID { au?.withChainColour(cid) { $0 = chain } } else { au?.editCells(editSelTargets) { $0.processors = chain } }
        refreshFromDocument()
    }

    @ViewBuilder func slotBox(_ i: Int, _ slot: ProcessorSlot, cell: Cell,
                              plainTitle: Bool = false, showMacro: Bool = true, onEdited: (() -> Void)? = nil,
                              onRemoved: (() -> Void)? = nil) -> some View {
        let sc: Colour = { var c = Colour(colourID: cell.colourID, type: slot.type); c.paramsA = slot.params; return c }()
        let cid = cell.colourID
        ProcessorBox(
            colour: sc, colourIndex: -1, face: .a,
            onEdit: { mutate in
                chainEditSlot(slot: i) { s in
                    var tmp = Colour(colourID: cid, type: s.type); tmp.paramsA = s.params
                    mutate(&tmp); s.params = tmp.paramsA                    // slotMode edits only paramsA
                }
                onEdited?()                                                // pop-up: re-snapshot the macro BASE from the edited params
            },
            onTranspose: { _ in }, onMorph: { _ in },
            onSetTypeA: { t in chainSetType(slot: i, t) },
            height: 260, slotMode: true, slotBypassed: slot.bypassed,
            accentOverride: mainDestHue,               // same blue as the emitters
            passHead: d.playing ? (d.pass & 3) : -1,   // MODE ROW: the passgate playhead follows the live pass
            onBypass: { chainToggleBypass(slot: i) },
            // user 2026-08-09: EVERY slot is deletable, incl. the head — deleting the last one leaves an empty passthrough.
            onRemove: { chainRemoveSlot(slot: i); onRemoved?() },
            onMacro: showMacro ? { openMacroAuthoring(slot: i, slotData: slot) } : nil, plainTitle: plainTitle)
    }

    // MARK: - MACRO AUTHORING (canonical pop-up) — open/callbacks for a processor slot. The BASE = the slot's current
    // values (untouched by authoring — the offset model: a binding stores delta = target − base). Bindings commit
    // LIVE so the in-pop-up macro panel is interactive; the pop-up's CANCEL restores the whole macros vector +
    // the base params (nothing escapes CANCEL). The audition sounds the slot live (hold keys) at the test values.
    // Wire the macro authoring data for a slot (group · base · macro baseline · existing bindings). Shared by the
    // standalone pop-up (chain stack) and the EMBEDDED section in the flow-diagram processor pop-up.
    func setupMacroAuthoring(slot i: Int, slotData slot: ProcessorSlot) {
        guard let a = sel.anchor else { return }
        macroAuthorAnchor = (a.col, a.row); macroAuthorSlot = i
        macroAuthorGroup = macroGroupForProcessor(col: a.col, row: a.row, slot: i, type: slot.type)
        macroAuthorBase = processorValues(slot)                       // the processor's CURRENT values (the offset base)
        macroAuthorMacrosBaseline = au?.uiMacros() ?? []              // snapshot every macro — CANCEL restores this
        macroAuthorExisting = macroSlotBindings(macroAuthorMacrosBaseline, col: a.col, row: a.row, slot: i)   // the dropdown + reflect
    }
    func openMacroAuthoring(slot i: Int, slotData slot: ProcessorSlot) {
        guard let a = sel.anchor else { return }
        setupMacroAuthoring(slot: i, slotData: slot)
        au?.setAudition(col: a.col, row: a.row)
        macroAuthorOpen = true
    }
    /// TEST audition — set the slot's live params to the per-param morphed test values (selected params morphed
    /// base→target by their test slider; the rest at base). The base is never rewritten; this is transient audio.
    func macroAuthorPreview(_ values: [String: Double]) {
        au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { $0 = applyProcessorValues(values, to: $0) }
    }
    /// BIND the selected params' deltas (target − base) to a macro — committed LIVE (the panel is interactive).
    /// Continuous (foldable) keys bind through addMacroTargets today; discrete keys are the future button path.
    func macroAuthorBind(_ macroIndex: Int, _ deltas: [String: Double]) {
        au?.removeMacroTargets(macroIndex, col: macroAuthorAnchor.col, row: macroAuthorAnchor.row, slot: macroAuthorSlot)   // idempotent: replace this slot's binding
        let foldable = Set(MacroParam.allCases.map(\.rawValue))   // the continuous params that fold through the engine (single source: MacroParam)
        let targets: [MacroTarget] = deltas.compactMap { k, d in
            (foldable.contains(k) && d != 0) ? MacroTarget(col: macroAuthorAnchor.col, row: macroAuthorAnchor.row, slot: macroAuthorSlot, param: k, delta: d) : nil
        }
        // A freshly-bound macro stays at its current VALUE (0 by default) — the offset is authored but SILENT until
        // it's driven from the grid slider (user ruling 2026-08-09: don't jump the sound on bind).
        if !targets.isEmpty { au?.addMacroTargets(macroIndex, targets); au?.setMacroFixed(macroIndex, macroIndex >= 8) }
        refreshFromDocument()
    }
    /// UNBIND — "Remove from M{n}": drop THIS slot's targets on this macro (reflected live in the MIDI out).
    func macroAuthorUnbind(_ macroIndex: Int) {
        au?.removeMacroTargets(macroIndex, col: macroAuthorAnchor.col, row: macroAuthorAnchor.row, slot: macroAuthorSlot)
        refreshFromDocument()
    }
    /// Live macro drag inside the pop-up (moves the bound params through the offset).
    func macroAuthorSetMacro(_ index: Int, _ value: Double) { au?.setMacroValue(index, value) }
    func closeMacroAuthoring(apply: Bool) {
        if !apply { au?.setMacrosDocument(macroAuthorMacrosBaseline.isEmpty ? nil : macroAuthorMacrosBaseline) }   // revert every macro change
        au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { $0 = applyProcessorValues(macroAuthorBase, to: $0) }   // restore the base (audition → off)
        au?.clearAudition()
        macroAuthorOpen = false; macroAuthorGroup = nil; macroAuthorMacrosBaseline = []
        refreshFromDocument()
    }

    func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)   // device round 2: bigger, legible
            Rectangle().fill(Self.editHue.opacity(0.25)).frame(height: 1)
        }.padding(.top, 4)
    }
    // A MIDI IN/OUT section header — the DIN plug mark (outline variant) beside the label (design ferry SPEC-din-icon).
    func midiSectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            dinMark(outline: true, ink: Self.editHue, size: 20)
            Text(label).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)
            Rectangle().fill(Self.editHue.opacity(0.25)).frame(height: 1)
        }.padding(.top, 4)
    }
    // The CHAIN section header carries the LIBRARY button at its top-right (moved off the page header).
    @ViewBuilder func chainSectionHeader() -> some View {
        HStack(spacing: 8) {
            Text("CHAIN").font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)
            Rectangle().fill(Self.editHue.opacity(0.25)).frame(height: 1)
            // ([AB] popup retired 2026-08-06 — superseded by the MACRO button on each processor slot, which opens
            //  the canonical MAIN/ALT authoring flow. The LIBRARY button stays.)
            Button { openCellLibrary() } label: {
                Text("LIBRARY").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Self.editHue.opacity(0.14)))
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }
    // MARK: - THE FLOW DIAGRAM (cell-edit redesign; design ferry GUIDANCE-signal-flow-tidy §8 THE SNAKE, 2026-08-07).
    // §8 SUPERSEDES the spine: ONE continuous DOTTED line, a boustrophedon S-path the eye follows; boxes are stations
    // on it. ROW 1 L→R: [ID cell] → [RECEIVERS box, channels prominent] → [+ IN FILTER ghost]; the line drops + runs
    // LEFT to the chain's left. ROW 2 L→R: ALL EIGHT slots (solid=set · dashed "+"=empty — supersedes the one-ghost
    // rule for this diagram), the line threading through. Drops from slot 8's right into ROW 3 R→L: [+ OUT FILTER] →
    // [EMITTERS box]. THE LINE LAW: one dotted thread, no branches. §4 R/OUT chips toggle in place. Filters are inert
    // ghosts (no engine). Dims fitted to the page column — the full §6/§7 (96×56 slots, 976 usable) needs the page-
    // wide relayout, owed.
    // Layout (user 2026-08-07 revisions): NO title. The SELECTED-CELL indicator (ID cell) is LEFT-aligned, bigger,
    // and RECTANGULAR (grid-cell proportions); the signal flow is CENTRED. RECEIVERS centred at top → the INPUT FILTER
    // box immediately BELOW them (dotted connector) → the 8 PROCESSOR boxes (the dotted line enters their LEFT, exits
    // their RIGHT) → the OUTPUT FILTER (centred, above emitters) → the EMITTERS box (centred). One dotted thread; every
    // box is OPAQUE so the line is hidden wherever it passes behind one. Receiver/emitter/processor boxes ~doubled.
    @ViewBuilder func flowDiagram(_ cell: Cell, width: CGFloat) -> some View {
        let chain = cellChain(cell)
        let bg = Color(red: 0.066, green: 0.075, blue: 0.094)   // the page background — opaque box fills occlude the line
        let hue = colourColor(cell.colourID) ?? mainDestHue     // the SELECTED colour tints the thread + the R/E box frames (user 2026-08-09)
        let idW: CGFloat = 120   // reserves the (now-hidden) ID-cell margin so RECEIVERS stays clear of the left
        let flowW = min(max(280, width), 1040)
        GeometryReader { g in
            let W = g.size.width
            let recvW = min(max(300, W - 2 * idW - 40), 660)     // receiver/emitter boxes ~doubled, centred, clear of the ID cell
            let gap: CGFloat = 6
            let sw = max(40, (W - 7 * gap) / 8)                  // 8 processor slots span the width (user 2026-08-09: restored from 4)
            let yRecv: CGFloat = 32, yProc: CGFloat = 130, yEm: CGFloat = 236   // OUTPUT FILTER removed → emitters pulled up (user 2026-08-09)
            ZStack(alignment: .topLeading) {
                Path { p in                                      // ONE continuous dotted thread that traces the FLOW (user 2026-08-09)
                    let firstX = sw / 2                          // centre of the first processor
                    let lastX = 7 * (sw + gap) + sw / 2          // centre of the last (8th) processor
                    let yTop: CGFloat = 82                       // the turn between the receivers and the processor row
                    let yBot: CGFloat = 192                      // the turn between the processor row and the emitters
                    // DOWN from the receivers' centre-bottom → LEFT → DOWN into the TOP of the first processor.
                    p.move(to: CGPoint(x: W / 2, y: 55)); p.addLine(to: CGPoint(x: W / 2, y: yTop))
                    p.addLine(to: CGPoint(x: firstX, y: yTop)); p.addLine(to: CGPoint(x: firstX, y: yProc))
                    // THROUGH each processor (occluded by the boxes, showing in the gaps) to the last.
                    p.addLine(to: CGPoint(x: lastX, y: yProc))
                    // Emerge at the BOTTOM CENTRE of the last processor → DOWN → LEFT → DOWN to the emitters' TOP CENTRE.
                    p.addLine(to: CGPoint(x: lastX, y: yBot)); p.addLine(to: CGPoint(x: W / 2, y: yBot)); p.addLine(to: CGPoint(x: W / 2, y: 213))
                }.stroke(hue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                // (SELECTED-CELL indicator + INPUT/OUTPUT FILTER removed — user 2026-08-07/09; the flow is RECEIVERS → PROCESSORS → EMITTERS.)
                receiverBox(cell, bg: bg).frame(width: recvW, height: 45).position(x: W / 2, y: yRecv)            // RECEIVERS (centred, −25% height)
                ForEach(0..<8, id: \.self) { i in                                                                // PROCESSORS (8 slots)
                    slotOrGhost(i, chain, bg: bg, hue: hue).frame(width: sw, height: 38).position(x: CGFloat(i) * (sw + gap) + sw / 2, y: yProc)   // −25% then −20% height (user 2026-08-09)
                }
                emitterBox(cell, bg: bg).frame(width: recvW, height: 45).position(x: W / 2, y: yEm)               // EMITTERS (centred, −25% height)
            }
        }
        .frame(width: flowW, height: 268)
    }
    // A set slot (tap → edit pop-up) or an empty dashed "+" ghost (tap → type picker) — user 2026-08-07.
    @ViewBuilder private func slotOrGhost(_ i: Int, _ chain: [ProcessorSlot], bg: Color, hue: Color) -> some View {
        if i < chain.count {
            flowSlot(chain[i], bg: bg, hue: hue).contentShape(Rectangle()).onTapGesture { openProcEdit(slot: i) }
        } else {
            flowGhost("+", bg: bg, plus: false, hue: hue).contentShape(Rectangle()).onTapGesture { procTypePickerOpen = true }
        }
    }
    // FLOW-DIAGRAM processor pop-up — tap a populated box to edit its FULL controls (same ProcessorBox as the chain
    // editor: big, legible, per-type). Title + BYPASS in the box's title row; the MACRO section (add/dropdown +
    // authoring) at the FOOT of the form; APPLY/CANCEL below it. ONE transaction: CANCEL reverts the whole document
    // snapshot (processor edits AND macro edits together, per the user's ruling 2026-08-08).
    func openProcEdit(slot i: Int) {
        procEditSlot = i
        procEditDocBaseline = au?.uiDocument()          // CANCEL restores this exactly (params + macros)
        procMacroEngaged = false
        if let cell = editingCell, i < cellChain(cell).count { setupMacroAuthoring(slot: i, slotData: cellChain(cell)[i]) }
        procEditOpen = true
    }
    // The macro morph auditions the cell live — started only when the macro section is opened, cleared on close.
    func procMacroEngage() {
        guard let a = sel.anchor else { return }
        au?.setAudition(col: a.col, row: a.row)
        procMacroEngaged = true
    }
    func closeProcEdit(apply: Bool) {
        if procMacroEngaged {
            au?.clearAudition()
            // slot → BASE: clears any unbound morph residue. macroAuthorBase tracks ProcessorBox param edits (onEdited),
            // so this KEEPS the edits while the macro holds its delta as an offset. (Editing params AFTER binding a
            // macro in the same session is not fully reconciled — author macros as the last step. Flagged.)
            if apply { chainEditSlot(slot: procEditSlot) { $0 = applyProcessorValues(macroAuthorBase, to: $0) } }
        }
        if !apply, let b = procEditDocBaseline { au?.restoreDocument(b) }   // revert every edit since it opened
        procEditOpen = false; procEditDocBaseline = nil; procMacroEngaged = false; macroAuthorGroup = nil
        refreshFromDocument()
    }
    @ViewBuilder func procEditPopup() -> some View {
        let chain = editingCell.map { cellChain($0) } ?? []
        if let cell = editingCell, procEditSlot < chain.count {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { closeProcEdit(apply: true) }   // scrim = keep
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            slotBox(procEditSlot, chain[procEditSlot], cell: cell,
                                    plainTitle: true, showMacro: false,
                                    onEdited: { if let c = editingCell, procEditSlot < cellChain(c).count { macroAuthorBase = processorValues(cellChain(c)[procEditSlot]) } },
                                    onRemoved: { closeProcEdit(apply: true) })   // deleting the shown slot closes the pop-up
                            if let g = macroAuthorGroup {                 // the MACROS section — folded in at the FOOT (user 2026-08-08)
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                MacroAuthoringView(group: g, macros: au?.uiMacros() ?? [], existing: macroAuthorExisting,
                                                   accent: mainDestHue, base: macroAuthorBase,
                                                   onPreview: macroAuthorPreview, onBind: macroAuthorBind, onUnbind: macroAuthorUnbind,
                                                   onSetMacro: macroAuthorSetMacro, onClose: { _ in },
                                                   embedded: true, onEngage: procMacroEngage)
                            }
                        }.padding(14)
                    }
                    HStack(spacing: 10) {
                        Spacer()
                        Button { closeProcEdit(apply: false) } label: { transactChip("CANCEL", enabled: true, fill: false) }.buttonStyle(.plain)
                        Button { closeProcEdit(apply: true) } label: { transactChip("APPLY", enabled: true, fill: true) }.buttonStyle(.plain)
                    }.padding(14)
                }
                .frame(maxWidth: 560, maxHeight: 760)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(mainDestHue.opacity(0.4), lineWidth: 1))
                .padding(20)
            }
        }
    }
    // The welcoming TYPE PICKER for an empty box — the same big emblem buttons as the current cell edit page's
    // "add processor" invitation. Picking a type appends the slot; the picker closes.
    @ViewBuilder func procTypePickerPopup() -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { procTypePickerOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                Text("ADD A PROCESSOR").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(mainDestHue)
                Text("Pick a processor to shape the signal.").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                HStack(spacing: 10) {
                    ForEach(ProcessorType.allCases, id: \.self) { t in
                        Button {
                            let newIdx = editingCell.map { cellChain($0).count } ?? 0   // the slot the append will create
                            chainAddSlot(type: t)
                            procTypePickerOpen = false
                            openProcEdit(slot: newIdx)                                   // straight into the edit form (user 2026-08-08)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: emblemSymbol(t)).font(.system(size: 26, weight: .black))
                                Text(t.rawValue).font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundColor(mainDestHue).frame(maxWidth: .infinity).frame(height: 84)
                            .background(RoundedRectangle(cornerRadius: 10).fill(mainDestHue.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(mainDestHue.opacity(0.5), lineWidth: 1.5)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(18).frame(maxWidth: 620)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(mainDestHue.opacity(0.4), lineWidth: 1))
            .padding(20)
        }
    }
    // The OUTPUT SPLIT editor (user 2026-08-09) — the MAIN destination · the 8×3 CHOP grid · the ALT destination,
    // lifted off the cell-edit page into an add-processor-style pop-up so the under-flow-diagram sections can retire.
    // Reached by tapping the emitters' SPLIT affordance in the flow diagram. Edits are LIVE (the same setters as the
    // old inline block); DONE / scrim-tap closes.
    @ViewBuilder func splitEditorPopup(_ cell: Cell) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { splitEditorOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                Text("OUTPUT SPLIT").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(mainDestHue)
                Text("Redirect each of the 8 slices to the MAIN emitters, MUTE, or the ALT destination.")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                outputSection(cell, emitterWidth: 480)
                HStack {
                    Spacer()
                    Button { splitEditorOpen = false } label: { transactChip("DONE", enabled: true, fill: true) }.buttonStyle(.plain)
                }
            }
            .padding(18).frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(mainDestHue.opacity(0.4), lineWidth: 1))
            .padding(20)
        }
    }
    // Styled EXACTLY like the emitter box (user 2026-08-09): opaque dark fill + a selected-colour frame, cornerRadius 10.
    private func flowSlot(_ slot: ProcessorSlot, bg: Color, hue: Color) -> some View {
        VStack(spacing: 1) {
            Text(slot.type.rawValue).font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)   // emblem icon removed (user 2026-08-09)
        }
        .foregroundColor(.white.opacity(0.9)).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg))                  // OPAQUE occluder — matches the emitter box
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hue.opacity(0.7), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if slot.bypassed { Circle().fill(.white.opacity(0.5)).frame(width: 7, height: 7).padding(3) }   // bypass dot
        }
    }
    // The RECEIVERS box — R1–R4 with the MIDI CHANNEL prominent; selected lit; OPAQUE (occludes the line). Toggles in place.
    private func receiverBox(_ cell: Cell, bg: Color) -> some View {
        let recvs = au?.uiReceivers() ?? []
        let hue = colourColor(cell.colourID) ?? mainDestHue     // frame in the SELECTED colour (user 2026-08-09)
        return HStack(spacing: 8) {
            dinMark(ink: .white.opacity(0.5), size: 26)   // MIDI IN mark (left)
            ForEach(0..<4, id: \.self) { r in
                let on = cell.inputReceiver == r
                let ch = r < recvs.count ? recvs[r].channel : 0
                VStack(spacing: 1) {
                    Text("R\(r + 1): MIDI IN").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(ch == 0 ? "OMNI" : "CH\(ch)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(on ? .black : .white.opacity(0.78)).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? (r < receiverHues.count ? receiverHues[r] : mainDestHue) : Color.white.opacity(0.06)))
                .contentShape(Rectangle()).onTapGesture { editPointedCell { $0.inputRow = nil; $0.inputReceiver = r } }
            }
        }.padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg))                  // OPAQUE occluder
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hue.opacity(0.7), lineWidth: 1.5))
    }
    // The EMITTERS box — mirror of the receivers box (in/out symmetry): A–D with channels prominent. Toggles in place.
    private func emitterBox(_ cell: Cell, bg: Color) -> some View {
        let hue = colourColor(cell.colourID) ?? mainDestHue     // frame in the SELECTED colour (user 2026-08-09)
        return HStack(spacing: 8) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { i, b in
                let on = cell.buses.contains(b)
                VStack(spacing: 1) {
                    Text("\(b.rawValue): MIDI OUT").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)
                    Text("CH\(i < busChannels.count ? busChannels[i] : i + 1)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(on ? .black : .white.opacity(0.78)).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? mainDestHue : Color.white.opacity(0.06)))
                .contentShape(Rectangle()).onTapGesture { toggleMainBus(b) }
            }
            splitAffordance()                              // → the OUTPUT SPLIT editor (user 2026-08-09)
        }.padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg))                  // OPAQUE occluder
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hue.opacity(0.7), lineWidth: 1.5))
    }
    // The SPLIT affordance on the emitters box — opens the OUTPUT SPLIT pop-up (extracted so emitterBox type-checks).
    private func splitAffordance() -> some View {
        let dashed = RoundedRectangle(cornerRadius: 6).strokeBorder(mainDestHue.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        return Button { splitEditorOpen = true } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 15, weight: .heavy))
                Text("SPLIT").font(.system(size: 8, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(mainDestHue).frame(width: 48).frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(mainDestHue.opacity(0.14)).overlay(dashed))
        }.buttonStyle(.plain)
    }
    // The cell face, drawn to MATCH the grid cells (the same mosaic + seal hash); rectangular via the caller's frame.
    private func flowCellFace(_ cell: Cell) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(colourColor(cell.colourID) ?? .gray)
            .overlay(Canvas { ctx, sz in
                let mh = UInt64(sealHash(cell, colours: docColours)); let ch = colourColor(cell.colourID) ?? .gray
                drawMosaic(hash: mh, into: ctx, size: sz, hue: ch, breath: 0, crest: mosaicCrest(hash: mh), crestTone: mosaicCrestTone(ch))
            }.padding(5))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.75), lineWidth: 2.5))
    }
    // The UNIFIED GHOST — a dashed, OPAQUE box that fills its frame. Dashed = the stage doesn't exist yet. `plus` adds
    // a trailing plus icon after the label (the Output Filter reads "Output Filter +"); pass a "+" label with plus:false
    // for a plus-only box (the processor ghost, user 2026-08-09).
    private func flowGhost(_ label: String, bg: Color, plus: Bool = true, hue: Color? = nil) -> some View {
        let h = hue ?? mainDestHue
        return HStack(spacing: 4) {
            Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)
            if plus { Image(systemName: "plus").font(.system(size: 11, weight: .heavy)) }     // the ADD affordance
        }
        .foregroundColor(h.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg)               // OPAQUE occluder — matches the emitter box
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(h.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))))
    }
    // B5 — a top-level accordion section (one open at a time). `summary` shows on the collapsed header.
    // C — IDENTITY section: swatch · name · position, then §I UTILITIES (apply the input shaping across scope ·
    // reset · delete). Triggers already propagate Colour-wide, so "apply to scope" carries the CELL-level input
    // shaping (chord split + velocity window) to the exemplar's twins / all same-colour cells.
    @ViewBuilder func identitySection(_ cell: Cell, swatch sw: CGFloat) -> some View {
        // The chosen-colour BOX (same footprint as the picker grid), the ALWAYS-VISIBLE 4×4 picker (swatches 50%
        // smaller), and the selection COUNT + how many identical (unselected twin) cells are available to add.
        let s2 = max(18, sw * 0.5)                         // the colour grid, 50% smaller
        let gap: CGFloat = 5
        let box = s2 * 4 + gap * 3                          // the 4×4 grid's footprint = the chosen box's size
        HStack(alignment: .center, spacing: 14) {
            // The chosen-colour box hosts the cell's SEAL, drawn to MATCH the grid cells: a landscape (wider-than-tall)
            // engraved plate with the SAME BLACK ink (user: it must match the cells, not show white/square). A config
            // change (new hash) CROSSFADES the seal (~250ms). (The arc-length re-route glide of §4 is deferred polish.)
            RoundedRectangle(cornerRadius: 8).fill(colourColor(cell.colourID) ?? .gray).frame(width: box, height: box)
                .overlay(
                    Group {
                        if useMosaicFace {                                                                   // THE MOSAIC — match the grid cells (candidate F, branch)
                            Canvas { ctx, size in
                                let mh = UInt64(sealHash(cell, colours: docColours)); let ch = colourColor(cell.colourID) ?? .gray
                                drawMosaic(hash: mh, into: ctx, size: size, hue: ch, breath: 0,
                                           crest: mosaicCrest(hash: mh), crestTone: mosaicCrestTone(ch))
                            }
                            .frame(width: box - 12, height: box - 12)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.14))            // engraved plate (as cells)
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                                Canvas { ctx, size in
                                    drawSeal(sealGeometry(sealHash(cell, colours: docColours)), into: ctx, size: size, padFraction: 0.16, stroke: 2.8, ink: sealInk)
                                }
                            }
                            .frame(width: box - 16, height: (box - 16) * 0.62)                               // landscape — matches the cell seal's dims
                        }
                    }
                    .id(sealHash(cell, colours: docColours)).transition(.opacity)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.75), lineWidth: 2.5))
                .animation(.easeInOut(duration: 0.25), value: sealHash(cell, colours: docColours))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(s2), spacing: gap), count: 4), spacing: gap) {
                ForEach(colourIDs, id: \.self) { id in
                    let on = cell.colourID == id
                    RoundedRectangle(cornerRadius: 5).fill(colourColor(id) ?? .gray).frame(width: s2, height: s2)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(on ? 0.95 : 0.14), lineWidth: on ? 2.5 : 1))
                        .contentShape(Rectangle()).onTapGesture { setCellColour(id) }
                }
            }.fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                Text(sel.count == 1 ? "1 CELL SELECTED" : "\(sel.count) CELLS SELECTED")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
    func setCellColour(_ id: String) {   // applies to the whole selection set
        au?.editCells(editSelTargets) { $0.colourID = id }
        brush = id; refreshFromDocument()
    }
    // D — INPUT section: source · shift (the chord-split + velocity-window "splits" were removed — a future processor).
    @ViewBuilder func inputSection(_ cell: Cell) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            receiverRadio(cell)          // §2 A–D receiver radio in the identity hues (+ NONE)
            inputShiftRow
            // The MIDI-IN SPLITS (chord split · velocity window) are removed here — they'll return as a standalone
            // processor in the chain. `chordSplitRow`/`velWindowRow` stay defined but unused (behaviour preserved).
        }
    }
    // §2 the receiver radio — MIDI-IN R1–R4 as chips wearing the RECEIVER IDENTITY HUES (slate/purple/green/tan),
    // + a NONE chip. Twin-aware (edits the pointed cell + its twins via editPointedCell).
    func receiverRadio(_ cell: Cell) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cable.connector").font(.system(size: 16)).foregroundColor(.white.opacity(0.4))
            ForEach(0..<4, id: \.self) { r in
                let on = cell.inputReceiver == r
                Text("R\(r + 1)").font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? mainDestHue : mainDestHue.opacity(0.18)))   // same blue as the emitters
                    .contentShape(Rectangle()).onTapGesture { editPointedCell { $0.inputRow = nil; $0.inputReceiver = r } }
            }
            Text("—").font(.system(size: 15, weight: .heavy, design: .monospaced))   // NONE (unrouted)
                .foregroundColor(cell.inputReceiver == nil ? .black : .white.opacity(0.5))
                .frame(width: 44, height: 42)
                .background(RoundedRectangle(cornerRadius: 7).fill(cell.inputReceiver == nil ? Color.white.opacity(0.55) : Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { editPointedCell { $0.inputRow = nil; $0.inputReceiver = nil } }
        }
    }
    // F — OUTPUT: MAIN destination toggles (live, edit cell.buses) · the CHOP 8×3 grid + ALT destination. The chop
    // routing engine IS wired: tick cells (arp/ratchet/strum) route per-slice; a HOLD cell routes by its onset slice.
    var mainDestHue: Color { Color(red: 0.15, green: 0.88, blue: 0.94) }   // cyan — the emitters
    enum ChopRow { case main, alt, mute }
    /// The OUTPUT block — MAIN dest · the 8×3 CHOP grid · ALT dest — CENTRED at the emitter section's width so it
    /// lines up over the MIDI OUTPUT strips below (user 2026-07-31). Each slice column: TOP → the cell's own (MAIN)
    /// emitters · MIDDLE → MUTE · BOTTOM → the ALT DESTINATION set (chosen below). The routing runs in the engine.
    @ViewBuilder func outputSection(_ cell: Cell, emitterWidth: CGFloat) -> some View {
        let chop = cell.chopResolved
        VStack(alignment: .leading, spacing: 8) {            // §6 left-aligned with the page grammar (was centred)
            Text("MAIN DESTINATION").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 6) { ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { i, b in   // §2 A–D toggles + channel tags
                VStack(spacing: 3) {
                    busToggle(b.rawValue, on: cell.buses.contains(b), hue: mainDestHue) { toggleMainBus(b) }
                    Text("ch\(i < busChannels.count ? busChannels[i] : i + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                }.frame(maxWidth: .infinity)
            } }
            VStack(spacing: 3) {                             // the 8×3 CHOP grid — one column per slice; rows are INDEPENDENT
                HStack(spacing: 3) { ForEach(0..<8, id: \.self) { chopCell($0, .main, chop) } }   // TOP = MAIN dest
                HStack(spacing: 3) { ForEach(0..<8, id: \.self) { chopCell($0, .mute, chop) } }   // MIDDLE = MUTE
                HStack(spacing: 3) { ForEach(0..<8, id: \.self) { chopCell($0, .alt,  chop) } }   // BOTTOM = ALT dest
            }
            Text("ALT DESTINATION").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 6) { ForEach(Bus.allCases, id: \.self) { b in busToggle(b.rawValue, on: chop.altDest.contains(b), hue: Self.editHue) { editChop { if $0.altDest.contains(b) { $0.altDest.remove(b) } else { $0.altDest.insert(b) } } } } }
        }
        .frame(maxWidth: emitterWidth, alignment: .leading)
    }
    func busToggle(_ label: String, on: Bool, hue: Color, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.6))
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? hue : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    @ViewBuilder func chopCell(_ i: Int, _ row: ChopRow, _ chop: Chop) -> some View {
        let bit = UInt8(1) << UInt8(i)
        let on: Bool = row == .main ? (chop.mainMask & bit != 0) : row == .alt ? (chop.altMask & bit != 0) : (chop.muteMask & bit != 0)
        let hue: Color = row == .main ? mainDestHue : row == .alt ? Self.editHue : Verb.delete.hue
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(on ? hue.opacity(0.85) : Color.white.opacity(0.08))
            if row == .mute {   // the MUTE row shows a speaker: unmuted when off, muted (slash) when on
                Image(systemName: on ? "speaker.slash.fill" : "speaker.fill").font(.system(size: 11, weight: .heavy))
                    .foregroundColor(on ? .black : .white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity).frame(height: 24)
        .contentShape(Rectangle()).onTapGesture { tapChop(i, row) }
    }
    func tapChop(_ i: Int, _ row: ChopRow) {   // each row is an INDEPENDENT per-slice toggle
        let bit = UInt8(1) << UInt8(i)
        editChop { c in
            switch row {
            case .main: c.mainMask ^= bit
            case .alt:  c.altMask ^= bit
            case .mute: c.muteMask ^= bit
            }
        }
    }
    func toggleMainBus(_ b: Bus) {
        editPointedCell { if $0.buses.contains(b) { $0.buses.remove(b) } else { $0.buses.insert(b) } }
    }
    func editChop(_ mutate: @escaping (inout Chop) -> Void) {
        editPointedCell { var ch = $0.chopResolved; mutate(&ch); $0.chop = (ch == Chop() ? nil : ch) }
    }
    /// A small labelled facet row (fixed-width label + a control) — used by `inputShiftRow`. (Was shared with the
    /// TRIGGERS accordion editors, now retired — the ON model stays on `Colour`, its inline UI returns with TOUCH.)
    @ViewBuilder func facetRow<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).frame(width: 44, alignment: .leading)
            control(); Spacer(minLength: 0)
        }
    }

    // MARK: - §cell-edit D — INPUT (Phase 3a: the SOURCE picker — cell-level, reuses the routing fields)

    /// MODE ROW — edit the whole SELECTION SET in one undoable step (input/output/chop/colour route through here).
    /// The edit applies to every selected cell; with a single cell selected it's just that cell.
    func editPointedCell(_ mutate: @escaping (inout Cell) -> Void) {
        guard let au else { return }
        // On the DRAG&DROP page a colour IS a machine — the per-cell ROUTING edit (receiver / emitters / chop) pushes
        // to EVERY cell of the selected colour, in every scene (not just the captured selection). (user 2026-08-09)
        if editColourScoped, let cid = editScopeColourID { au.editCellsOfColour(cid, mutate); refreshFromDocument(); return }
        guard !sel.isEmpty else { return }
        au.editCells(editSelTargets, mutate); refreshFromDocument()
    }
    /// SHIFT (D "octave + transpose · existing steppers, unchanged") — reuses the per-Colour transpose
    /// (−24…+24 st, already applied engine-wide via `setBrushTranspose`). OCTAVE = a ±12 convenience, SEMITONE =
    /// ±1; both mutate the one `Colour.transpose`. Colour-side like the triggers, so same-colour cells follow.
    @ViewBuilder var inputShiftRow: some View {
        let t = brushColour?.transpose ?? 0
        facetRow("SHIFT") {
            HStack(spacing: 5) {
                stepPad("−12") { setBrushTranspose(max(-24, t - 12)) }
                stepPad("−")   { setBrushTranspose(max(-24, t - 1)) }
                Text(t == 0 ? "0 st" : "\(t > 0 ? "+" : "")\(t) st")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(t == 0 ? .white.opacity(0.5) : Self.editHue)
                    .frame(minWidth: 42)
                stepPad("+")   { setBrushTranspose(min(24, t + 1)) }
                stepPad("+12") { setBrushTranspose(min(24, t + 12)) }
            }
        }
    }
    func stepPad(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            .frame(minWidth: 22, minHeight: 20).padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // CELL MACHINE stage-4 — the CELL LIBRARY: save the selected cell, browse, stamp saved cells.
    func openCellLibrary() { cellLibraryList = au?.listLibraryCells() ?? []; showCellLibrary = true }
    func saveCellNamed(_ name: String) {
        au?.saveCellToLibrary(col: selCol, row: selRow, name: name)
        cellLibraryList = au?.listLibraryCells() ?? []
    }
    func deleteLibraryCellNamed(_ name: String) {
        au?.deleteLibraryCell(name: name); cellLibraryList = au?.listLibraryCells() ?? []
    }
    // LIBRARY · APPLY — replace the CHAIN of the cells currently being edited with the library cell's chain.
    func applyLibraryChain(_ cell: Cell?) {
        guard let cell, !sel.isEmpty else { return }
        let chain = cell.processors ?? []          // the saved cell's materialised chain (empty = passthrough)
        chainReplace(chain)
        showCellLibrary = false
    }
    func stampFromLibrary(_ name: String) { applyLibraryChain(au?.loadLibraryCell(name: name)) }
    func stampFromFactory(_ name: String) { applyLibraryChain(au?.factoryLibraryCell(name: name)) }
}
