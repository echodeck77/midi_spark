import SwiftUI
import UniformTypeIdentifiers

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (16 colours, flat swatches) + ROW SELECTORS + the 8×8 GRID (flat colour v1, calm).
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// Built: layout · selection · machinery · row selectors · RANDOMIZE · the palette playhead · the SIX DRAG LANDINGS
// (palette→grid PLACE · grid→grid MOVE · grid→occupied-palette ADOPT · grid→empty-palette FORK · →LITTER delete).
// Deferred: palette↔palette reorg, SINGLE|MULTI|FREE, the true per-colour machine model.
private enum DDTarget { case grid(Int, Int), palette(Int), litter }

extension DiagView {
    @ViewBuilder func dragDropPage(_ size: CGSize) -> some View {
        let topH = min(size.height * 0.46, 400)
        let swatch = max(28, min((topH - 58) / 4, 64))               // 4×4 palette; leave room for the litter box below
        let paletteW = swatch * 4 + 18
        let rowSelW: CGFloat = 22
        let gridCell = max(16, min(46, min((size.width - paletteW - rowSelW - 74) / 8, topH / 8.5)))
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {                    // TOP band: palette LEFT · row selectors + grid RIGHT
                ddPalette(swatch: swatch).frame(width: paletteW, alignment: .top)
                HStack(alignment: .top, spacing: 5) {
                    ddRowSelectors(cell: gridCell)                    // paint a row with the selected colour
                    ddGrid(cell: gridCell)
                }
                Spacer(minLength: 0)
            }.frame(height: topH, alignment: .top)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ddMachinery(width: size.width - 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // BOTTOM band
        }.padding(12)
        .onChange(of: d.beat) { b in ddBeatAnchor = b; ddBeatAnchorAt = Date() }   // playhead: anchor each poll for extrapolation
    }
    // A drop-target highlight binding: SwiftUI drives it true while a drag hovers this target, false when it leaves.
    private func ddHoverBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { ddDropHover == key }, set: { ddDropHover = $0 ? key : (ddDropHover == key ? nil : ddDropHover) })
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
    @ViewBuilder private func ddSwatch(_ i: Int, side: CGFloat) -> some View {
        let id = colourIDs[i]
        let selected = ddColourSel == i
        let placed = ddColourIsPlaced(id)
        let hover = ddDropHover == "palette:\(i)"
        RoundedRectangle(cornerRadius: 8).fill(colourColor(id) ?? .gray)
            .frame(width: side, height: side)
            .overlay { ddSwatchPlayhead(id, side: side) }             // THE REFILL: a downward fill-wipe on the active column
            .overlay(alignment: .topTrailing) {
                if placed { Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6).padding(4) }   // has placed cells
            }
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(hover ? Self.editHue : (selected ? Color.white : Color.white.opacity(0.12)), lineWidth: hover || selected ? 3 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { ddSelectColour(i) }
            .onDrag { NSItemProvider(object: "colour:\(id)" as NSString) }              // drag a colour → grid (PLACE) / litter (DELETE)
            .onDrop(of: [.text], isTargeted: ddHoverBinding("palette:\(i)")) { ddHandleDrop($0, onto: .palette(i)) }   // a cell dropped here → FORK/ADOPT
    }
    // THE PALETTE PLAYHEAD (design "THE REFILL"): while a colour has an UNMUTED cell in the ACTIVE column, its swatch
    // fills downward over the column window. v1 sweeps at the column rate (not yet phase-locked to the exact playhead).
    @ViewBuilder private func ddSwatchPlayhead(_ id: String, side: CGFloat) -> some View {
        if d.playing && ddColourInActiveColumn(id) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = ddBeatAnchor + tl.date.timeIntervalSince(ddBeatAnchorAt) * d.tempo / 60.0   // extrapolate the polled beat
                let raw = stepBeats > 0 ? (live / stepBeats).truncatingRemainder(dividingBy: 1) : 0     // fraction through the current column
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
        .animation(.easeOut(duration: 0.15), value: flashing)
        .onDrop(of: [.text], isTargeted: ddHoverBinding("litter")) { ddHandleDrop($0, onto: .litter) }
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
        let fill: Color = cell.flatMap { colourColor($0.colourID) } ?? Color.white.opacity(0.05)
        RoundedRectangle(cornerRadius: 5)
            .fill(fill.opacity(cell?.muted == true ? 0.28 : 1))
            .frame(width: size, height: size)
            .overlay {
                if cell?.muted == true {
                    Image(systemName: "speaker.slash.fill").font(.system(size: size * 0.3, weight: .heavy)).foregroundColor(.black.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(hover ? Self.editHue : (selected ? Color.white : Color.white.opacity(0.12)), lineWidth: hover || selected ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onTapGesture { ddGridTap(c, r) }
            .onDrag { NSItemProvider(object: "cell:\(c):\(r)" as NSString) }               // drag this cell → palette / litter / grid
            .onDrop(of: [.text], isTargeted: ddHoverBinding("grid:\(c):\(r)")) { ddHandleDrop($0, onto: .grid(c, r)) }   // a colour / cell dropped here
    }

    // THE MACHINERY — the selected colour's flow diagram, full-width, with PLAY THIS CELL + RANDOMIZE on the right.
    @ViewBuilder private func ddMachinery(width: CGFloat) -> some View {
        if editArmed, let cell = editingCell {
            HStack(alignment: .top, spacing: 12) {
                flowDiagram(cell, width: width - 140)
                VStack(spacing: 8) {
                    playScopeButton()          // PLAY THIS CELL (solo the selected cell) — reuses the play-scope button
                    ddRandomizeButton()
                    Spacer(minLength: 0)
                }.frame(width: 128)
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
    private func ddSelect(_ c: Int, _ r: Int) {
        if let cell = scene.cellAt(c, r), let i = colourIDs.firstIndex(of: cell.colourID) { ddColourSel = i }
        selCol = c; selRow = r; sel.reset(); sel.add(GridView.GridPos(col: c, row: r))
    }
    /// Select a palette colour → point the machinery at the FIRST placed cell of that colour (the representative
    /// machine). No placed cell → nothing to edit yet (place it via a row selector or a drag).
    func ddSelectColour(_ i: Int) {
        guard i >= 0 && i < colourIDs.count else { return }
        ddColourSel = i
        let id = colourIDs[i]
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id {
            selCol = c; selRow = r; sel.reset(); sel.add(GridView.GridPos(col: c, row: r)); return
        } }
        selCol = -1; selRow = -1; sel.reset()
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

    private func ddHandleDrop(_ providers: [NSItemProvider], onto target: DDTarget) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String else { return }
            DispatchQueue.main.async { ddApplyDrop(payload: s, onto: target) }
        }
        return true
    }
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
