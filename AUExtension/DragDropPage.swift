import SwiftUI

// THE DRAG&DROP PAGE (design stage, user 2026-08-09) — a NEW first tab. Per DESIGN-dragdrop-page.md: a colour is a
// machine; you edit colours, placed as cells. LANDSCAPE-first, ONE non-scrolling panel:
//   TOP band  = the 4×4 PALETTE (the 16 colours, flat swatches) + the 8×8 GRID.
//   BOTTOM band = the MACHINERY (the existing flow diagram) full-width, with PLAY THIS CELL + RANDOMIZE at its right.
// PHASE 1 (this build, per Paul): layout + selection + machinery. No drag yet — palette/grid taps SELECT (a grid tap
// also MUTES); the flow diagram edits a representative placed cell of the selected colour (scaffold on the per-cell
// machine). Deferred: the six drag landings, the palette fill-wipe playhead, SINGLE|MULTI|FREE, RANDOMIZE, the LITTER.
extension DiagView {
    @ViewBuilder func dragDropPage(_ size: CGSize) -> some View {
        let topH = min(size.height * 0.46, 400)
        let swatch = max(28, min((topH - 58) / 4, 64))               // 4×4 palette; leave room for the litter box below
        let paletteW = swatch * 4 + 18
        let gridCell = max(16, min(46, min((size.width - paletteW - 60) / 8, topH / 8.5)))
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {                    // TOP band: palette LEFT · grid RIGHT
                ddPalette(swatch: swatch).frame(width: paletteW, alignment: .top)
                GridView(scene: scene, colours: docColours, playColumn: d.effColumn,
                         trueColumn: d.playing ? ((d.absoluteStep % 8) + 8) % 8 : -1, playing: d.playing,
                         beat: d.beat, tempo: d.tempo, stepBeats: stepBeats, swing: swing,
                         cellHeight: gridCell, editing: false,
                         selCol: selCol, selRow: selRow, onTap: ddGridTap, flagNoDest: false)
                    .frame(width: gridCell * 8, height: topH, alignment: .topLeading)
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
                .overlay(alignment: .topTrailing) {
                    if placed { Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6).padding(4) }   // has placed cells
                }
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.white : Color.white.opacity(0.12), lineWidth: selected ? 3 : 1))
        }.buttonStyle(.plain)
    }
    // THE LITTER (design): drop a colour here to delete it, a cell to clear it. Visual only in phase 1 (drag arrives next).
    private func ddLitter() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "trash").font(.system(size: 13, weight: .heavy))
            Text("LITTER").font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.3)).frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
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
            Text(ddColourSel >= 0 ? "This colour isn't on the grid yet — placement arrives with drag & drop"
                                  : "Tap a colour, or a placed cell, to edit its machine")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    // RANDOMIZE — rolls the selected colour (design). Inert placeholder in phase 1 (no roll engine yet).
    private func ddRandomizeButton() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "die.face.5.fill").font(.system(size: 12, weight: .heavy))
            Text("RANDOMIZE").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundColor(.white.opacity(0.28)).frame(maxWidth: .infinity).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    // MARK: - selection (drives the existing flow-diagram selection: selCol/selRow/sel + ddColourSel)

    private func ddColourIsPlaced(_ id: String) -> Bool {
        for c in 0..<8 { for r in 0..<8 where scene.cellAt(c, r)?.colourID == id { return true } }
        return false
    }
    /// Select a palette colour → point the machinery at the FIRST placed cell of that colour (its representative
    /// machine). No placed cell → nothing to edit yet (the machinery shows a hint; placement comes with drag).
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
}
