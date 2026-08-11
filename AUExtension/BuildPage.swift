import SwiftUI

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-iteration-3.md + -build-page-iteration-4.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (user 2026-08-11: THREE EQUAL COLUMNS + the machinery strip along the bottom; NO focus highlight):
//   • LEFT COLUMN (the build flow, top→bottom): [● PLAY THIS CELL] → [PART ▾][+ NEW] → 1·INPUT (R1–R4, MIDI ⎓ | PIANO
//     ⌨ per door; a PIANO door reveals its octave keyboard) → 2·THE CAST (the FULL 4×4 palette, 16 slots) · 🎲
//     RANDOMIZE (the chain's die = roll the colour's machine) → 3·OUTPUT (A–D) → [APPLY TO STAGING →] → LITTER.
//   • MIDDLE COLUMN — STAGING (the workshop 8×8: row rail · loop keys · variation rows), with the VERBS in their own
//     box BELOW: [PLACE · MOVE · DELETE] (spring-held workbench verbs) then [APPLY TO PLAY → · MUTATE · 🎲 RE-ROLL].
//   • RIGHT COLUMN — the PLAY grid: five FIXED bands. THE TARGET DECIDES THE VERB: APPLY TO PLAY arms the bands →
//     tap a LANE = FLATTEN · tap a LADDER = COPY ROWS · tap FREE = takes land · long-press a ladder = flatten-into-row.
//   • MACHINERY STRIP (bottom, full width) — the chain: ID · receiver box · slots + ghost · emitter box.
//
// ┌─ BUILD STATUS ─ INCREMENT 1 (this file): LAYOUT SKELETON — placeholder content, NO engine wiring. Every dimension
// │ is a named constant in `BuildGeom`; each region is its own helper (placement edits are one-liners). NEXT (region
// │ by region): left-column I/O + cast → staging roll (reuse Dice) → the PLACE/MOVE/DELETE verbs (spring-hold + engine;
// │ retires the DRAG&DROP tab) → APPLY TO PLAY arming + the band-decides-verb landings → the real machinery snake.
// │ Deferred here: the PIANO keyboard is a placeholder; the real voice behind the buttons.  ──────────────────────────┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners.
private enum BuildGeom {
    static let colGap:   CGFloat = 10       // gap between the three equal columns
    static let cellMin:  CGFloat = 18       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 34
    static let cellGap:  CGFloat = 4         // inter-cell gap
    static let loopKeyH: CGFloat = 18       // the staging loop-key row height
    static let rowRailW: CGFloat = 14       // the staging left row-selector rail
    static let playRailW: CGFloat = 26      // the play grid's left band-glyph rail (the wider of the two → it sets the shared cell)
    static let seam:     CGFloat = 2        // the gap between play bands
    static let barH:     CGFloat = 76       // the machinery snake bar height
    static let playCalm: Double = 0.45      // the PLAY grid CALMS — dimmer cells
    static let castSwatch: CGFloat = 28     // the cast palette swatch (8 across · 4 down)
    static let castGap:    CGFloat = 4
    static var castW: CGFloat { castSwatch * 8 + castGap * 7 }   // the cast's total width — INPUT/OUTPUT rows match it
}

// Placeholder cast hues (mockup palette). Real colours come from the part's cast when the palette is wired.
private let buildHues: [Color] = [
    Color(red: 0.91, green: 0.70, blue: 0.23),   // amber
    Color(red: 0.19, green: 0.83, blue: 0.91),   // cyan
    Color(red: 0.29, green: 0.49, blue: 1.00),   // blue
    Color(red: 0.91, green: 0.36, blue: 0.44),   // red
    Color(red: 0.35, green: 0.84, blue: 0.48),   // green
    Color(red: 0.69, green: 0.42, blue: 0.91),   // purple
]
private let buildPanel = Color(red: 0.08, green: 0.09, blue: 0.11)
private let buildCell  = Color(red: 0.10, green: 0.12, blue: 0.15)
private let buildDim   = Color(white: 0.36)
private let buildPink  = Color(red: 0.94, green: 0.41, blue: 0.85)
private let buildCyan  = Color(red: 0.19, green: 0.83, blue: 0.91)

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildVerb: String { case place = "PLACE", move = "MOVE", delete = "DELETE" }

extension DiagView {

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        // AUv3 views get an initial ZERO / degenerate layout pass; laying the grids out then would compute a NEGATIVE
        // column width → SwiftUI's fatal "Invalid frame dimension" (the plugin fails to load in AUM). Draw nothing
        // until a real, finite size arrives.
        if size.width.isFinite, size.height.isFinite, size.width > 80, size.height > 80 {
            if size.width > size.height { buildLandscape(size) } else { buildPortrait(size) }
        } else {
            Color.clear
        }
    }

    // ── LANDSCAPE: three EQUAL columns (palette · staging · play) over the full-width machinery strip ──────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        let colW = max(1, (size.width - BuildGeom.colGap * 2 - 20) / 3)   // clamp ≥ 1: never a negative frame width
        // one shared cell size fits an 8×8 grid + its rail inside a column; the PLAY rail is the wider → it sets it.
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (colW - BuildGeom.playRailW - BuildGeom.cellGap * 7) / 8))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // AnyView boundaries: opaque `some View` types get INLINED into the parent's concrete type, so the
                // whole page collapses into ONE giant nested generic whose metadata instantiation overflows the Swift
                // demangler's stack (SIGSEGV opening BUILD). AnyView is a nominal type the demangler won't recurse
                // through — each column's type is instantiated separately + bounded.
                AnyView(buildPaletteColumn().frame(width: colW, alignment: .leading))
                AnyView(buildStagingColumn(cell: cell).frame(width: colW, alignment: .leading))
                AnyView(buildPlayColumn(cell: cell).frame(width: colW, alignment: .leading))
            }
            AnyView(buildMachinery())
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.rowRailW - 24) / 8))
        VStack(spacing: 12) {
            AnyView(buildPaletteColumn())          // AnyView boundaries — see buildLandscape's note (metadata-stack overflow)
            AnyView(buildStagingColumn(cell: cell))
            AnyView(buildPlayColumn(cell: cell))
            AnyView(buildMachinery())
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── LEFT COLUMN: play-cell · part · input(+keyboard) · cast 4×4 (+🎲) · output · APPLY TO STAGING · litter ──────
    // IMPORTANT: keep this VStack SHALLOW — the INPUT/CAST/OUTPUT groups are SEPARATE opaque sub-views. A single
    // deeply-nested SwiftUI view type here makes the Swift runtime's type-metadata demangler recurse until it
    // overflows the stack when the AU instantiates the view → SIGSEGV the moment BUILD opens (device crash 2026-08-11).
    @ViewBuilder private func buildPaletteColumn() -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS MACHINE"))
            AnyView(buildPartHeader())
            AnyView(buildInputSection())
            AnyView(buildCastSection())
            AnyView(buildOutputSection())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private func buildInputSection() -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildStep("1 · INPUT")
            HStack(spacing: 4) {
                buildIOChip("R1 ⌨", on: true, keys: true, fill: true)
                buildIOChip("R2 ⎓", fill: true); buildIOChip("R3 ⎓", fill: true); buildIOChip("R4 ⎓", fill: true)
            }
            .frame(width: BuildGeom.castW)                         // match the receivers row to the cast palette width
            buildKeyboard()                                        // a PIANO door reveals its octave keyboard (placeholder)
            HStack(spacing: 6) { buildOctBtn("OCT −"); buildOctBtn("OCT +") }.frame(width: 176)   // octave shift
        }
    }

    @ViewBuilder private func buildCastSection() -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildStep("2 · THE CAST")
            buildCastPalette()
        }
    }

    @ViewBuilder private func buildOutputSection() -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildStep("3 · OUTPUT")
            HStack(spacing: 4) {
                buildIOChip("A", on: true, fill: true); buildIOChip("B", fill: true)
                buildIOChip("C", fill: true); buildIOChip("D", fill: true)
            }
            .frame(width: BuildGeom.castW)                         // match the emitters row to the cast palette width
            buildMidiOutInfo()                                     // clear MIDI OUT channel info, piano-height
        }
    }

    @ViewBuilder private func buildPartHeader() -> some View {
        HStack(spacing: 6) {
            Text("PART 1 ▾").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
            Text("+ NEW").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(buildDim)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            Spacer(minLength: 0)
        }
    }

    // The octave keyboard shown under a selected PIANO door (placeholder: one octave, some notes held). Mockup layout.
    @ViewBuilder private func buildKeyboard() -> some View {
        let whites: [(x: CGFloat, held: Bool)] = [(0, true), (25, false), (50, true), (75, false), (100, true), (125, false), (150, false)]
        let blacks: [(x: CGFloat, held: Bool)] = [(17, false), (42, false), (92, false), (117, true), (142, false)]
        ZStack(alignment: .topLeading) {
            ForEach(Array(whites.enumerated()), id: \.offset) { _, k in
                RoundedRectangle(cornerRadius: 3).fill(k.held ? buildCyan : Color(white: 0.9))
                    .frame(width: 24, height: 52).overlay(RoundedRectangle(cornerRadius: 3).stroke(buildPanel, lineWidth: 1))
                    .offset(x: k.x)
            }
            ForEach(Array(blacks.enumerated()), id: \.offset) { _, k in
                RoundedRectangle(cornerRadius: 2).fill(k.held ? buildCyan : buildPanel)
                    .frame(width: 15, height: 31).offset(x: k.x)
            }
        }
        .frame(width: 176, height: 52, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    // OCT −/+ buttons under the piano (octave shift for the selected PIANO door).
    @ViewBuilder private func buildOctBtn(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(0.4), lineWidth: 1))
    }

    // clear MIDI OUT info below the emitters — piano-height, cast-width.
    @ViewBuilder private func buildMidiOutInfo() -> some View {
        VStack(spacing: 3) {
            Text("MIDI OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
            Text("A → CH 1").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
        }
        .frame(width: BuildGeom.castW, height: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
    }

    @ViewBuilder private func buildCastPalette() -> some View {
        VStack(spacing: BuildGeom.castGap) {
            ForEach(0..<4, id: \.self) { row in                    // 8×4 = 32 slots (8 columns · 4 rows)
                HStack(spacing: BuildGeom.castGap) {
                    ForEach(0..<8, id: \.self) { col in
                        let i = row * 8 + col
                        let hue = i < buildHues.count ? buildHues[i] : buildCell
                        RoundedRectangle(cornerRadius: 6).fill(hue)
                            .frame(width: BuildGeom.castSwatch, height: BuildGeom.castSwatch)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                                .opacity(i == buildSelColour ? 1 : 0))
                            .onTapGesture { buildSelColour = i }
                    }
                }
            }
        }
    }

    // ── MIDDLE COLUMN: STAGING (header · rail+loopkeys+grid · label) with the VERBS in their own box below ──────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        // the staging grid's total width = the row rail + 8 cells + the 8 gaps between them (rail↔grid + 7 inter-cell).
        let gridW = BuildGeom.rowRailW + cell * 8 + BuildGeom.cellGap * 8
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THE STAGING GRID"))
            AnyView(buildStagingGrid(cell: cell, hue: hue))       // AnyView — keeps the deep 8×8 type out of this body
            AnyView(buildStagingVerbBox(gridW: gridW))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowRail(cell: cell, hue: hue)                     // the row-selector rail on staging's LEFT edge
            VStack(spacing: BuildGeom.cellGap) {
                buildLoopKeys(cell: cell)                          // the column-selector (loop-key) row
                VStack(spacing: BuildGeom.cellGap) {               // 8 variation rows, one colour, dim/act placeholders
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                let filled = (c + r * 3) % 4 != 0
                                let active = (c + r) % 5 == 0
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(filled ? hue.opacity(active ? 1 : 0.28) : buildCell)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.white, lineWidth: 2).opacity(active ? 1 : 0))
                            }
                        }
                    }
                }
            }
        }
    }

    // THE VERB BOX (a different box below staging): the workbench verbs, then the workshop's outcomes.
    @ViewBuilder private func buildStagingVerbBox(gridW: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { buildVerbBtn(.place); buildVerbBtn(.move); buildVerbBtn(.delete) }
            HStack(spacing: 6) {
                buildActionBtn("APPLY TO PLAY →", pink: true)      // arms the play grid; the band decides FLATTEN|COPY ROWS
                buildActionBtn("MUTATE")
                buildActionBtn("🎲 RE-ROLL")                        // re-roll the variation ladder (distinct from the column's 🎲)
            }
        }
        .padding(8)
        .frame(width: gridW)                                       // match the verb box to the grid above it
        .background(RoundedRectangle(cornerRadius: 10).fill(buildPanel))
    }

    // the COLUMN-SELECTOR (loop-key) row — 8 keys the width of the grid columns; shared by staging + play so they match.
    @ViewBuilder private func buildLoopKeys(cell: CGFloat) -> some View {
        HStack(spacing: BuildGeom.cellGap) {
            ForEach(0..<8, id: \.self) { c in
                RoundedRectangle(cornerRadius: 5)
                    .fill(c == 1 || c == 2 ? buildCyan : buildPanel)
                    .frame(width: cell, height: BuildGeom.loopKeyH)
            }
        }
    }

    // the ROW-SELECTOR RAIL — one bar per staging row on the LEFT edge; tinted the selected hue, chevron into the grid.
    @ViewBuilder private func buildRowRail(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: BuildGeom.rowRailW, height: BuildGeom.loopKeyH)   // align the rail past the loop-key row
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(hue.opacity(0.5))
                    .frame(width: BuildGeom.rowRailW, height: cell)
                    .overlay(Text("‹").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7)))
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID"))
            AnyView(HStack(spacing: 6) {                           // the column-selector row, aligned over the bands
                Color.clear.frame(width: BuildGeom.playRailW, height: BuildGeom.loopKeyH)   // clear the glyph rail
                buildLoopKeys(cell: cell)
            })
            AnyView(buildPlayBands(cell: cell))                   // AnyView — keeps the deep bands type out of this body
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // the five fixed PLAY bands + glyph rail — its OWN opaque view (see buildPaletteColumn's metadata-stack note).
    @ViewBuilder private func buildPlayBands(cell: CGFloat) -> some View {
        let bands: [(rows: Int, glyph: String, free: Bool)] = [
            (3, "⊻", false), (2, "⊻", false), (1, "≡", false), (1, "≡", false), (1, "▶", true),
        ]
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: BuildGeom.seam) {                      // the glyph rail
                ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                    let h = cell * CGFloat(b.rows) + BuildGeom.cellGap * CGFloat(b.rows - 1)
                    Text(b.glyph).font(.system(size: 10, weight: .bold))
                        .foregroundColor(b.free ? buildPink : buildCyan)
                        .frame(width: BuildGeom.playRailW, height: h)
                        .overlay(Rectangle().fill(b.free ? buildPink : buildCyan).frame(width: 3), alignment: .leading)
                }
            }
            VStack(spacing: BuildGeom.seam) {                      // the bands
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, b in
                    VStack(spacing: BuildGeom.cellGap) {
                        ForEach(0..<b.rows, id: \.self) { r in
                            HStack(spacing: BuildGeom.cellGap) {
                                ForEach(0..<8, id: \.self) { c in
                                    let hue = buildHues[(idx + r + c) % buildHues.count]
                                    let filled = (c + r + idx) % 3 != 0
                                    RoundedRectangle(cornerRadius: 7)   // PLAY calms — dimmer fill
                                        .fill(filled ? hue.opacity(BuildGeom.playCalm) : buildCell)
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── MACHINERY STRIP (bottom, full width): the chain — ID · IN box · slots + ghost · OUT box ────────────────────
    @ViewBuilder private func buildMachinery() -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(hue).frame(width: 40, height: 40)   // the colour ID
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            buildSlot("ARP"); Text("┈").foregroundColor(buildDim)
            buildSlot("MASK"); Text("┈").foregroundColor(buildDim)
            buildSlot("MOD"); Text("┈").foregroundColor(buildDim)
            buildSlot("+", dashed: true)
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            buildBox("A: MIDI OUT", "ch1")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: BuildGeom.barH, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    // The identical audition button at the top of each column (dot + label, cyan-bordered).
    @ViewBuilder private func buildColumnButton(_ label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(buildCyan).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(buildCell))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildCyan, lineWidth: 1))
    }
    @ViewBuilder private func buildStep(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false, fill: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7)
            .frame(maxWidth: fill ? .infinity : nil).frame(height: 48)   // fill → the row spreads evenly to the cast width; height doubled (24→48)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan, lineWidth: keys && !on ? 1 : 0))
    }
    @ViewBuilder private func buildActionBtn(_ s: String, pink: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
            .foregroundColor(pink ? Color.black : Color.white).tracking(0.5)
            .frame(maxWidth: .infinity).frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(pink ? buildPink : buildCell))
    }
    // the spring-held workbench verb (iteration 4). Skeleton: a tap arms/disarms it (the real gesture is hold→release).
    @ViewBuilder private func buildVerbBtn(_ v: BuildVerb) -> some View {
        let armed = buildVerb == v
        Text(v.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(armed ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(buildCyan, lineWidth: 1).opacity(armed ? 0 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture { buildVerb = armed ? nil : v }
    }
    @ViewBuilder private func buildBox(_ title: String, _ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundColor(.white)
            Text(ch).font(.system(size: 8, design: .monospaced)).foregroundColor(buildCyan)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(buildCell))
    }
    @ViewBuilder private func buildSlot(_ s: String, dashed: Bool = false) -> some View {
        Text(s).font(.system(size: 8, design: .monospaced)).foregroundColor(dashed ? buildDim : .white)
            .frame(width: 44, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(dashed ? Color.clear : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(dashed ? buildDim : Color(white: 0.15),
                                                              style: StrokeStyle(lineWidth: dashed ? 1.3 : 1, dash: dashed ? [4] : [])))
    }
}
