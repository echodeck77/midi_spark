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
    func syncSingleModeActivation() {
        // NOT on the DRAG&DROP page: there the selection is the WHOLE colour, so deriving the active rung from it would
        // activate every column the colour occupies (user 2026-08-09 bug). The DD grid sets the rung via armLadderRung.
        guard ladderMode, editMode == .addEdit, let au else { return }
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
    // The active edit SCOPE for machine edits. On the DRAG&DROP page a colour IS a machine — edits are GLOBAL, so they
    // write the colour's TEMPLATE chain (and clear every per-cell override across all scenes) → every cell of the
    // colour, in every scene, stays uniform. Elsewhere (the PROCESSORS tab's manual selection) edits apply per-cell.
    // (user 2026-08-09: processor settings must change uniformly across all instances of a colour.)
    private var editColourScoped: Bool { false }   // was the DRAG&DROP page (removed); the surviving GRID edit flow is per-cell
    // The anchor cell's colour scopes an edit (the DRAG&DROP colour-wide path was removed with that page).
    private var editScopeColourID: String? { editingCell?.colourID }
    // Every chain edit is based on the DISPLAYED chain (cellChain(editingCell)) and written whole — so a colour-scoped
    // edit can't operate on a stale representative cell (which reverted the arp / emptied the chain to a passgate on
    // delete — user 2026-08-09/10). `applyChain` writes it colour-wide (DRAG&DROP) or per-cell (PROCESSORS).
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
            let yRecv: CGFloat = 32, yProc: CGFloat = 130, yEm: CGFloat = 214   // emitters pulled CLOSER to the processor row (user 2026-08-10)
            ZStack(alignment: .topLeading) {
                Path { p in                                      // the dotted thread that traces the FLOW (user 2026-08-09/10)
                    let firstX = sw / 2                          // centre of the first processor
                    let lastX = 7 * (sw + gap) + sw / 2          // centre of the last (8th) processor
                    let yTop: CGFloat = 82                       // the shared horizontal, between the receivers and the processor row
                    let yBot: CGFloat = 172                      // the turn between the processor row and the emitters
                    let recvBottom = yRecv + 22.5               // the receivers box bottom edge
                    let emTop = yEm - 22.5                       // the emitters box top edge
                    // FOUR lines — one from the bottom of EACH receiver — DOWN to the shared horizontal (user 2026-08-10).
                    // Receiver-cell geometry: box padding 6 + DIN mark 26 + spacing 8 → the 4 cells (gaps 8) fill the rest.
                    let boxLeft = W / 2 - recvW / 2
                    let rw = (recvW - 70) / 4                    // 70 = padding 12 + DIN 26 + 4 gaps × 8
                    let rStart = boxLeft + 40                    // padding 6 + DIN 26 + spacing 8
                    func rcx(_ i: Int) -> CGFloat { rStart + CGFloat(i) * (rw + 8) + rw / 2 }
                    for i in 0..<4 { p.move(to: CGPoint(x: rcx(i), y: recvBottom)); p.addLine(to: CGPoint(x: rcx(i), y: yTop)) }
                    // the SHARED horizontal (spanning the 4 drop points) → LEFT to the first processor → DOWN into it →
                    // THROUGH the row to the last slot → DOWN → LEFT → DOWN to the emitters' TOP CENTRE.
                    p.move(to: CGPoint(x: rcx(3), y: yTop)); p.addLine(to: CGPoint(x: firstX, y: yTop))
                    p.addLine(to: CGPoint(x: firstX, y: yProc)); p.addLine(to: CGPoint(x: lastX, y: yProc))
                    p.addLine(to: CGPoint(x: lastX, y: yBot)); p.addLine(to: CGPoint(x: W / 2, y: yBot)); p.addLine(to: CGPoint(x: W / 2, y: emTop))
                }.stroke(hue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                // (SELECTED-CELL indicator + INPUT/OUTPUT FILTER removed — user 2026-08-07/09; the flow is RECEIVERS → PROCESSORS → EMITTERS.)
                receiverBox(cell, bg: bg).frame(width: recvW, height: 45).position(x: W / 2, y: yRecv)            // RECEIVERS (centred, −25% height)
                ForEach(0..<8, id: \.self) { i in                                                                // PROCESSORS (8 slots)
                    slotOrGhost(i, chain, bg: bg, hue: hue).frame(width: sw, height: 38).position(x: CGFloat(i) * (sw + gap) + sw / 2, y: yProc)   // −25% then −20% height (user 2026-08-09)
                }
                ddZone("procLast").frame(width: sw, height: 38).position(x: 7 * (sw + gap) + sw / 2, y: yProc)     // measure the FINAL slot in "dd" space → the DRAG&DROP action-box connector line (user 2026-08-10)
                emitterBox(cell, bg: bg).frame(width: recvW, height: 45).position(x: W / 2, y: yEm)               // EMITTERS (centred, −25% height)
            }
        }
        .frame(width: flowW, height: 268)
    }
    // A set slot (tap → edit pop-up) or an empty dashed "+" ghost (tap → type picker) — user 2026-08-07.
    // DISPLAY-ONLY now (BUILD renders flowDiagram with allowsHitTesting(false); the interactive proc-editor was retired
    // with the PROCESSORS tab — BUILD edits via its own buildProcessorEditor).
    @ViewBuilder private func slotOrGhost(_ i: Int, _ chain: [ProcessorSlot], bg: Color, hue: Color) -> some View {
        if i < chain.count {
            flowSlot(chain[i], bg: bg, hue: hue)
        } else {
            flowGhost("+", bg: bg, plus: false, hue: hue)
        }
    }
    // FLOW-DIAGRAM processor pop-up — tap a populated box to edit its FULL controls (same ProcessorBox as the chain
    // editor: big, legible, per-type). Title + BYPASS in the box's title row; the MACRO section (add/dropdown +
    // authoring) at the FOOT of the form; APPLY/CANCEL below it. ONE transaction: CANCEL reverts the whole document
    // snapshot (processor edits AND macro edits together, per the user's ruling 2026-08-08).
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
    private func splitAffordance() -> some View {   // display-only now (the SPLIT pop-up was retired with the PROCESSORS tab)
        let dashed = RoundedRectangle(cornerRadius: 6).strokeBorder(mainDestHue.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        return VStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 15, weight: .heavy))
            Text("SPLIT").font(.system(size: 8, weight: .heavy, design: .monospaced))
        }
        .foregroundColor(mainDestHue).frame(width: 48).frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(mainDestHue.opacity(0.14)).overlay(dashed))
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
    // F — OUTPUT: MAIN destination toggles (live, edit cell.buses) · the CHOP 8×3 grid + ALT destination. The chop
    // routing engine IS wired: tick cells (arp/ratchet/strum) route per-slice; a HOLD cell routes by its onset slice.
    var mainDestHue: Color { UI.cyan }   // cyan — the emitters
    enum ChopRow { case main, alt, mute }
    /// The OUTPUT block — MAIN dest · the 8×3 CHOP grid · ALT dest — CENTRED at the emitter section's width so it
    /// lines up over the MIDI OUTPUT strips below (user 2026-07-31). Each slice column: TOP → the cell's own (MAIN)
    /// emitters · MIDDLE → MUTE · BOTTOM → the ALT DESTINATION set (chosen below). The routing runs in the engine.
    func toggleMainBus(_ b: Bus) {
        editPointedCell { if $0.buses.contains(b) { $0.buses.remove(b) } else { $0.buses.insert(b) } }
    }
    func editPointedCell(_ mutate: @escaping (inout Cell) -> Void) {
        guard let au else { return }
        // On the DRAG&DROP page a colour IS a machine — the per-cell ROUTING edit (receiver / emitters / chop) pushes
        // to EVERY cell of the selected colour, in every scene (not just the captured selection). (user 2026-08-09)
        if editColourScoped, let cid = editScopeColourID {
            au.editCellsOfColour(cid, mutate)
            // An UNPLACED colour has no cells for editCellsOfColour to touch — the routing edit would silently no-op.
            // Capture the intent on the page STICKY so the buttons respond now + the colour inherits it when placed.
            if ddColourCellsPublic(cid).isEmpty { ddApplyStickyRoutingMutation(cid, mutate) }
            refreshFromDocument(); ddCaptureStickyRouting(); return
        }
        guard !sel.isEmpty else { return }
        au.editCells(editSelTargets, mutate); refreshFromDocument()
    }
    func deleteLibraryCellNamed(_ name: String) {   // CellBrowser onDelete (live)
        au?.deleteLibraryCell(name: name); cellLibraryList = au?.libraryCellSummaries() ?? []
    }
}
