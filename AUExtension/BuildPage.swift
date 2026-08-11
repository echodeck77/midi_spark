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
        let avail = max(1, size.width - BuildGeom.colGap * 2 - 20)
        let leftW = max(1, avail / 3 * 0.8)                        // the MACHINE column is 20% narrower than an equal third
        let gridColW = max(1, (avail - leftW) / 2)                 // staging + play split the reclaimed width
        // the PLAY grid is the widest: a cell-sized ROW BUTTON + a ½-cell PART-CELL column + 8 grid cells (+ 9 gaps).
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (gridColW - BuildGeom.cellGap * 9) / 9.5))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // AnyView boundaries: opaque `some View` types get INLINED into the parent's concrete type, so the
                // whole page collapses into ONE giant nested generic whose metadata instantiation overflows the Swift
                // demangler's stack (SIGSEGV opening BUILD). AnyView is a nominal type the demangler won't recurse
                // through — each column's type is instantiated separately + bounded.
                AnyView(buildPaletteColumn().frame(width: leftW, alignment: .center))
                AnyView(buildStagingColumn(cell: cell).frame(width: gridColW, alignment: .center))
                AnyView(buildPlayColumn(cell: cell).frame(width: gridColW, alignment: .center))
            }
            AnyView(buildMachinery())
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.cellGap * 9 - 24) / 9.5))
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
        let gridW = cell * 9 + BuildGeom.cellGap * 8              // row button + 8 cells + the 8 gaps between the 9
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THE STAGING GRID"))
            AnyView(buildStagingGrid(cell: cell, hue: hue))       // AnyView — keeps the deep 8×8 type out of this body
            AnyView(buildStagingVerbBox(gridW: gridW))
            Spacer(minLength: 0)
            AnyView(buildPopulate())                              // bottom of the centre column, above the footer
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // POPULATE — the call-to-action at the bottom of the centre column: an upward chevron above the text.
    @ViewBuilder private func buildPopulate() -> some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.up").font(.system(size: 14, weight: .heavy)).foregroundColor(buildPink)
            Text("POPULATE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowButtons(cell: cell, hue: hue, bands: [8])     // cell-sized ROW BUTTONS on the LEFT (staging = one group of 8)
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

    // A part boundary. It occupies exactly ONE inter-cell gap so the grid stays uniformly spaced; the LINE is drawn
    // only where asked (the row buttons), centred in that gap so nothing shifts and both columns stay row-aligned.
    @ViewBuilder private func partDivider(line: Bool) -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: BuildGeom.cellGap)
            .overlay { if line { Rectangle().fill(Color.white.opacity(0.6)).frame(height: 2) } }
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

    // ROW BUTTONS — a cell-sized selector per grid row on the LEFT edge; shared by both grids. `bands` is the row
    // grouping (staging = [8]; play = [3,2,1,1,1]) so the buttons carry the SAME part dividers as the grid → they align
    // row-for-row. A top spacer clears the loop-key row.
    @ViewBuilder private func buildRowButtons(cell: CGFloat, hue: Color, bands: [Int]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: BuildGeom.loopKeyH)   // align past the loop-key row
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                    if idx > 0 { partDivider(line: true) }         // the DIVIDING LINE lives here, between the row buttons
                    VStack(spacing: BuildGeom.cellGap) {
                        ForEach(0..<rows, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.4))
                                .frame(width: cell, height: cell)
                                .overlay(Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.85)))
                        }
                    }
                }
            }
        }
    }

    // PART CELLS — a ½-cell-wide cell PER PART on the play grid's left, each spanning its part's full height (part 1 =
    // 3 cells high, part 2 = 2, parts 3–5 = 1). They connect the per-row buttons into the grid and carry the same part
    // dividers so everything aligns. The last part (row 8) is the FREE band (pink).
    @ViewBuilder private func buildPartCells(cell: CGFloat, bands: [Int]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell / 2, height: BuildGeom.loopKeyH)   // align past the loop-key row
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                    if idx > 0 { partDivider(line: false) }        // no line here — just the gap (the line is on the row buttons)
                    let h = cell * CGFloat(rows) + BuildGeom.cellGap * CGFloat(rows - 1)   // the part's full height
                    let free = idx == bands.count - 1
                    RoundedRectangle(cornerRadius: 6).fill((free ? buildPink : buildCyan).opacity(0.5))
                        .frame(width: cell / 2, height: h)
                        .overlay(Text("\(idx + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)))
                }
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID"))
            // The side ROW BUTTONS assign from STAGING → PERFORM when the transport is STOPPED (function wires later).
            AnyView(HStack(alignment: .top, spacing: 0) {          // spacing 0 → the buttons + part cells CONNECT onto the grid
                AnyView(buildRowButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1, 1]))   // cell-sized row buttons on the LEFT, part-grouped
                AnyView(buildPartCells(cell: cell, bands: [3, 2, 1, 1, 1]))                    // ½-cell PART cells (3-high · 2-high · 1 · 1 · 1)
                VStack(spacing: BuildGeom.cellGap) {
                    buildLoopKeys(cell: cell)                     // the column-selector row
                    AnyView(buildPlayBands(cell: cell))          // AnyView — keeps the deep bands type out of this body
                }
            })
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // the PLAY grid rows — its OWN opaque view (see buildPaletteColumn's metadata-stack note).
    @ViewBuilder private func buildPlayBands(cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.cellGap) {                       // UNIFORM 8 rows — no line inside the grid; parts show on the row buttons
            ForEach(0..<8, id: \.self) { r in
                let p = r < 3 ? 0 : (r < 5 ? 1 : r - 3)            // this row's PART (parts: 0-2 · 3-4 · 5 · 6 · 7)
                let base = buildHues[p % buildHues.count]           // one base hue PER PART
                HStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<8, id: \.self) { c in
                        let shade = 0.35 + 0.5 * Double((r * 3 + c * 2 + p) % 4) / 3.0   // a variety of SIMILAR shades within the part
                        RoundedRectangle(cornerRadius: 7).fill(base.opacity(shade))
                            .frame(width: cell, height: cell)
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
            buildFooterBtn("🎲 RANDOMIZE", pink: true)             // inviting — the machine's re-roll
            buildFooterBtn("MUTATE")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: BuildGeom.barH, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
    }

    // a fixed-width footer button (the footer uses a Spacer, so these can't be maxWidth-fill like buildActionBtn).
    @ViewBuilder private func buildFooterBtn(_ label: String, pink: Bool = false) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(pink ? Color.black : Color.white)
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(pink ? buildPink : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(buildCyan.opacity(pink ? 0 : 0.35), lineWidth: 1))
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
