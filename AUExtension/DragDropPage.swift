import SwiftUI

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (the 16 colours, flat swatches) + ROW SELECTORS + the 8×8 GRID.
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// Built: layout · selection · machinery · ROW SELECTORS (paint a row with the selected colour) · RANDOMIZE (reroll
// the selected colour's chain + params) · the PALETTE PLAYHEAD (a downward fill-wipe while a colour is in the active
// column). Deferred: the six drag landings (next), SINGLE|MULTI|FREE, the true per-colour machine model.
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
                HStack(spacing: 5) {
                    ddRowSelectors(cell: gridCell, top: GridGeometry.headH + GridGeometry.vGap)   // paint a row with the selected colour
                    GridView(scene: scene, colours: docColours, playColumn: d.effColumn,
                             trueColumn: d.playing ? ((d.absoluteStep % 8) + 8) % 8 : -1, playing: d.playing,
                             beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                             cellHeight: gridCell, editing: false,
                             selCol: selCol, selRow: selRow, onTap: ddGridTap, flagNoDest: false)
                        .frame(width: gridCell * 8, height: topH, alignment: .topLeading)
                }
                Spacer(minLength: 0)
            }.frame(height: topH, alignment: .top)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ddMachinery(width: size.width - 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // BOTTOM band
        }.padding(12)
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
        Button { ddSelectColour(i) } label: {
            RoundedRectangle(cornerRadius: 8).fill(colourColor(id) ?? .gray)
                .frame(width: side, height: side)
                .overlay { ddSwatchPlayhead(id, side: side) }          // THE REFILL: a downward fill-wipe on the active column
                .overlay(alignment: .topTrailing) {
                    if placed { Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6).padding(4) }   // has placed cells
                }
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.white : Color.white.opacity(0.12), lineWidth: selected ? 3 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    // THE PALETTE PLAYHEAD (design "THE REFILL"): while a colour has an UNMUTED cell in the ACTIVE column, its swatch
    // fills downward over the column window. v1 sweeps at the column rate (not yet phase-locked to the exact playhead).
    @ViewBuilder private func ddSwatchPlayhead(_ id: String, side: CGFloat) -> some View {
        if d.playing && ddColourInActiveColumn(id) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let colDur = max(0.08, stepBeats * 60.0 / max(1, d.tempo))
                let f = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: colDur) / colDur
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.4)).frame(height: side * CGFloat(f))
                    Spacer(minLength: 0)
                }.allowsHitTesting(false)
            }
        }
    }
    // THE LITTER (design): drop a colour here to delete it, a cell to clear it. Visual only for now (drag arrives next).
    private func ddLitter() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "trash").font(.system(size: 13, weight: .heavy))
            Text("LITTER").font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.3)).frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    // ROW SELECTORS (user 2026-08-09) — one key per grid row; a tap PAINTS the whole row with the selected colour
    // (its representative machine, or a default passthrough if the colour isn't placed). No column paint (by design).
    @ViewBuilder private func ddRowSelectors(cell: CGFloat, top: CGFloat) -> some View {
        let tint = ddColourSel >= 0 ? (colourColor(colourIDs[ddColourSel]) ?? Color.white) : Color.white.opacity(0.25)
        VStack(spacing: GridGeometry.vGap) {
            Color.clear.frame(width: 18, height: top)                 // align with the grid's column-key row
            ForEach(0..<8, id: \.self) { r in
                Button { ddPaintRow(r) } label: {
                    RoundedRectangle(cornerRadius: 4).fill(tint.opacity(ddColourSel >= 0 ? 0.6 : 0.12))
                        .overlay(Image(systemName: "arrow.left").font(.system(size: 9, weight: .black)).foregroundColor(.black.opacity(0.55)))
                        .frame(width: 18, height: cell)
                }.buttonStyle(.plain).disabled(ddColourSel < 0)
            }
        }
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
            Text(ddColourSel >= 0 ? "This colour isn't on the grid yet — place it with a row selector (or drag, coming next)"
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

    // MARK: - selection (drives the existing flow-diagram selection: selCol/selRow/sel + ddColourSel)

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
    /// Select a palette colour → point the machinery at the FIRST placed cell of that colour (its representative
    /// machine). No placed cell → nothing to edit yet (the machinery shows a hint; place it via a row selector/drag).
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
        guard let cell = scene.cellAt(col, row) else { return }
        au?.editScene { $0.cells[col][row]?.muted.toggle() }
        refreshFromDocument()
        if let i = colourIDs.firstIndex(of: cell.colourID) { ddColourSel = i }
        selCol = col; selRow = row; sel.reset(); sel.add(GridView.GridPos(col: col, row: row))
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
