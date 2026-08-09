import SwiftUI

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (16 colours, flat swatches) + ROW SELECTORS + the 8×8 GRID (flat colour v1, calm).
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// Built: layout · selection · machinery · row selectors · RANDOMIZE · the palette playhead · the SIX DRAG LANDINGS
// (palette→grid PLACE · grid→grid MOVE · grid→occupied-palette ADOPT · grid→empty-palette FORK · →LITTER delete).
// Deferred: palette↔palette reorg, SINGLE|MULTI|FREE, the true per-colour machine model.
private enum DDTarget { case grid(Int, Int), palette(Int), litter }

// The row-selector PAINT cycle (user 2026-08-09): press 1 fills the row's EMPTY cells with the colour; press 2 fills
// the WHOLE row (only if the row is now mixed, else it reverts like press 3); press 3 reverts to the original row.
struct DDRowCycle { var row: Int; var colour: Int; var phase: Int; var original: [Cell?] }

// Drop-zone frames for the CUSTOM finger-tracking drag (SwiftUI's .onDrag/.onDrop don't survive the AU host).
struct DDZonePref: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension DiagView {
    @ViewBuilder func dragDropPage(_ size: CGSize) -> some View {
        let pageW = min(size.width - 24, 1024)                       // hold the global 1024 content cap (user 2026-08-09)
        let landscape = size.width > size.height
        // grid + palette are HEIGHT-MATCHED (user 2026-08-09): the grid = loop row (18) + 8 cells; the palette = 4
        // swatches + the DELETE box (= a swatch). gridCell drives, swatch is derived so both stack to the same height.
        let H = min(size.height * (landscape ? 0.52 : 0.46), landscape ? 480 : 400)
        let gridCell = max(16, min(48, (H - 50) / 8))
        let matchedH = gridCell * 8 + 50                             // the actual grid height after clamping
        let swatch = landscape ? max(24, (matchedH - 28) / 5)        // landscape: palette + DELETE matches the grid height
                               : max(22, (matchedH - 128) / 5)       // portrait: palette + DELETE + identity (name·count·PLAY) matches it
        let paletteW = swatch * 4 + 18
        Group {
            if landscape {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {            // TOP band: identity · palette+DELETE · grid · PLAY
                        ddColourIdentity(showPlay: false).frame(width: 130, alignment: .topLeading)
                        ddPalette(swatch: swatch, litterHeight: swatch).frame(width: paletteW, alignment: .top)
                        HStack(alignment: .top, spacing: 5) {
                            ddRowSelectors(cell: gridCell, topInset: 18)
                            VStack(spacing: 4) { ddColumnLoopRow(cell: gridCell); ddGrid(cell: gridCell) }
                        }
                        ddPlayCellButton()                            // PLAY: THIS CELL — right of the grid, top-aligned
                        Spacer(minLength: 0)
                    }
                    ddMachinery(width: pageW).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // buttons + flow, no identity/line
                }
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 20) {            // PORTRAIT: palette + DELETE + identity LEFT · grid RIGHT
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 10) {   // palette · DELETE · GOLD swatch+label · "1 cell" — matched to the grid
                            ddPalette(swatch: swatch, litterHeight: swatch)
                            ddColourIdentity()
                        }.frame(width: paletteW, alignment: .top)
                        HStack(alignment: .top, spacing: 5) {
                            ddRowSelectors(cell: gridCell, topInset: 18)
                            VStack(spacing: 4) { ddColumnLoopRow(cell: gridCell); ddGrid(cell: gridCell) }
                        }
                        Spacer(minLength: 0)
                    }.frame(height: matchedH, alignment: .top)
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    ddMachinery(width: pageW).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: pageW)
        .frame(maxWidth: .infinity)                                  // centre the capped content on wider canvases
        .padding(.vertical, 12)
        .coordinateSpace(name: "dd")                                               // the drag's shared frame of reference
        .onPreferenceChange(DDZonePref.self) { ddZones = $0 }                       // collect the drop-zone frames
        // SAFETY NET: a page-level release clears any stuck drag state. The page root survives the cell re-renders that
        // can cancel a source cell's own gesture mid-drop (leaving the ghost/highlights stuck). (user 2026-08-09)
        .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("dd")).onEnded { _ in ddResetDrag() })
        .overlay(alignment: .topLeading) { if let p = ddDragPayload { ddGhost(p).position(x: ddDragLoc.x, y: ddDragLoc.y - 32).allowsHitTesting(false) } }   // the in-hand ghost, above the finger
        .onChange(of: d.beat) { b in ddBeatAnchor = b; ddBeatAnchorAt = Date() }   // playhead: anchor each poll for extrapolation
    }
    // A cell/swatch reports its frame (in "dd" space) so a drag's end point can be hit-tested to a landing.
    private func ddZone(_ key: String) -> some View {
        GeometryReader { g in Color.clear.preference(key: DDZonePref.self, value: [key: g.frame(in: .named("dd"))]) }
    }
    // The custom drag (user 2026-08-09): a LONG PRESS (0.25s) ARMS the drag — the ghost appears + the actual move/copy
    // begins. A quick tap still flows to onTapGesture. The inner DragGesture has minimumDistance 0 so `.second` fires
    // at the press point the instant the hold completes.
    private func ddDragGesture(_ payload: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("dd")))
            .onChanged { value in
                if case .second(_, let drag) = value {
                    ddDragPayload = payload
                    if let d = drag { ddDragLoc = d.location; ddDropHover = ddZoneAt(d.location, excluding: payload) }
                }
            }
            .onEnded { value in
                if case .second(_, let drag) = value, let d = drag,
                   let target = ddZoneAt(d.location, excluding: payload) { ddLandingKey(payload: payload, targetKey: target) }
                ddResetDrag()
            }
    }
    /// Clear ALL transient drag state — the in-hand ghost, the touched-source highlight, and the hover. A SAFETY NET:
    /// SwiftUI can CANCEL a gesture (its `.onEnded` never fires) when the drop's document mutation re-renders/re-identifies
    /// the source cell mid-gesture, which left the ghost + target highlights stuck on. Called from every gesture's end AND
    /// a page-level release gesture whose root survives the cell re-renders. (user 2026-08-09)
    func ddResetDrag() { ddDragPayload = nil; ddTouchSource = nil; ddDropHover = nil }
    // Drop-target HIGHLIGHT-on-TOUCH (user 2026-08-09): a bare minimumDistance-0 drag fires the instant a finger lands
    // on a draggable source, so the potential destinations light up BEFORE the long-press arms the real drag. Cleared
    // the moment the finger lifts (or the drag drops). Runs simultaneously with the tap + the long-press-drag above.
    private func ddTouchGesture(_ payload: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("dd"))
            .onChanged { _ in if ddTouchSource != payload { ddTouchSource = payload } }
            .onEnded { _ in ddResetDrag() }
    }
    // What's active for the HIGHLIGHT: the in-hand drag payload, or (before the long-press arms) the touched source.
    private var ddActivePayload: String? { ddDragPayload ?? ddTouchSource }
    // The colour of a payload ("colour:<id>" or "cell:<c>:<r>") → the drop-zone highlight hue.
    private func ddPayloadColourID(_ payload: String?) -> String? {
        guard let p = payload else { return nil }
        let t = p.split(separator: ":").map(String.init)
        if t.first == "colour", t.count == 2 { return t[1] }
        if t.first == "cell", t.count == 3, let c = Int(t[1]), let r = Int(t[2]) { return scene.cellAt(c, r)?.colourID }
        return nil
    }
    private var ddDragHue: Color { ddPayloadColourID(ddActivePayload).flatMap { colourColor($0) } ?? Self.editHue }
    private func ddZoneAt(_ p: CGPoint, excluding payload: String) -> String? {
        // a cell dragged onto its OWN frame isn't a landing — skip it so the ghost reads the litter/palette behind
        let selfKey = payload.hasPrefix("cell:") ? "grid:" + payload.dropFirst("cell:".count) : nil
        return ddZones.first(where: { $0.value.contains(p) && $0.key != selfKey })?.key
    }
    private func ddLandingKey(payload: String, targetKey k: String) {
        let t = k.split(separator: ":").map(String.init)
        if t.first == "grid", t.count == 3, let c = Int(t[1]), let r = Int(t[2]) { ddApplyDrop(payload: payload, onto: .grid(c, r)) }
        else if t.first == "palette", t.count == 2, let i = Int(t[1]) { ddApplyDrop(payload: payload, onto: .palette(i)) }
        else if t.first == "litter" { ddApplyDrop(payload: payload, onto: .litter) }
    }
    // The floating in-hand token that follows the finger.
    @ViewBuilder private func ddGhost(_ payload: String) -> some View {
        let hue: Color = {
            let t = payload.split(separator: ":").map(String.init)
            if t.first == "colour", t.count == 2 { return colourColor(t[1]) ?? .gray }
            if t.first == "cell", t.count == 3, let c = Int(t[1]), let r = Int(t[2]), let cell = scene.cellAt(c, r) { return colourColor(cell.colourID) ?? .gray }
            return .gray
        }()
        RoundedRectangle(cornerRadius: 7).fill(hue).frame(width: 40, height: 40).opacity(0.9)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.8), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    // THE PALETTE — the 16 colours as a 4×4 of flat swatches (v1), with the DELETE box below. `litterHeight` sizes
    // the DELETE box (= a swatch in landscape, so palette+DELETE matches the grid height).
    @ViewBuilder private func ddPalette(swatch: CGFloat, litterHeight: CGFloat = 36) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { c in ddSwatch(r * 4 + c, side: swatch) }
                    }
                }
            }
            ddLitter(height: litterHeight)
        }
    }
    // THE COLOUR IDENTITY (landscape) — the swatch + colour name, with the cell count beneath; sits top-left, lined
    // up with the tops of the palette + grid (user 2026-08-09).
    // The colour whose identity/machine the page is showing: the SELECTED palette colour (shows even with 0 placed
    // cells, so a freshly-created colour labels immediately), falling back to the anchor cell's colour. (user 2026-08-09)
    var ddSelectedColourID: String? {
        if ddColourSel >= 0 && ddColourSel < colourIDs.count { return colourIDs[ddColourSel] }
        return editingCell?.colourID
    }
    @ViewBuilder private func ddColourIdentity(showPlay: Bool = true) -> some View {
        if editArmed, let cid = ddSelectedColourID {
            let hue = colourColor(cid) ?? .white
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(hue).frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.55), lineWidth: 1.2))
                    Text(cid.uppercased()).font(.system(size: 18, weight: .black, design: .monospaced)).foregroundColor(hue).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text("\(editSelTargets.count) cell\(editSelTargets.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                if showPlay { ddPlayCellButton() }   // PORTRAIT: PLAY under the labels · LANDSCAPE: PLAY sits right of the grid
            }
        }
    }
    // A palette slot: a DEFINED colour (created, or has placed cells) shows as a flat swatch; an UNDEFINED one is an
    // empty "+" slot — tap it to CREATE a new colour, or drag a grid cell onto it to FORK. Palette starts with one.
    @ViewBuilder private func ddSwatch(_ i: Int, side: CGFloat) -> some View {
        let id = colourIDs[i]
        let selected = ddColourSel == i
        let defined = ddColourShown(i)
        let hover = ddDropHover == "palette:\(i)"
        let dragging = ddActivePayload != nil                        // a source is touched/dragged → light the drop zones in its colour
        let brdr: Color = hover ? (dragging ? ddDragHue : Self.editHue)
                                : (dragging ? ddDragHue.opacity(0.65) : (selected ? .white : .white.opacity(0.12)))
        let brdrW: CGFloat = hover ? 3 : (dragging ? 2 : (selected ? 3 : 1))
        Group {
            if defined {
                RoundedRectangle(cornerRadius: 8).fill(colourColor(id) ?? .gray)
                    .overlay { ddSwatchPlayhead(id, side: side) }        // THE REFILL: a downward fill-wipe on the active column
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(brdr, lineWidth: brdrW))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(ddDragPayload == "colour:\(id)" ? 0.35 : 1)  // lift the source while dragging
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035))       // EMPTY slot — a FORK target
                    .overlay(Image(systemName: "plus").font(.system(size: side * 0.3, weight: .heavy)).foregroundColor(.white.opacity(hover ? 0.8 : 0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(brdr, style: StrokeStyle(lineWidth: max(1, brdrW - 0.5), dash: [4, 3])))
            }
        }
        .frame(width: side, height: side)
        .background(ddZone("palette:\(i)"))                                             // drop-zone frame (cell → FORK/ADOPT)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { if defined { ddSelectColour(i) } else { ddCreateColour(i) } }   // tap "+" → create a new colour
        .simultaneousGesture(ddTouchGesture("colour:\(id)"), including: defined ? .all : .subviews)  // touch → highlight targets
        .simultaneousGesture(ddDragGesture("colour:\(id)"), including: defined ? .all : .subviews)   // only defined colours drag
    }
    // THE PALETTE PLAYHEAD (design "THE REFILL"): while a colour has an UNMUTED cell in the ACTIVE column, its swatch
    // fills downward over the column window. v1 sweeps at the column rate (not yet phase-locked to the exact playhead).
    @ViewBuilder private func ddSwatchPlayhead(_ id: String, side: CGFloat) -> some View {
        if d.playing && ddColourInActiveColumn(id) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = ddBeatAnchor + tl.date.timeIntervalSince(ddBeatAnchorAt) * d.tempo / 60.0   // extrapolate the polled beat
                let musical = musicalOf(live, stepBeats: stepBeats, a: max(1.0, Double(swing) / 50.0))   // column progress runs in MUSICAL time (swing-warped)
                let raw = stepBeats > 0 ? (musical / stepBeats).truncatingRemainder(dividingBy: 1) : 0  // fraction through the current column
                let f = max(0, min(1, raw < 0 ? raw + 1 : raw))                                         // phase-locked to the column boundary
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.4)).frame(height: side * CGFloat(f))
                    Spacer(minLength: 0)
                }.allowsHitTesting(false)
            }
        }
    }
    // THE DELETE box (design "litter"): drop a colour here → delete it AND all its cells; a cell → clear that cell.
    // Always RED (user 2026-08-09), and lit throughout a drag so the delete target reads at a glance.
    private func ddLitter(height: CGFloat = 36) -> some View {
        let hover = ddDropHover == "litter"
        let flashing = ddLitterFlash != nil
        let dragging = ddActivePayload != nil                        // a source is touched/dragged → the delete zone is a live target
        let lit = hover || flashing || dragging
        // The DELETE icon/label appears ONLY while a drag is live (this is the delete target) or the delete-FLASH is up
        // ("−1 cell" etc.); otherwise the box carries a prominent drag-and-drop instruction (user 2026-08-09).
        let showDelete = dragging || flashing
        return Group {
            if showDelete {
                VStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .heavy))
                    Text(ddLitterFlash ?? "DELETE").font(.system(size: 10, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundColor(Verb.delete.hue)
            } else {
                Text("Drag and Drop to place and copy cells")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(0.55)).padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover || flashing ? Verb.delete.hue.opacity(0.18) : (dragging ? Verb.delete.hue.opacity(0.10) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lit ? Verb.delete.hue : .white.opacity(0.15), style: StrokeStyle(lineWidth: lit ? 2 : 1.2, dash: [4, 3]))))
        .contentShape(Rectangle())
        .background(ddZone("litter"))                                                  // drop-zone frame (a drop target only)
        .animation(.easeOut(duration: 0.15), value: flashing)
    }

    // ROW SELECTORS (user 2026-08-09) — one key per grid row; a tap PAINTS the whole row with the selected colour
    // (its representative machine, or a default passthrough if unplaced). No column paint (by design).
    @ViewBuilder private func ddRowSelectors(cell: CGFloat, topInset: CGFloat) -> some View {
        let tint = ddColourSel >= 0 ? (colourColor(colourIDs[ddColourSel]) ?? Color.white) : Color.white.opacity(0.25)
        VStack(spacing: 4) {
            Color.clear.frame(width: 18, height: topInset)   // align the row keys below the column-loop row
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 4).fill(tint.opacity(ddColourSel >= 0 ? 0.6 : 0.12))
                    .overlay(Image(systemName: "arrow.left").font(.system(size: 9, weight: .black)).foregroundColor(.black.opacity(0.55)))
                    .frame(width: 18, height: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { ddPaintRow(r) }
            }
        }
    }

    // COLUMN LOOP buttons (user 2026-08-09) — one per grid column, aligned over the grid; tap to hold/release that
    // column in the loop set (the same `laneMask` the perform grid drives). Lit = held; the active column is ringed.
    @ViewBuilder private func ddColumnLoopRow(cell size: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { c in
                let held = laneMask & (1 << UInt8(c)) != 0
                let active = d.playing && d.effColumn == c && !ddSolo   // solo freezes the timeline — no active-column ring
                RoundedRectangle(cornerRadius: 4).fill(held ? Self.editHue : Color.white.opacity(0.08))
                    .overlay(Image(systemName: "repeat").font(.system(size: 9, weight: .black)).foregroundColor(held ? .black : .white.opacity(0.4)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(active ? 0.8 : 0), lineWidth: 1.5))
                    .frame(width: size, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleLoopColumn(c) }
            }
        }
    }
    // THE GRID — flat-colour 8×8 (design v1: cells are flat colour, the grid stays calm). Tap = mute/unmute + select;
    // drag a cell → palette (FORK/ADOPT) / litter (clear) / another cell (MOVE); a colour drops here to PLACE.
    @ViewBuilder private func ddGrid(cell size: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 4) { ForEach(0..<8, id: \.self) { c in ddGridCell(c, r, size: size) } }
            }
        }
    }
    @ViewBuilder private func ddGridCell(_ c: Int, _ r: Int, size: CGFloat) -> some View {
        let cell = scene.cellAt(c, r)
        let hover = ddDropHover == "grid:\(c):\(r)"
        let dragging = ddActivePayload != nil                                        // a source is touched/dragged → light the drop zones
        // NO grid cell is ever shown as SELECTED (user 2026-08-09) — only the hover/drag drop highlights. The selection
        // lives in the palette + machinery, never on the grid.
        let stroke: Color = hover ? (dragging ? ddDragHue : Self.editHue)
                                  : (dragging ? ddDragHue.opacity(0.65) : .white.opacity(0.12))
        let strokeW: CGFloat = hover ? 3 : (dragging ? 2 : 1)
        let fill: Color = cell.flatMap { colourColor($0.colourID) } ?? Color.white.opacity(0.05)
        RoundedRectangle(cornerRadius: 5)
            .fill(fill.opacity(cell?.muted == true ? 0.28 : 1))
            .frame(width: size, height: size)
            .overlay {
                if cell?.muted == true {
                    Image(systemName: "speaker.slash.fill").font(.system(size: size * 0.3, weight: .heavy)).foregroundColor(.black.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(stroke, lineWidth: strokeW))
            .opacity(ddDragPayload == "cell:\(c):\(r)" ? 0.35 : 1)                         // lift the source while dragging
            .background(ddZone("grid:\(c):\(r)"))                                          // drop-zone frame (colour → PLACE · cell → MOVE)
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onTapGesture { ddGridTap(c, r) }
            .simultaneousGesture(ddTouchGesture("cell:\(c):\(r)"), including: cell != nil ? .all : .subviews)  // touch → highlight targets
            .simultaneousGesture(ddDragGesture("cell:\(c):\(r)"), including: cell != nil ? .all : .subviews)   // only occupied cells drag
    }

    // THE MACHINERY — the selected colour's flow diagram (full-width), with the LIBRARY button to the LEFT of the
    // receivers and RANDOMIZE · MUTATE stacked to the RIGHT of them (user 2026-08-09).
    // The cell the machinery draws: a PLACED cell of the selected colour, else a SYNTHETIC cell for the selected
    // colour (so the machine is ALWAYS visible — a freshly-created, not-yet-placed colour still shows its chain via
    // the 3-tier resolution, and edits are colour-scoped so they persist). (user 2026-08-09)
    private var ddMachineryCell: Cell? {
        if let c = editingCell { return c }
        guard let cid = ddSelectedColourID else { return nil }
        return Cell(colourID: cid)
    }
    @ViewBuilder private func ddMachinery(width: CGFloat) -> some View {
        if editArmed, let cell = ddMachineryCell {
            flowDiagram(cell, width: width)
                .overlay(alignment: .topLeading) { ddLibraryButton().padding(.leading, 10).padding(.top, 14) }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 6) { ddRandomizeButton(); ddMutateButton() }.padding(.trailing, 10).padding(.top, 6)
                }
        } else {
            Text("Tap a colour to edit its machine")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    // PLAY: THIS CELL (user 2026-08-09) — isolate the selected cell's colour and freeze the timeline on its column, so
    // ONLY that machine sounds, ungated by the grid sequence (the grid's active column is ignored). Toggle.
    private func ddPlayCellButton() -> some View {
        let on = ddSolo
        return Button {
            ddSolo.toggle()
            if ddSolo, selCol >= 0, selRow >= 0 { au?.setColourSolo(col: selCol, row: selRow) } else { ddSolo = false; au?.clearColourSolo() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "speaker.wave.2.fill" : "play.fill").font(.system(size: 11, weight: .heavy))
                Text("PLAY: THIS CELL").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? .black : Self.editHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Self.editHue : Self.editHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.editHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // LIBRARY — open the cell library (left of the receivers).
    private func ddLibraryButton() -> some View {
        Button { openCellLibrary() } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill").font(.system(size: 12, weight: .heavy))
                Text("LIBRARY").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(Self.editHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.editHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.editHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // RANDOMIZE — reroll the selected colour's PROCESSOR CHAIN + params (user 2026-08-09; receivers/emitters kept).
    private func ddRandomizeButton() -> some View {
        Button { ddRandomize() } label: {
            HStack(spacing: 6) {
                Image(systemName: "die.face.5.fill").font(.system(size: 12, weight: .heavy))
                Text("RANDOMIZE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(Self.editHue).padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.editHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.editHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }
    // MUTATE — placeholder (a nudged variation of the colour, to come). Inert dashed chip for now.
    private func ddMutateButton() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .heavy))
            Text("MUTATE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundColor(.white.opacity(0.28)).padding(.horizontal, 12).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    // MARK: - selection helpers

    private func ddColourIsPlaced(_ id: String) -> Bool {
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { return true } }
        return false
    }
    /// A palette slot shows a colour when it's been CREATED (defined flag) or has placed cells; else it's a "+" slot.
    private func ddColourShown(_ i: Int) -> Bool {
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
    private func ddColourInActiveColumn(_ id: String) -> Bool {
        let col = d.effColumn
        guard col >= 0 && col < 8 else { return false }
        for r in 0..<8 { if let cell = scene.cellAt(col, r), cell.colourID == id, !cell.muted { return true } }
        return false
    }
    private func ddRepresentativeCell(_ id: String) -> Cell? {
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
        if ddSolo { if selCol >= 0, selRow >= 0 { au?.setColourSolo(col: selCol, row: selRow) } else { au?.clearColourSolo() } }   // PLAY: THIS CELL follows the selection
    }
    private func ddSelect(_ c: Int, _ r: Int) {
        guard let cell = scene.cellAt(c, r) else { return }
        if let i = colourIDs.firstIndex(of: cell.colourID) { ddColourSel = i }
        ddScopeToColour(cell.colourID, anchor: (c, r))
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
    /// Grid tap = MUTE/UNMUTE + SELECT the cell's colour (palette + machinery follow), per the design.
    func ddGridTap(_ col: Int, _ row: Int) {
        guard scene.cellAt(col, row) != nil else { return }
        au?.editScene { $0.cells[col][row]?.muted.toggle() }
        refreshFromDocument(); ddSelect(col, row)
    }
    /// Row-selector PAINT — a 3-press cycle for the selected colour (user 2026-08-09):
    ///   1st press  → fill only the EMPTY cells (populated cells kept).
    ///   2nd press  → fill the WHOLE row, IF the row is now mixed (>1 colour); else revert (as a 3rd press would).
    ///   3rd press  → revert the row to its original state. Switching row/colour restarts the cycle.
    func ddPaintRow(_ r: Int) {
        guard ddColourSel >= 0 else { return }
        let colour = ddColourSel, id = colourIDs[colour]
        if let cyc = ddRowCycle, cyc.row == r, cyc.colour == colour {
            if cyc.phase == 1 && ddRowDistinctColours(r) > 1 {
                ddFillRow(r, id, wholeRow: true)                                       // press 2: mixed row → fill it
                ddRowCycle = DDRowCycle(row: r, colour: colour, phase: 2, original: cyc.original)
            } else {
                ddRevertRow(r, cyc.original); ddRowCycle = nil                         // press 2 (uniform) or press 3 → revert
            }
        } else {
            let original = (0..<8).map { scene.cellAt($0, r) }                         // press 1: capture + fill empties
            ddFillRow(r, id, wholeRow: false)
            ddRowCycle = DDRowCycle(row: r, colour: colour, phase: 1, original: original)
        }
    }
    private func ddCellOfColour(_ id: String) -> Cell {
        var cell = ddRepresentativeCell(id) ?? newbornCell()
        cell.colourID = id; cell.muted = false; cell.processors = nil   // inherit the colour's machine (per-colour model)
        return cell
    }
    private func ddFillRow(_ r: Int, _ id: String, wholeRow: Bool) {
        let template = ddCellOfColour(id)
        au?.editScene { s in for c in 0..<8 where wholeRow || s.cells[c][r] == nil { s.cells[c][r] = template } }
        refreshFromDocument()
    }
    private func ddRevertRow(_ r: Int, _ original: [Cell?]) {
        au?.editScene { s in for c in 0..<8 { s.cells[c][r] = c < original.count ? original[c] : nil } }
        refreshFromDocument()
    }
    private func ddRowDistinctColours(_ r: Int) -> Int { Set((0..<8).compactMap { scene.cellAt($0, r)?.colourID }).count }

    // MARK: - the six drag landings

    private func ddApplyDrop(payload: String, onto target: DDTarget) {
        let parts = payload.split(separator: ":").map(String.init)
        if parts.first == "colour", parts.count == 2 {
            let id = parts[1]
            switch target {
            case .grid(let c, let r): ddPlace(id, at: c, r)          // palette → grid = PLACE
            case .litter:             ddDeleteColour(id)             // colour → litter = DELETE the colour + its cells
            case .palette:            break                          // palette → palette reorg (deferred)
            }
        } else if parts.first == "cell", parts.count == 3, let sc = Int(parts[1]), let sr = Int(parts[2]) {
            switch target {
            case .grid(let dc, let dr): if sc != dc || sr != dr { moveCell((sc, sr), (dc, dr)); ddSelect(dc, dr) }   // grid → grid = MOVE
            case .palette(let i):       ddRecolour(sc, sr, toSlot: i)   // grid → palette = ADOPT (occupied) / FORK (empty)
            case .litter:               ddClearCell(sc, sr)             // grid cell → litter = clear that cell
            }
        }
    }
    private func ddPlace(_ id: String, at c: Int, _ r: Int) {
        let template = ddRepresentativeCell(id)
        au?.editScene { s in
            var cell = template ?? newbornCell()
            cell.colourID = id; cell.muted = false
            s.cells[c][r] = cell
        }
        refreshFromDocument(); ddSelect(c, r)
    }
    /// Grid cell dropped on a palette slot: OCCUPIED slot = ADOPT (the cell takes that colour's machine); EMPTY
    /// (unused) slot = FORK (the cell keeps its own machine, just recolours to the unused colour).
    private func ddRecolour(_ sc: Int, _ sr: Int, toSlot i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        let id = colourIDs[i]
        let adopt = ddColourIsPlaced(id) ? ddRepresentativeCell(id) : nil
        au?.editScene { s in
            guard var cell = s.cellAt(sc, sr) else { return }
            if let rep = adopt { let keepMuted = cell.muted; cell = rep; cell.muted = keepMuted }   // ADOPT the target's machine
            cell.colourID = id                                                                      // FORK just recolours
            s.cells[sc][sr] = cell
        }
        refreshFromDocument(); ddColourSel = i; ddSelect(sc, sr)
    }
    private func ddClearCell(_ c: Int, _ r: Int) {
        guard scene.cellAt(c, r) != nil else { return }
        au?.editScene { $0.cells[c][r] = nil }
        refreshFromDocument()
        if selCol == c && selRow == r { selCol = -1; selRow = -1; sel.reset() }
        ddFlashLitter("−1 cell")
    }
    private func ddDeleteColour(_ id: String) {
        var removed = 0
        au?.editScene { s in
            for c in 0..<8 { for r in 0..<8 where s.cellAt(c, r)?.colourID == id { s.cells[c][r] = nil; removed += 1 } }
        }
        au?.editDocument { doc in if let ci = doc.colours.firstIndex(where: { $0.colourID == id }) { doc.colours[ci].defined = false } }   // un-create → back to a "+" slot
        refreshFromDocument()
        if ddColourSel >= 0 && colourIDs[ddColourSel] == id { ddColourSel = -1; selCol = -1; selRow = -1; sel.reset() }
        ddFlashLitter("−1 colour · \(removed) cell\(removed == 1 ? "" : "s")")
    }
    private func ddFlashLitter(_ msg: String) {
        ddLitterFlash = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if ddLitterFlash == msg { ddLitterFlash = nil } }
    }

    // MARK: - RANDOMIZE (reroll the selected colour's chain)

    func ddRandomize() {
        // Reroll the COLOUR'S machine, not per-cell overrides. A colour IS a machine (GLOBAL by construction), so
        // `withChainColour` writes the templateChain AND clears every cell's per-cell override across all scenes —
        // so ALL cells of the colour (placed now or later) render the one rerolled chain. Writing per-cell overrides
        // to only editSelTargets left un-selected / later-placed cells on the OLD chain → the grid split into two
        // sequences (user 2026-08-09: "identical gold cells identified as different").
        guard editArmed else { return }
        let cid = editingCell?.colourID ?? (ddColourSel >= 0 && ddColourSel < colourIDs.count ? colourIDs[ddColourSel] : nil)
        guard let colourID = cid else { return }
        let n = Int.random(in: 1...3)
        let chain = (0..<n).map { _ in ddRandomProcessor() }
        au?.withChainColour(colourID) { $0 = chain }
        refreshFromDocument()
    }
    private func ddRandomProcessor() -> ProcessorSlot {
        var s = ProcessorSlot(type: ProcessorType.allCases.randomElement() ?? .arp)
        s.params.rate = ArpRate.allCases.randomElement()
        s.params.octaves = Int.random(in: 1...3)
        s.params.gate = Double.random(in: 0.3...0.95)
        s.params.count = Int.random(in: 2...6)
        s.params.ramp = Double.random(in: 0...1)
        s.params.spread = Double.random(in: 0...0.5)
        s.params.curve = Double.random(in: -0.6...0.6)
        s.params.probability = Double.random(in: 0.45...1)
        s.params.harmIntervals = [[0, 3, 4, 5, 7, 12, -12].randomElement() ?? 0, [0, 4, 7].randomElement() ?? 0, 0]
        s.params.euclidPulses = Int.random(in: 2...7)
        s.params.euclidSteps = [8, 16].randomElement() ?? 8
        s.params.echoRepeats = Int.random(in: 2...6)
        s.params.echoDelayDiv = [2, 3, 4, 6].randomElement() ?? 4
        return s
    }
}
