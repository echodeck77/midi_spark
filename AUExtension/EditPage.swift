//  EditPage.swift
//  The EDIT-spike-page surface, extracted from AudioUnitViewController.swift as an extension of DiagView
//  (mode row · selection set · inspector · chain · chop · triggers · cell library). Pure relocation — no behaviour
//  change. @State lives in DiagView (AudioUnitViewController.swift); these are its methods/computed views.

import SwiftUI

extension DiagView {
    // MODE ROW — the selection set's helpers. The ANCHOR is editSel.first: it drives the inspector (selCol/selRow)
    // and the breadcrumb, and is protected from a stray tap (long-press to drop). Edits write through to editSel.
    var editSelTargets: [(col: Int, row: Int)] { editSel.map { (col: $0.col, row: $0.row) } }
    func syncAnchor() {
        if let a = editSel.first { selCol = a.col; selRow = a.row; brush = scene.cellAt(a.col, a.row)?.colourID ?? brush }
        else { selCol = -1; selRow = -1 }
    }
    /// Remove a cell from the group and REVERT it to its original state: a cell created this session is deleted;
    /// a populated cell adopted into the group is restored from its pre-adopt stash.
    func deselect(_ pos: GridView.GridPos) {
        if bornThisSession.contains(pos) {
            au?.editScene { $0.deleteCellSever(col: pos.col, row: pos.row) }; bornThisSession.remove(pos); refreshFromDocument()
        } else if let orig = preAdoptStash[pos] {
            au?.editScene { $0.setCell(pos.col, pos.row, orig) }; preAdoptStash[pos] = nil; refreshFromDocument()
        }
        editSel.removeAll { $0 == pos }
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
            guard editSel.first == pos else { return }   // only the anchor responds to a long-press (drops + reverts)
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
    @ViewBuilder func editSpikePage(_ size: CGSize) -> some View {
        let gridH = max(150, size.height * 0.42)                     // top ~42% is the grid; the rest scrolls
        let cellH = max(18, min(46, (gridH - 30) / 9))               // 9 = 8 rows + the column-key row
        let inspectorW = min(360, size.width - 24)
        // EDIT-PAGE LAYOUT (design ferry 2026-08-06): the grid LEFT-aligned within the 1024pt page; opposite it, top-
        // aligned within the grid's height, a RIGHT block = the mode controls in a 2×2 (ADD/EDIT · MOVE / MUTE · CLEAR)
        // → the armed mode's description → APPLY / CANCEL.
        let pageW = min(size.width - 24, 1024)
        let rightW: CGFloat = 210
        let gridW = min(pageW - rightW - 16, max(240, gridH * 1.3))
        let canCommit = !editSel.isEmpty
        VStack(spacing: 8) {
            // LAYOUT v2: the header + tab bar are rendered ONCE by the parent now — this page is the PROCESSORS tab
            // body only (no arrangementBar of its own).
            HStack(alignment: .top, spacing: 16) {                  // grid LEFT · mode block opposite it, tops shared
                spikeGrid(cellH).frame(width: gridW, height: gridH)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 10) {          // the RIGHT block, within the grid's height
                    VStack(spacing: 6) {                            // the mode controls in a 2×2
                        HStack(spacing: 6) { modeChip("ADD/EDIT", .addEdit); modeChip("MOVE", .move) }
                        HStack(spacing: 6) { modeChip("MUTE", .mute); modeChip("CLEAR", .clear) }
                    }
                    Text(modeGuidance)                              // the armed mode's description, below the 2×2
                        .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if editMode == .addEdit {                       // APPLY / CANCEL below the description (the one staging mode)
                        HStack(spacing: 10) {
                            Button { commitSession() } label: { transactChip("APPLY", enabled: canCommit, fill: true) }
                                .buttonStyle(.plain).disabled(!canCommit)
                            Button { revertSession() } label: { transactChip("CANCEL", enabled: canCommit, fill: false) }
                                .buttonStyle(.plain).disabled(!canCommit)
                        }
                    }
                    Spacer(minLength: 0)                            // the stack lives within the grid's height
                }
                .frame(width: rightW, height: gridH, alignment: .top)
            }
            .frame(width: pageW, alignment: .leading)               // grid left-aligned in the 1024 page…
            .frame(maxWidth: .infinity)                             // …the page itself centred on wider canvases
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            if editMode == .addEdit, let cell = editingCell {       // controls show ONLY in ADD/EDIT, with a cell selected
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {       // §4 sparse: clear seams between sections
                        sectionHeader("IDENTITY");       identitySection(cell, swatch: max(38, cellH))
                        sectionSeam()
                        sectionHeader("FROM · MIDI IN"); inputSection(cell)   // the signal path reads FROM → CHAIN → TO
                        sectionSeam()
                        chainSectionHeader()                                  // CHAIN + the LIBRARY button (top-right of the chain)
                        chainStack(cell, boxWidth: min(540, size.width - 48))
                        sectionSeam()
                        sectionHeader("TO · MIDI OUT");  outputSection(cell, emitterWidth: min(320, inspectorW))
                    }.frame(maxWidth: 560, alignment: .leading).padding(.bottom, 8)   // §4 max content width
                }.frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)                                  // grid only (nothing selected, or a non-edit mode)
            }
        }
        .padding(12)
    }
    private func sectionSeam() -> some View { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.vertical, 2) }

    /// The always-visible guidance line for the current mode (INSTRUCTIONS: the guidance for each button is always shown).
    var modeGuidance: String {
        switch editMode {
        case .addEdit: return "Choose one cell, then choose more to duplicate and edit as a group. Flashing cells are duplicates, so select them if you want them to stay in sync"
        case .move:    return "Drag and drop a cell to a new position"
        case .mute:    return "Choose cells to mute"
        case .clear:   return "Choose cells to clear (tap the empty slot to bring it back)"
        }
    }
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
        editSel = []; clearedStash = [:]; bornThisSession = []; preAdoptStash = [:]; syncAnchor()
        editMode = m
        if m == .addEdit { au?.beginEditSession() }
        refreshFromDocument()
    }
    /// APPLY — commit the staged ADD/EDIT session as one undo step, then re-open a fresh baseline so editing continues.
    func commitSession() {
        au?.applyEditSession(); editSel = []; bornThisSession = []; preAdoptStash = [:]; syncAnchor()
        au?.beginEditSession(); refreshFromDocument()
    }
    /// CANCEL — revert everything staged since the session opened, then re-open a fresh baseline.
    func revertSession() {
        au?.cancelEditSession(); editSel = []; bornThisSession = []; preAdoptStash = [:]; syncAnchor()
        au?.beginEditSession(); refreshFromDocument()
    }

    /// SINGLE-mode editing (design ferry 2026-08-06): while in SINGLE (ladder) + ADD/EDIT, the SELECTION drives each
    /// column's ACTIVE rung — for every column that holds a selected cell, the TOPMOST (upper = smallest row index)
    /// selected cell becomes active (it plays) and the rest of that column mutes. Lower selected cells stay in the
    /// set (they keep the animated selection border) but read as muted (dormant, via the ladder). The activation
    /// writes `activeRow`, which rides the STANDING TRANSACTION — APPLY persists it, CANCEL reverts it with
    /// everything else (cancelEditSession restores the whole document). MULTI editing is untouched.
    func syncSingleModeActivation() {
        guard ladderMode, editMode == .addEdit, let au else { return }
        var topByColumn: [Int: Int] = [:]
        for p in editSel { topByColumn[p.col] = min(topByColumn[p.col] ?? p.row, p.row) }
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
    // set (white ring); its twins PULSE. A long-press drops the ANCHOR (repurposes the perform audition hold, which
    // is parked on this setup surface). CLEAR marks show as a dashed removal ring (increment 4).
    @ViewBuilder func spikeGrid(_ cellHeight: CGFloat) -> some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn,
                 trueColumn: d.playing ? ((d.absoluteStep % 8) + 8) % 8 : -1, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: false,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onAuditionStart: editGridLongPress, onAuditionEnd: editGridLongEnd,
                 laneMask: laneMask, onLaneMask: nil, onColumnKey: toggleLoopColumn, holdLatch: false,
                 onMoveCell: editMode == .move ? moveCell : nil, moveMode: editMode == .move, flagNoDest: false, animateSelection: true,
                 showAddPlus: editMode == .addEdit && !editSel.isEmpty,
                 cellHitAt: cellHitAt, cellHitVel: cellHitVel,   // SEAL comet feed
                 cellSounding: cellSounding, cellReleasedAt: cellReleasedAt,   // SEAL comet gate
                 selection: [],
                 whiteBorder: Set(editSel), twins: twinCells, ladderDim: ladderDim, verbInvite: nil,   // LADDER: dim dormant rungs + no playhead in EDIT too
                 routeFoci: [], routeIn: [], routeOut: [],
                 tapAltMask: tapAltMask, tapMuteMask: tapMuteMask,
                 strokeActive: false, onStroke: strokeCell, onStrokeEnd: endStroke)
    }
    /// MOVE mode — drag a cell to a new position; drop over a populated cell SWAPS them. Immediate + undoable.
    func moveCell(_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) {
        guard from.col != to.col || from.row != to.row else { return }
        au?.editScene { $0.swapCells((from.col, from.row), (to.col, to.row)) }
        refreshFromDocument()
    }
    /// MODE ROW — the ADVERTISE set: cells that are TWINS of anything in the selection but not themselves selected.
    /// They PULSE to invite inclusion (they are NOT auto-edited). Empty unless ADD/EDIT mode has a selection.
    var twinCells: Set<GridView.GridPos> {
        guard editArmed, editMode == .addEdit, !editSel.isEmpty else { return [] }
        var s = Set<GridView.GridPos>()
        for m in editSel {
            for t in au?.twinPositions(col: m.col, row: m.row) ?? [] { s.insert(GridView.GridPos(col: t.col, row: t.row)) }
        }
        for m in editSel { s.remove(m) }   // selected cells wear the white ring, not the pulse
        return s
    }

    // CELL MACHINE (feat/EditPageSpike): the selected cell's processor CHAIN as a VERTICAL STACK of slot boxes,
    // each 50% of screen width, head first, plus [+ ADD] (≤ 8 slots). Stage 1 renders the HEAD; slots 2…8 are
    // stored + editable but not yet executed (serial run is Phase 2). Reuses ProcessorBox in `slotMode`.
    func cellChain(_ cell: Cell) -> [ProcessorSlot] {         // the cell's own chain; nil → materialise the Colour head
        if let p = cell.processors { return p }                       // incl. an EXPLICIT empty chain (passthrough → the invitation)
        let c = docColours.first { $0.colourID == cell.colourID }
        return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())]
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
                Button { au?.addSlotCells(editSelTargets, type: t); refreshFromDocument() } label: {
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
        let n = editSel.count
        HStack(spacing: 8) {
            Text(n > 1 ? "\(n) SELECTED" : (n == 1 ? "1 SELECTED" : "—"))
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(n > 1 ? Self.editHue : .white.opacity(0.55))
            if !twinCells.isEmpty {
                Text("· \(twinCells.count) MATCHING (tap to add)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder func slotBox(_ i: Int, _ slot: ProcessorSlot, cell: Cell) -> some View {
        let sc: Colour = { var c = Colour(colourID: cell.colourID, type: slot.type); c.paramsA = slot.params; return c }()
        let cid = cell.colourID, targets = editSelTargets
        ProcessorBox(
            colour: sc, colourIndex: -1, face: .a,
            onEdit: { mutate in
                au?.editSlotCells(targets, slot: i) { s in
                    var tmp = Colour(colourID: cid, type: s.type); tmp.paramsA = s.params
                    mutate(&tmp); s.params = tmp.paramsA                    // slotMode edits only paramsA
                }
                refreshFromDocument()
            },
            onTranspose: { _ in }, onMorph: { _ in },
            onSetTypeA: { t in au?.setSlotTypeCells(targets, slot: i, t); refreshFromDocument() },
            height: 260, slotMode: true, slotBypassed: slot.bypassed,
            accentOverride: mainDestHue,               // same blue as the emitters
            passHead: d.playing ? (d.pass & 3) : -1,   // MODE ROW: the passgate playhead follows the live pass
            onBypass: { au?.toggleSlotBypassCells(targets, slot: i); refreshFromDocument() },
            onRemove: i == 0 ? nil : { au?.removeSlotCells(targets, slot: i); refreshFromDocument() },
            onMacro: { openMacroAuthoring(slot: i, slotData: slot) })
    }

    // MARK: - MACRO AUTHORING FLOW (canonical) — open/callbacks for a processor slot. Rides the processors-page
    // edit session, so all writes preview live + revert with the page's CANCEL; the flow's own CANCEL additionally
    // restores the slot baseline + discards its staged bindings (§6 "nothing escapes CANCEL").
    func openMacroAuthoring(slot i: Int, slotData slot: ProcessorSlot) {
        guard let a = editSel.first else { return }
        macroAuthorAnchor = (a.col, a.row); macroAuthorSlot = i; macroAuthorBaseline = slot; macroAuthorPending = []
        macroAuthorGroup = macroGroupForProcessor(col: a.col, row: a.row, slot: i, type: slot.type)
        macroAuthorMain = processorValues(slot)
        if let alt = slot.paramsAlt {
            var s = ProcessorSlot(type: slot.type, params: alt); s.bypassed = slot.bypassedAlt ?? slot.bypassed
            macroAuthorAlt = processorValues(s)
        } else { macroAuthorAlt = [:] }                              // empty → the view seeds ALT = MAIN
        au?.setAudition(col: a.col, row: a.row)                      // REAL-TIME AUDITION: hold keys to hear the processor live while authoring
        macroAuthorOpen = true
    }
    /// MAIN is REAL — write the edited MAIN values onto the live slot(s). NO refreshFromDocument on the hot path:
    /// editSlotCells → scheduleRebuild already republishes the snapshot immediately (the audio tracks live), whereas
    /// refreshFromDocument reloads ~40 @State fields per tick (the lag that hid the real-time change).
    func macroAuthorWriteMain(_ v: [String: Double]) {
        au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { $0 = applyProcessorValues(v, to: $0) }
    }
    /// TEST audition — apply a value dict live (nil restores the current MAIN, never a stale preview).
    func macroAuthorPreview(_ v: [String: Double]?) {
        let vals = v ?? macroAuthorMain
        au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { $0 = applyProcessorValues(vals, to: $0) }
    }
    /// §7 persist the ALTERNATIVE set on the slot (leaves MAIN untouched — no audio impact, no refresh needed).
    func macroAuthorPersistAlt(_ v: [String: Double]) {
        macroAuthorAlt = v
        au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { s in
            let a = applyProcessorValues(v, to: ProcessorSlot(type: s.type)); s.paramsAlt = a.params; s.bypassedAlt = a.bypassed
        }
    }
    /// Stage a binding (committed on APPLY). Only the CONTINUOUS (foldable) delta keys bind today; discrete keys are
    /// the future button/timeline path (noted).
    func macroAuthorAssign(_ macroIndex: Int, _ delta: [String: Double]) { macroAuthorPending.append((macroIndex, delta)) }
    func closeMacroAuthoring(apply: Bool) {
        let foldable: Set<String> = ["gate", "ramp", "spread", "curve", "velTilt", "probability", "harmVelScale"]
        if apply {
            for b in macroAuthorPending {                            // commit the staged bindings
                let targets: [MacroTarget] = b.delta.compactMap { k, d in
                    foldable.contains(k) ? MacroTarget(col: macroAuthorAnchor.col, row: macroAuthorAnchor.row, slot: macroAuthorSlot, param: k, delta: d) : nil
                }
                if !targets.isEmpty { au?.addMacroTargets(b.macro, targets) }
                au?.setMacroFixed(b.macro, b.macro >= 8)             // buttons = toggle/fixed · sliders = spring
            }
        } else if let base = macroAuthorBaseline {                   // CANCEL → restore MAIN + ALT to the slot's open state
            au?.editSlotCells(editSelTargets, slot: macroAuthorSlot) { $0 = base }
        }
        au?.clearAudition()
        macroAuthorOpen = false; macroAuthorGroup = nil; macroAuthorBaseline = nil; macroAuthorPending = []
        refreshFromDocument()
    }

    func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)   // device round 2: bigger, legible
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
                Text(editSel.count == 1 ? "1 CELL SELECTED" : "\(editSel.count) CELLS SELECTED")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                Text("\(twinCells.count) IDENTICAL CELLS AVAILABLE")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
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
        guard let au, !editSel.isEmpty else { return }
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
        guard let cell, !editSel.isEmpty else { return }
        let chain = cell.processors ?? []          // the saved cell's materialised chain (empty = passthrough)
        au?.editCells(editSelTargets) { $0.processors = chain }
        refreshFromDocument(); showCellLibrary = false
    }
    func stampFromLibrary(_ name: String) { applyLibraryChain(au?.loadLibraryCell(name: name)) }
    func stampFromFactory(_ name: String) { applyLibraryChain(au?.factoryLibraryCell(name: name)) }
}
