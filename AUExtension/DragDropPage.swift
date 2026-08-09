import SwiftUI

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (16 colours, flat swatches) + ROW SELECTORS + the 8×8 GRID (flat colour v1, calm).
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// Built: layout · selection · machinery · row selectors · RANDOMIZE · the palette playhead · the SIX DRAG LANDINGS
// (palette→grid PLACE · grid→grid MOVE · grid→occupied-palette ADOPT · grid→empty-palette FORK · →LITTER delete).
// Deferred: palette↔palette reorg, SINGLE|MULTI|FREE, the true per-colour machine model.
private enum DDTarget { case grid(Int, Int), palette(Int), litter }

// Drop-zone frames for the CUSTOM finger-tracking drag (SwiftUI's .onDrag/.onDrop don't survive the AU host).
struct DDZonePref: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension DiagView {
    @ViewBuilder func dragDropPage(_ size: CGSize) -> some View {
        let pageW = min(size.width - 24, 1024)                       // hold the global 1024 content cap (user 2026-08-09)
        let topH = min(size.height * 0.46, 400)
        let swatch = max(28, min((topH - 58) / 4, 64))               // 4×4 palette; leave room for the litter box below
        let paletteW = swatch * 4 + 18
        let rowSelW: CGFloat = 22
        let gridCell = max(16, min(46, min((pageW - paletteW - rowSelW - 74) / 8, topH / 8.5)))
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {                    // TOP band CENTRED in the cap: palette LEFT · grid RIGHT
                Spacer(minLength: 0)
                ddPalette(swatch: swatch).frame(width: paletteW, alignment: .top)
                HStack(alignment: .top, spacing: 5) {
                    ddRowSelectors(cell: gridCell)                    // paint a row with the selected colour
                    ddGrid(cell: gridCell)
                }
                Spacer(minLength: 0)
            }.frame(height: topH, alignment: .top)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ddMachinery(width: pageW).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // BOTTOM band, full cap width
        }
        .frame(width: pageW)
        .frame(maxWidth: .infinity)                                  // centre the capped content on wider canvases
        .padding(.vertical, 12)
        .coordinateSpace(name: "dd")                                               // the drag's shared frame of reference
        .onPreferenceChange(DDZonePref.self) { ddZones = $0 }                       // collect the drop-zone frames
        .overlay(alignment: .topLeading) { if let p = ddDragPayload { ddGhost(p).position(x: ddDragLoc.x, y: ddDragLoc.y - 32).allowsHitTesting(false) } }   // the in-hand ghost, above the finger
        .onChange(of: d.beat) { b in ddBeatAnchor = b; ddBeatAnchorAt = Date() }   // playhead: anchor each poll for extrapolation
    }
    // A cell/swatch reports its frame (in "dd" space) so a drag's end point can be hit-tested to a landing.
    private func ddZone(_ key: String) -> some View {
        GeometryReader { g in Color.clear.preference(key: DDZonePref.self, value: [key: g.frame(in: .named("dd"))]) }
    }
    // The custom drag: a real move (≥12pt) picks `payload` up; a plain tap flows to onTapGesture untouched. onChanged
    // tracks the finger + highlights the zone under it; onEnded hit-tests the drop and runs the landing.
    private func ddDragGesture(_ payload: String) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("dd"))
            .onChanged { v in ddDragPayload = payload; ddDragLoc = v.location; ddDropHover = ddZoneAt(v.location, excluding: payload) }
            .onEnded { v in
                let target = ddZoneAt(v.location, excluding: payload)
                ddDragPayload = nil; ddDropHover = nil
                if let target { ddLandingKey(payload: payload, targetKey: target) }
            }
    }
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

    // THE PALETTE — the 16 colours as a 4×4 of flat swatches (v1), with the LITTER box in the spare vertical below.
    @ViewBuilder private func ddPalette(swatch: CGFloat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { c in ddSwatch(r * 4 + c, side: swatch) }
                    }
                }
            }
            ddLitter()
        }
    }
    // A palette slot: a DEFINED colour (has placed cells) shows as a flat swatch; an UNDEFINED one is an empty "+"
    // slot — the FORK target (drag a grid cell here to CREATE a new colour). The palette starts with one colour.
    @ViewBuilder private func ddSwatch(_ i: Int, side: CGFloat) -> some View {
        let id = colourIDs[i]
        let selected = ddColourSel == i
        let defined = ddColourIsPlaced(id)
        let hover = ddDropHover == "palette:\(i)"
        Group {
            if defined {
                RoundedRectangle(cornerRadius: 8).fill(colourColor(id) ?? .gray)
                    .overlay { ddSwatchPlayhead(id, side: side) }        // THE REFILL: a downward fill-wipe on the active column
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(hover ? Self.editHue : (selected ? Color.white : Color.white.opacity(0.12)), lineWidth: hover || selected ? 3 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(ddDragPayload == "colour:\(id)" ? 0.35 : 1)  // lift the source while dragging
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035))       // EMPTY slot — a FORK target
                    .overlay(Image(systemName: "plus").font(.system(size: side * 0.3, weight: .heavy)).foregroundColor(.white.opacity(hover ? 0.8 : 0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hover ? Self.editHue : .white.opacity(0.12), style: StrokeStyle(lineWidth: hover ? 2.5 : 1, dash: [4, 3])))
            }
        }
        .frame(width: side, height: side)
        .background(ddZone("palette:\(i)"))                                             // drop-zone frame (cell → FORK/ADOPT)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { if defined { ddSelectColour(i) } }
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
    // THE LITTER (design): drop a colour here → delete it AND all its cells; drop a cell here → clear that cell.
    private func ddLitter() -> some View {
        let hover = ddDropHover == "litter"
        let flashing = ddLitterFlash != nil
        return HStack(spacing: 6) {
            Image(systemName: "trash").font(.system(size: 13, weight: .heavy))
            Text(ddLitterFlash ?? "LITTER").font(.system(size: 10, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundColor(hover || flashing ? Verb.delete.hue : .white.opacity(0.3)).frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover || flashing ? Verb.delete.hue.opacity(0.18) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hover || flashing ? Verb.delete.hue : .white.opacity(0.15), style: StrokeStyle(lineWidth: hover || flashing ? 2 : 1.2, dash: [4, 3]))))
        .contentShape(Rectangle())
        .background(ddZone("litter"))                                                  // drop-zone frame (a drop target only)
        .animation(.easeOut(duration: 0.15), value: flashing)
    }

    // ROW SELECTORS (user 2026-08-09) — one key per grid row; a tap PAINTS the whole row with the selected colour
    // (its representative machine, or a default passthrough if unplaced). No column paint (by design).
    @ViewBuilder private func ddRowSelectors(cell: CGFloat) -> some View {
        let tint = ddColourSel >= 0 ? (colourColor(colourIDs[ddColourSel]) ?? Color.white) : Color.white.opacity(0.25)
        VStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 4).fill(tint.opacity(ddColourSel >= 0 ? 0.6 : 0.12))
                    .overlay(Image(systemName: "arrow.left").font(.system(size: 9, weight: .black)).foregroundColor(.black.opacity(0.55)))
                    .frame(width: 18, height: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { ddPaintRow(r) }
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
        let selected = selCol == c && selRow == r
        let hover = ddDropHover == "grid:\(c):\(r)"
        let inScope = ddColourSel >= 0 && cell?.colourID == colourIDs[ddColourSel]   // a sibling of the edited colour
        let stroke: Color = hover ? Self.editHue : (selected ? .white : (inScope ? .white.opacity(0.5) : .white.opacity(0.12)))
        let strokeW: CGFloat = hover || selected ? 2.5 : (inScope ? 1.5 : 1)
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
            .simultaneousGesture(ddDragGesture("cell:\(c):\(r)"), including: cell != nil ? .all : .subviews)   // only occupied cells drag
    }

    // THE MACHINERY — the selected colour's flow diagram, full-width, with PLAY THIS CELL + RANDOMIZE on the right.
    @ViewBuilder private func ddMachinery(width: CGFloat) -> some View {
        if editArmed, let cell = editingCell {
            let hue = colourColor(cell.colourID) ?? .white
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {          // PROMINENT colour header — this machine IS the selected colour (user 2026-08-09)
                    RoundedRectangle(cornerRadius: 7).fill(hue).frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.55), lineWidth: 1.5))
                    Text(cell.colourID.uppercased()).font(.system(size: 22, weight: .black, design: .monospaced)).foregroundColor(hue)
                    Text("· \(editSelTargets.count) cell\(editSelTargets.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }
                Rectangle().fill(hue.opacity(0.7)).frame(height: 2)
                HStack(alignment: .top, spacing: 12) {
                    flowDiagram(cell, width: width - 140)
                    VStack(spacing: 8) {
                        playScopeButton()      // PLAY THIS CELL (solo the selected cell) — reuses the play-scope button
                        ddRandomizeButton()
                        Spacer(minLength: 0)
                    }.frame(width: 128)
                }
            }
        } else {
            Text(ddColourSel >= 0 ? "This colour isn't on the grid yet — drag it onto the grid, or use a row selector"
                                  : "Tap a colour, or a placed cell, to edit its machine")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    // RANDOMIZE — reroll the selected colour's PROCESSOR CHAIN + params (user 2026-08-09; receivers/emitters kept).
    private func ddRandomizeButton() -> some View {
        Button { ddRandomize() } label: {
            HStack(spacing: 6) {
                Image(systemName: "die.face.5.fill").font(.system(size: 12, weight: .heavy))
                Text("RANDOMIZE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(Self.editHue).frame(maxWidth: .infinity).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.editHue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.editHue.opacity(0.5), lineWidth: 1)))
        }.buttonStyle(.plain)
    }

    // MARK: - selection helpers

    private func ddColourIsPlaced(_ id: String) -> Bool {
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { return true } }
        return false
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
    /// Grid tap = MUTE/UNMUTE + SELECT the cell's colour (palette + machinery follow), per the design.
    func ddGridTap(_ col: Int, _ row: Int) {
        guard scene.cellAt(col, row) != nil else { return }
        au?.editScene { $0.cells[col][row]?.muted.toggle() }
        refreshFromDocument(); ddSelect(col, row)
    }
    /// Paint the whole row with the selected colour — its representative machine, or a default passthrough cell.
    func ddPaintRow(_ r: Int) {
        guard ddColourSel >= 0 else { return }
        let id = colourIDs[ddColourSel]
        let template = ddRepresentativeCell(id)
        au?.editScene { s in
            for c in 0..<8 {
                var cell = template ?? newbornCell()
                cell.colourID = id; cell.muted = false
                s.cells[c][r] = cell
            }
        }
        refreshFromDocument()
    }

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
        guard editArmed, editingCell != nil, !editSelTargets.isEmpty else { return }
        let n = Int.random(in: 1...3)
        let chain = (0..<n).map { _ in ddRandomProcessor() }
        au?.editCells(editSelTargets) { $0.processors = chain }
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
