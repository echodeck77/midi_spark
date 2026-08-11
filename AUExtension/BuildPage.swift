import SwiftUI

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-focus-model.md + -build-page-iteration-3.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (iteration 3 — the page reads left→right as BUILD · STAGE · DEPLOY, every verb at its own front door):
//   • LEFT COLUMN (the build flow, top→bottom): [● PLAY THIS CELL] (the machine's audition + the focus lamp's handle)
//     → [PART ▾][+ NEW] → 1·INPUT (R1–R4, MIDI ⎓ | PIANO ⌨ per door; a PIANO door reveals its octave keyboard) →
//     2·THE CAST (the FULL 4×4 palette, 16 slots) → 3·OUTPUT (A–D) → [APPLY TO STAGING →] (pink, the closing word) →
//     LITTER. CHAIN has NO numbered step — the SNAKE below IS the chain.
//   • STAGING (centre) — the workshop 8×8 (row rail · loop keys · variation rows) with its OWN verb strip beneath:
//     [APPLY TO PLAY →] · [MUTATE] · [🎲 re-roll].
//   • PLAY (right) — the piece, five FIXED bands. THE TARGET DECIDES THE VERB: APPLY TO PLAY arms the bands →
//     tap a LANE = FLATTEN · tap a LADDER = COPY ROWS · tap FREE = takes land · long-press a ladder = flatten-into-row.
//   • MACHINERY SNAKE (bottom, full width) — the chain: ID · receiver box · slots + ghost · emitter box + RANDOMIZE.
//   The bridge column is GONE — its width flows to the two grids.
//
// THE FOCUS LAMP (focus-model §1: the voice is the cursor): the two WORKSHOP zones are the LEFT COLUMN (the machine)
// and STAGING; one owns the voice (lit: full-sat + pink border + ● badge / bright snake thread), the other dims to
// ~60%. The PLAY grid sits OUTSIDE the economy (always calm). ~150ms crossfade when the lamp changes hands.
//
// ┌─ BUILD STATUS ─ INCREMENT 1 (this file): LAYOUT SKELETON — placeholder content, NO engine wiring. Every dimension
// │ is a named constant in `BuildGeom`; each region is its own helper (placement edits are one-liners). NEXT (region
// │ by region): left-column I/O + cast → staging roll (reuse Dice) → rung picking + loop keys → APPLY TO PLAY arming +
// │ the band-decides-verb landings → the real machinery snake (reuse the flow diagram) → the FREE band tap-to-voice.
// │ Deferred here: the PIANO keyboard is a placeholder, the animated snake pulse, the real voice behind the lamp.  ───┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners.
private enum BuildGeom {
    static let paletteW: CGFloat = 196      // LEFT column width (the build flow)
    static let colGap:   CGFloat = 10       // gap between the three landscape columns
    static let cellMin:  CGFloat = 20       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 34       // iteration 4: grids SMALLER + calmer (was 48)
    static let cellGap:  CGFloat = 4        // iteration 4: tighter inter-cell gaps (was 5)
    static let loopKeyH: CGFloat = 18       // the staging loop-key row height
    static let rowRailW: CGFloat = 14       // the staging left row-selector rail
    static let playRailW: CGFloat = 26      // the play grid's left band-glyph rail
    static let seam:     CGFloat = 2        // the gap between play bands
    static let barH:     CGFloat = 76       // the machinery snake bar height
    static let playCalm: Double = 0.45      // iteration 4: the PLAY grid CALMS — dim its cells (was 0.6)
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

// focus-model §1: which WORKSHOP zone owns the single voice — the machine (the left column) or staging.
enum BuildFocus { case palette, staging }

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildVerb: String { case place = "PLACE", move = "MOVE", delete = "DELETE" }

extension DiagView {
    // The lamp: is each workshop zone lit (owns the voice) or dimmed (~60%, touchable)?
    fileprivate var palLit: Bool { buildFocus == .palette }
    fileprivate var stgLit: Bool { buildFocus == .staging }
    // GRAB the voice (focus-model §2). ● PLAY THIS CELL / cast-select pull it to the machine; staging column keys +
    // the ● badge pull it to staging. ~150ms crossfade teaches.
    fileprivate func buildGrabStaging() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .staging } }
    fileprivate func buildGrabPalette() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .palette } }
    @ViewBuilder fileprivate func buildFocusBorder(_ lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10).stroke(buildPink, lineWidth: 2).opacity(lit ? 1 : 0).padding(-3)
    }
    @ViewBuilder fileprivate func buildPlayingBadge() -> some View {
        HStack(spacing: 3) {
            Circle().fill(buildPink).frame(width: 6, height: 6)
            Text("PLAYING").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
    }

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        let landscape = size.width > size.height
        if landscape { buildLandscape(size) } else { buildPortrait(size) }
    }

    // ── LANDSCAPE: three columns (palette · staging · play) over the full-width machinery snake ────────────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        // one cell size fits BOTH 8×8 grids + the staging row rail + the play glyph rail inside the width left of the
        // palette column.
        let budget = size.width - BuildGeom.paletteW - BuildGeom.rowRailW - BuildGeom.playRailW - BuildGeom.colGap * 2 - 34
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, budget / 16))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // PALETTE (the machine) + STAGING are the two workshop zones — the lamp lights one, dims the other (§1).
                buildPaletteColumn().frame(width: BuildGeom.paletteW)
                    .opacity(palLit ? 1 : 0.6).overlay(buildFocusBorder(palLit))
                    .contentShape(Rectangle()).onTapGesture { buildGrabPalette() }
                    .animation(.easeInOut(duration: 0.15), value: buildFocus)
                buildStagingColumn(cell: cell)
                    .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                    .animation(.easeInOut(duration: 0.15), value: buildFocus)
                buildPlayColumn(cell: cell)                        // PLAY sits OUTSIDE the focus economy (always calm)
            }
            buildMachinery()
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.rowRailW - 24) / 8))
        VStack(spacing: 12) {
            buildPaletteColumn()
                .opacity(palLit ? 1 : 0.6).overlay(buildFocusBorder(palLit))
                .contentShape(Rectangle()).onTapGesture { buildGrabPalette() }
                .animation(.easeInOut(duration: 0.15), value: buildFocus)
            buildStagingColumn(cell: cell)
                .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                .animation(.easeInOut(duration: 0.15), value: buildFocus)
            buildPlayColumn(cell: cell)
            buildMachinery()
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── LEFT COLUMN: play-cell · part · input(+keyboard) · cast 4×4 · output · APPLY TO STAGING · litter ───────────
    @ViewBuilder private func buildPaletteColumn() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // [● PLAY THIS CELL] — first: the machine's audition AND the focus lamp's handle (pulls the voice left).
            HStack(spacing: 8) {
                Circle().fill(buildCyan).frame(width: 8, height: 8)
                Text("PLAY THIS CELL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).tracking(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildCyan, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { buildGrabPalette() }

            buildPartHeader()

            buildStep("1 · INPUT")
            HStack(spacing: 4) {
                buildIOChip("R1 ⌨", on: true, keys: true)
                buildIOChip("R2 ⎓"); buildIOChip("R3 ⎓"); buildIOChip("R4 ⎓")
            }
            buildKeyboard()                                        // a PIANO door reveals its octave keyboard (placeholder)

            HStack(spacing: 6) {                                   // iteration 4: RANDOMIZE is the CHAIN's verb → it joins the cast/chain step
                buildStep("2 · THE CAST")
                Spacer(minLength: 0)
                Text("🎲 RANDOMIZE").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(0.5)
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(buildCell))
            }
            buildCastPalette()                                     // the FULL 4×4 palette (16 slots)

            buildStep("3 · OUTPUT")
            HStack(spacing: 4) { buildIOChip("A", on: true); buildIOChip("B"); buildIOChip("C"); buildIOChip("D") }

            buildActionBtn("APPLY TO STAGING →", pink: true)       // the column's closing word, pointing at its destination

            buildLitter()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder private func buildCastPalette() -> some View {
        VStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { row in                    // FULL 4×4 = 16 slots (iteration 3: the compact bar starved it)
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { col in
                        let i = row * 4 + col
                        let hue = i < buildHues.count ? buildHues[i] : buildCell
                        RoundedRectangle(cornerRadius: 8).fill(hue)
                            .frame(width: 40, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                                .opacity(i == buildSelColour ? 1 : 0))
                            .onTapGesture { buildSelColour = i; buildGrabPalette() }   // selecting a cast colour is a workbench act — lamp left
                    }
                }
            }
        }
    }

    @ViewBuilder private func buildLitter() -> some View {
        Text("🗑 LITTER").font(.system(size: 10, design: .monospaced)).foregroundColor(buildDim)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).stroke(buildDim, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
    }

    // ── STAGING column: header+badge · rail+loopkeys+grid · the workshop verb strip · simple→complex label ─────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {                                   // header — the ● badge appears when staging owns the voice, and is a GRAB
                buildLabel("STAGING — the current question")
                if stgLit { buildPlayingBadge() }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle()).onTapGesture { buildGrabStaging() }
            HStack(alignment: .top, spacing: BuildGeom.cellGap) {
                buildRowRail(cell: cell, hue: hue)                 // the row-selector rail on staging's LEFT edge
                VStack(spacing: BuildGeom.cellGap) {
                    HStack(spacing: BuildGeom.cellGap) {           // the loop-key row — a tap GRABS the voice onto staging (§2)
                        ForEach(0..<8, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(c == 1 || c == 2 ? buildCyan : buildPanel)
                                .frame(width: cell, height: BuildGeom.loopKeyH)
                        }
                    }
                    .contentShape(Rectangle()).onTapGesture { buildGrabStaging() }
                    VStack(spacing: BuildGeom.cellGap) {           // 8 variation rows, one colour, dim/act placeholders
                        ForEach(0..<8, id: \.self) { r in
                            HStack(spacing: BuildGeom.cellGap) {
                                ForEach(0..<8, id: \.self) { c in
                                    let filled = (c + r * 3) % 4 != 0
                                    let active = (c + r) % 5 == 0
                                    // §2 silence tell: when staging is DIMMED, active picks show as HOLLOW rings; the voice fills them.
                                    let restHollow = active && !stgLit
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(filled && !restHollow ? hue.opacity(active ? 1 : 0.28) : buildCell)
                                        .frame(width: cell, height: cell)
                                        .overlay(RoundedRectangle(cornerRadius: 7)
                                            .stroke(stgLit ? Color.white : hue, lineWidth: 2).opacity(active ? 1 : 0))
                                }
                            }
                        }
                    }
                }
            }
            // iteration 4 §4: the WORKBENCH verbs (PLACE · MOVE · DELETE — spring-held, replacing the drag), then the
            // workshop's OUTCOMES (apply · mutate · re-roll). Two rows under staging.
            HStack(spacing: 6) {
                buildVerbBtn(.place); buildVerbBtn(.move); buildVerbBtn(.delete)
            }
            HStack(spacing: 6) {
                buildActionBtn("APPLY TO PLAY →", pink: true)      // arms the play grid; the band decides FLATTEN|COPY ROWS
                buildActionBtn("MUTATE")
                buildActionBtn("🎲 RE-ROLL").frame(width: 96)      // re-roll the variation ladder (distinct from the column's 🎲 = roll the machine)
            }
            Text("SIMPLE ▲ · rows = variations of the selected colour · ▼ COMPLEX")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
        }
    }

    // the ROW-SELECTOR RAIL — one bar per staging row on the LEFT edge; tinted the selected hue, chevron into the grid.
    @ViewBuilder private func buildRowRail(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: 5) {
            Color.clear.frame(width: BuildGeom.rowRailW, height: BuildGeom.loopKeyH)   // align the rail past the loop-key row
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(hue.opacity(0.5))
                    .frame(width: BuildGeom.rowRailW, height: cell)
                    .overlay(Text("‹").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7)))
            }
        }
    }

    // ── PLAY column: the piece, five fixed bands + glyph rail; the target decides the verb ─────────────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        let bands: [(rows: Int, glyph: String, free: Bool)] = [
            (3, "⊻", false), (2, "⊻", false), (1, "≡", false), (1, "≡", false), (1, "▶", true),
        ]
        VStack(alignment: .leading, spacing: 6) {
            buildLabel("PLAY — the target decides: LANE=flatten · LADDER=copy rows")
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: BuildGeom.seam) {                  // the glyph rail
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                        let h = cell * CGFloat(b.rows) + BuildGeom.seam * CGFloat(b.rows - 1)
                        Text(b.glyph).font(.system(size: 10, weight: .bold))
                            .foregroundColor(b.free ? buildPink : buildCyan)
                            .frame(width: BuildGeom.playRailW, height: h)
                            .overlay(Rectangle().fill(b.free ? buildPink : buildCyan).frame(width: 3), alignment: .leading)
                    }
                }
                VStack(spacing: BuildGeom.seam) {                  // the bands
                    ForEach(Array(bands.enumerated()), id: \.offset) { idx, b in
                        VStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<b.rows, id: \.self) { r in
                                HStack(spacing: BuildGeom.cellGap) {
                                    ForEach(0..<8, id: \.self) { c in
                                        let hue = buildHues[(idx + r + c) % buildHues.count]
                                        let filled = (c + r + idx) % 3 != 0
                                        RoundedRectangle(cornerRadius: 7)   // iteration 4: PLAY calms — dimmer fill
                                            .fill(filled ? hue.opacity(BuildGeom.playCalm) : buildCell)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text("3-LADDER ⊻ · 2-LADDER ⊻ · LANE · LANE · FREE ▶ (tap-to-voice)")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
        }
    }

    // ── MACHINERY SNAKE (bottom, full width): the chain — ID · IN box · slots + ghost · OUT box + RANDOMIZE ────────
    @ViewBuilder private func buildMachinery() -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        // §1: in the MACHINE phase (palette owns the voice) the snake's thread comes alive. Skeleton = brighten; the
        // animated door→wire pulse arrives with the real wiring.
        let thread = palLit ? buildCyan : buildDim
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(hue).frame(width: 40, height: 40)   // the colour ID
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
            buildSlot("ARP"); Text("┈").foregroundColor(thread)
            buildSlot("MASK"); Text("┈").foregroundColor(thread)
            buildSlot("MOD"); Text("┈").foregroundColor(thread)
            buildSlot("+", dashed: true)
            Text("┈┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
            buildBox("A: MIDI OUT", "ch1")
            Spacer(minLength: 0)                                   // iteration 4: RANDOMIZE left the bar (now the cast step); PLAY THIS CELL is the column top
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: BuildGeom.barH, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func buildLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(buildPink).tracking(1)
    }
    @ViewBuilder private func buildStep(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan, lineWidth: keys && !on ? 1 : 0))
    }
    @ViewBuilder private func buildActionBtn(_ s: String, pink: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
            .foregroundColor(pink ? Color.black : Color.white).tracking(0.5)
            .frame(maxWidth: .infinity).frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(pink ? buildPink : buildCell))
    }
    // the spring-held workbench verb (iteration 4). Skeleton: a tap arms/disarms it (the real gesture is hold→release).
    @ViewBuilder private func buildVerbBtn(_ v: BuildVerb) -> some View {
        let armed = buildVerb == v
        Text(v.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(armed ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(buildCyan, lineWidth: armed ? 0 : 1).opacity(0.5))
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
