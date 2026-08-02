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
        if let a = editSel.first { selCol = a.col; selRow = a.row; brush = scene.cells[a.col][a.row]?.colourID ?? brush }
        else { selCol = -1; selRow = -1 }
    }
    /// Remove a cell from the group and REVERT it to its original state: a cell created this session is deleted;
    /// a populated cell adopted into the group is restored from its pre-adopt stash.
    func deselect(_ pos: GridView.GridPos) {
        if bornThisSession.contains(pos) {
            au?.editScene { $0.deleteCellSever(col: pos.col, row: pos.row) }; bornThisSession.remove(pos); refreshFromDocument()
        } else if let orig = preAdoptStash[pos] {
            au?.editScene { $0.cells[pos.col][pos.row] = orig }; preAdoptStash[pos] = nil; refreshFromDocument()
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("GRID SETUP").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.editHue)
                Spacer()
                Button { au?.uiUndo(); refreshFromDocument() } label: { headerIcon("arrow.uturn.backward", on: au?.uiCanUndo ?? false) }
                    .buttonStyle(.plain).disabled(!(au?.uiCanUndo ?? false))
                Button { au?.uiRedo(); refreshFromDocument() } label: { headerIcon("arrow.uturn.forward", on: au?.uiCanRedo ?? false) }
                    .buttonStyle(.plain).disabled(!(au?.uiCanRedo ?? false))
                Button { editArmed = false } label: {                // the only exit while the spike owns the screen
                    Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Self.editHue))
                }.buttonStyle(.plain)
            }
            spikeGrid(cellH).frame(height: gridH)                    // the alternative main grid, on top (its column keys toggle the loop)
            modeRow()                                                // MODE ROW: ADD/EDIT · MOVE · MUTE · CLEAR ‖ APPLY · CANCEL
            Text(modeGuidance)                                       // the ALWAYS-VISIBLE guidance for the current mode
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            if editMode == .addEdit, let cell = editingCell {       // controls show ONLY in ADD/EDIT, with a cell selected
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {       // §4 sparse: ~2× vertical rhythm
                        sectionHeader("IDENTITY");       identitySection(cell, swatch: max(38, cellH))
                        sectionHeader("FROM · MIDI IN"); inputSection(cell)   // the signal path reads FROM → CHAIN → TO
                        chainSectionHeader()                                  // CHAIN + the LIBRARY button (top-right of the chain)
                        chainStack(cell, boxWidth: min(540, size.width - 48))
                        sectionHeader("TO · MIDI OUT");  outputSection(cell, emitterWidth: min(320, inspectorW))
                    }.frame(maxWidth: 560, alignment: .leading).padding(.bottom, 8)   // §4 max content width
                }.frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)                                  // grid + guidance only (nothing selected, or a non-edit mode)
            }
        }
        .padding(12)
    }

    // MODE ROW: big, left-justified ADD/EDIT · MOVE · MUTE · CLEAR radio + right-justified APPLY·CANCEL (shown ONLY
    // in ADD/EDIT — the one staging mode; MOVE/MUTE/CLEAR are immediate + undo/redo). APPLY commits the staged
    // edits/births as ONE undo step; CANCEL reverts them.
    @ViewBuilder func modeRow() -> some View {
        let canCommit = !editSel.isEmpty                     // APPLY/CANCEL are available whenever ≥1 cell is selected
        HStack(spacing: 6) {
            modeChip("ADD/EDIT", .addEdit); modeChip("MOVE", .move); modeChip("MUTE", .mute); modeChip("CLEAR", .clear)
            Spacer(minLength: 10)
            if editMode == .addEdit {
                Button { commitSession() } label: { transactChip("APPLY", enabled: canCommit, fill: true) }
                    .buttonStyle(.plain).disabled(!canCommit)
                Button { revertSession() } label: { transactChip("CANCEL", enabled: canCommit, fill: false) }
                    .buttonStyle(.plain).disabled(!canCommit)
            }
        }.padding(.vertical, 4)
    }
    /// The always-visible guidance line for the current mode (INSTRUCTIONS: the guidance for each button is always shown).
    var modeGuidance: String {
        switch editMode {
        case .addEdit: return "Select 1 cell, then choose more to edit them as a group"
        case .move:    return "Drag and drop a cell to a new position"
        case .mute:    return "Choose cells to mute"
        case .clear:   return "Choose cells to clear (tap the empty slot to bring it back)"
        }
    }
    func headerIcon(_ system: String, on: Bool) -> some View {
        Image(systemName: system).font(.system(size: 15, weight: .heavy)).foregroundColor(on ? Self.editHue : .white.opacity(0.2))
            .frame(width: 34, height: 30).background(RoundedRectangle(cornerRadius: 6).fill(Self.editHue.opacity(on ? 0.14 : 0.05)))
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

    // MODE ROW §5 — the grid's own column keys ARE the loop control (one row, not two): a TAP toggles the column in
    // the SAME laneMask the PERFORM column-hold drives (au.setLaneMask → Derivations.lapColumn), so the engine loops
    // exactly the toggled subset — one loop mechanism, two surfaces. Toggled keys show the LOOP glyph. Cleared on DONE.
    func setEditLoop(_ mask: UInt8) { editLoopMask = mask; au?.setLaneMask(mask) }
    func toggleLoopColumn(_ c: Int) { setEditLoop(editLoopMask ^ (1 << UInt8(c))) }

    // The grid instance for the spike page — the same GridView component. In EDIT mode a tap builds the selection
    // set (white ring); its twins PULSE. A long-press drops the ANCHOR (repurposes the perform audition hold, which
    // is parked on this setup surface). CLEAR marks show as a dashed removal ring (increment 4).
    @ViewBuilder func spikeGrid(_ cellHeight: CGFloat) -> some View {
        GridView(scene: scene, colours: docColours, playColumn: d.effColumn, playing: d.playing,
                 beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                 cellHeight: cellHeight, editing: false,
                 selCol: selCol, selRow: selRow, onTap: tapCell,
                 onAuditionStart: editGridLongPress, onAuditionEnd: editGridLongEnd,
                 laneMask: editLoopMask, onLaneMask: nil, onColumnKey: toggleLoopColumn, holdLatch: false,
                 onMoveCell: editMode == .move ? moveCell : nil, moveMode: editMode == .move, flagNoDest: false, animateSelection: true,
                 showAddPlus: editMode == .addEdit && !editSel.isEmpty,
                 cellHitAt: cellHitAt, cellHitVel: cellHitVel,   // ORBIT comet feed
                 cellSounding: cellSounding, cellReleasedAt: cellReleasedAt,   // SEAL comet gate
                 selection: [],
                 whiteBorder: Set(editSel), twins: twinCells, verbInvite: nil,
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
                if chain.count < 8 {                             // ADD MORE — the same big, bold TYPE selector as the empty state
                    VStack(alignment: .leading, spacing: 8) {
                        Text("+ ADD PROCESSOR").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(mainDestHue)
                        processorTypeRow(boxWidth: boxWidth)
                    }.padding(.top, 4)
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
            onRemove: i == 0 ? nil : { au?.removeSlotCells(targets, slot: i); refreshFromDocument() })
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.14))                   // engraved plate (as cells)
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                        Canvas { ctx, size in
                            drawSeal(sealGeometry(sealHash(cell)), into: ctx, size: size, padFraction: 0.16, stroke: 2.8, ink: sealInk)
                        }
                    }
                    .frame(width: box - 16, height: (box - 16) * 0.62)                                       // landscape — matches the cell seal's dims
                    .id(sealHash(cell)).transition(.opacity)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.75), lineWidth: 2.5))
                .animation(.easeInOut(duration: 0.25), value: sealHash(cell))
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
    // F — OUTPUT: MAIN destination toggles (live, edit cell.buses) · the CHOP 8×2 grid + ALT destination (model
    // persisted; the routing ENGINE is a separate increment — labelled so it's honest, not a silent no-op).
    var mainDestHue: Color { Color(red: 0.15, green: 0.88, blue: 0.94) }   // cyan — the emitters
    enum ChopRow { case main, alt, mute }
    /// The OUTPUT block — MAIN dest · the 8×3 CHOP grid · ALT dest — CENTRED at the emitter section's width so it
    /// lines up over the MIDI OUTPUT strips below (user 2026-07-31). MAIN dest is live (edits cell.buses); the
    /// chop grid + alt dest persist but their routing ENGINE is a separate increment.
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
    func editName(_ id: String) -> String {
        docColours.first { $0.colourID == id }?.nameResolved ?? id.uppercased()
    }
    // MARK: - §cell-edit E — the TRIGGERS accordion (Colour-side; edits the pointed cell's Colour `OnConfig`)

    /// The Colour-side write path: triggers live on `Colour.on`, and `brush` already points at the pointed cell's
    /// Colour (set in tapCell), so this mutates the pointed cell's triggers — every same-colour cell follows.
    /// Reverting to all-defaults clears `.on` back to nil (clean docs). Undoable via `editBrushColour`.
    func editOn(_ mutate: @escaping (inout OnConfig) -> Void) {
        editBrushColour { var c = $0.on ?? OnConfig(); mutate(&c); $0.on = (c == OnConfig() ? nil : c) }
    }
    /// The five ON rows, one-open-at-a-time; assigned rows show their summary, unassigned show a dim ＋ (reusing
    /// the model's `*Summary` strings). Reads the brush Colour's resolved `OnConfig`.
    // TRIGGERS, flat (user 2026-08-01): TAP · HOLD · ARRIVE editors shown inline, no accordion. LEAVE + SCENE
    // dropped this version; each picker offers only the engine-WIRED actions.
    @ViewBuilder func triggersInline(_ cell: Cell) -> some View {
        let on = brushColour?.onResolved ?? OnConfig()
        VStack(alignment: .leading, spacing: 10) {
            trigLabel("TAP");    tapEditor(on)
            trigLabel("HOLD");   holdEditor(on)
            trigLabel("ARRIVE"); arriveEditor(on)
        }
    }
    func trigLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
    }
    // ---- per-section editors. Each picker offers ONLY the engine-WIRED actions (the inert placeholders — TAP
    //      fill/replay · HOLD freeze/slice-cycle/morph-scrub · ARRIVE dice — are hidden this version; the enum
    //      cases stay in the model, append-only, for the future TOUCH-box design pass). ----
    @ViewBuilder func tapEditor(_ on: OnConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            trigMenu([.none, .alt, .mute, .solo], on.tap) { v in editOn { $0.tap = v } }
            if on.tap != .none {
                facetRow("WHEN") { trigSeg(OnTapWhen.allCases, on.tapWhen, label: { $0.rawValue }) { v in editOn { $0.tapWhen = v } } }
                facetRow("FOR")  { trigSeg(OnTapFor.allCases, on.tapFor, label: { $0.rawValue }) { v in editOn { $0.tapFor = v } } }
            }
        }
    }
    @ViewBuilder func holdEditor(_ on: OnConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            trigMenu([.none, .alt, .oct], on.hold) { v in editOn { $0.hold = v } }
            // (REL SPRING|LATCH dropped — hold triggers are spring-only today; LATCH-persist is a future. SIZE
            //  facet dropped with slice-cycle.)
            if on.hold == .oct { facetRow("DIR") { trigSeg([true, false], on.octUp, label: { $0 ? "+" : "−" }) { v in editOn { $0.octUp = v } } } }
        }
    }
    @ViewBuilder func arriveEditor(_ on: OnConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            trigMenu([.none, .altAlternate, .morphDrift, .emitterRotate], on.arrive) { v in editOn { $0.arrive = v } }
            if on.arrive != .none {
                facetRow("EVERY") { trigStepper(on.arriveEvery, 1, 4) { v in editOn { $0.arriveEvery = v } } }
                if on.arrive == .morphDrift {
                    facetRow("DRIFT") { trigStepper(on.driftPct, 1, 100) { v in editOn { $0.driftPct = v } } }
                    facetRow("MODE") { trigSeg(DriftMode.allCases, on.driftMode, label: { $0.rawValue }) { v in editOn { $0.driftMode = v } } }
                }
            }
        }
    }
    // ---- small trigger controls ----
    func trigMenu<T: RawRepresentable & Hashable>(_ options: [T], _ current: T,
                                                          _ pick: @escaping (T) -> Void) -> some View where T.RawValue == String {
        Menu {
            ForEach(options, id: \.self) { opt in Button(opt.rawValue) { pick(opt) } }
        } label: {
            HStack {
                Text(current.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 8).frame(height: 24).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
        }
    }
    func trigSeg<T: Equatable>(_ options: [T], _ sel: T, label: @escaping (T) -> String,
                                       _ pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let hot = opt == sel
                Text(label(opt)).font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(hot ? .black : .white.opacity(0.6))
                    .padding(.horizontal, 6).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(hot ? Self.editHue : Color.white.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { pick(opt) }
            }
        }
    }
    @ViewBuilder func facetRow<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).frame(width: 44, alignment: .leading)
            control(); Spacer(minLength: 0)
        }
    }
    func trigStepper(_ value: Int, _ lo: Int, _ hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text("−").font(.system(size: 12, weight: .heavy)).foregroundColor(.white.opacity(0.7)).frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))).contentShape(Rectangle()).onTapGesture { set(max(lo, value - 1)) }
            Text("\(value)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white).frame(minWidth: 20)
            Text("+").font(.system(size: 12, weight: .heavy)).foregroundColor(.white.opacity(0.7)).frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))).contentShape(Rectangle()).onTapGesture { set(min(hi, value + 1)) }
        }
    }

    // MARK: - §cell-edit D — INPUT (Phase 3a: the SOURCE picker — cell-level, reuses the routing fields)

    /// The pointed cell's input source in words: a receiver (nil ⇒ unrouted). (Grid-chaining retired.)
    func inputSourceLabel(_ cell: Cell) -> String {
        if let rcv = cell.inputReceiver { return "MIDI-IN · R\(rcv + 1)" }
        return "NONE"                                        // null input (no receiver)
    }
    /// SOURCE = a value chip (tap = picker): NONE · MIDI-IN R1–R4. (Grid-chaining retired: FROM ROW removed.)
    @ViewBuilder func inputSourceChip(_ cell: Cell) -> some View {
        Menu {
            Button("NONE (unrouted)") { setEditSourceNone() }
            ForEach(0..<4, id: \.self) { r in Button("MIDI-IN · R\(r + 1)") { editPointedCell { $0.inputRow = nil; $0.inputReceiver = r } } }
        } label: {
            HStack {
                Text(inputSourceLabel(cell)).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Self.editHue)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 8).frame(height: 24).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
        }
    }
    func setEditSource(_ mutate: @escaping (inout SceneState) -> Void) {
        guard let au, selCol >= 0, selRow >= 0, scene.cells[selCol][selRow] != nil else { return }
        au.editScene(mutate); refreshFromDocument()
    }
    /// MODE ROW — edit the whole SELECTION SET in one undoable step (input/output/chop/colour route through here).
    /// The edit applies to every selected cell; with a single cell selected it's just that cell.
    func editPointedCell(_ mutate: @escaping (inout Cell) -> Void) {
        guard let au, !editSel.isEmpty else { return }
        au.editCells(editSelTargets, mutate); refreshFromDocument()
    }
    func setEditSourceNone() {
        editPointedCell { $0.inputRow = nil; $0.inputReceiver = nil }
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
