import SwiftUI

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// Docs/mockup-build-three-grids-landscape.html (user 2026-08-11). The new PRIMARY workshop and the default landing
// tab. The flow is PALETTE → STAGING → PLAY:
//   • PALETTE (left)  — the current PART's build flow: pick a colour, choose its INPUT (MIDI|PIANO door) · CHAIN ·
//     OUTPUT (by hand in the machinery or via RANDOMIZE); the PART's cast (a 4×4 of provisional colours) + litter.
//   • STAGING (centre) — the workshop 8×8: APPLY TO STAGING rolls 8 VARIATIONS of the selected colour, one per row,
//     SIMPLE at the top → COMPLEX below. Loop columns, tap rungs to pick the groove, MUTATE a rung.
//   • BRIDGE (thin)   — APPLY TO STAGING · MUTATE · → · FLATTEN · COPY ROWS · → + the BAND TARGET strip.
//   • PLAY (right)    — the piece, five FIXED bands: 3-LADDER · 2-LADDER · LANE · LANE · FREE. Applies land here.
//   • MACHINERY (below, full width) — the colour's snake: IN door → chain slots → OUT + the cluster.
//
// This page is DESTINED to REPLACE the DRAG&DROP page and the PROCESSORS (cell-edit) page — both stay live until it
// supersedes them.
//
// ┌─ BUILD STATUS ────────────────────────────────────────────────────────────────────────────────────────────┐
// │ INCREMENT 1 (this file): the LAYOUT SKELETON only — the five regions in their mockup proportions with        │
// │ PLACEHOLDER content and NO engine wiring, so placement can be iterated first (Paul: "lots of placement       │
// │ changes as we go"). Nothing here reads or writes the document yet. Each region is its own helper so a "move   │
// │ X to Y" is a local edit, and every dimension is a named constant in `BuildGeom` below.                        │
// │ NEXT increments (region by region, each device-verifiable): wire the palette I/O steps + cast → the staging  │
// │ roll (reuse Dice) → rung picking + loop keys → FLATTEN / COPY ROWS onto the play bands → the machinery snake  │
// │ (reuse the existing flow diagram) → the FREE band tap-to-voice.                                               │
// └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners (nothing below hard-codes sizes).
private enum BuildGeom {
    static let paletteW: CGFloat = 200      // LEFT column width (the build flow + cast)
    static let bridgeW:  CGFloat = 96       // the thin action/bridge column
    static let colGap:   CGFloat = 12       // gap between the four landscape columns
    static let cellMin:  CGFloat = 22       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 46
    static let loopKeyH: CGFloat = 18       // the staging loop-key row height
    static let railW:    CGFloat = 26       // the play grid's left band-glyph rail
    static let machineH: CGFloat = 92       // the machinery snake band height
    static let seam:     CGFloat = 3        // the gap between play bands
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

// focus-model §1: which WORKSHOP zone owns the single voice (the PLAY grid is outside this economy).
enum BuildFocus { case palette, staging }

extension DiagView {
    // The lamp: is each workshop zone lit (owns the voice) or dimmed (~60%, touchable)?
    fileprivate var palLit: Bool { buildFocus == .palette }
    fileprivate var stgLit: Bool { buildFocus == .staging }
    // GRAB the voice onto staging (focus-model §2: column keys + the ● badge are the deliberate grab). ~150ms teach.
    fileprivate func buildGrabStaging() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .staging } }
    fileprivate func buildGrabPalette() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .palette } }
    // The accent border on the lit zone.
    @ViewBuilder fileprivate func buildFocusBorder(_ lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10).stroke(buildPink, lineWidth: 2).opacity(lit ? 1 : 0).padding(-4)
    }
    // The ● PLAYING badge for a lit zone's header.
    @ViewBuilder fileprivate func buildPlayingBadge() -> some View {
        HStack(spacing: 3) {
            Circle().fill(buildPink).frame(width: 6, height: 6)
            Text("PLAYING").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
    }

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        let landscape = size.width > size.height
        // One cell size fits BOTH 8×8 grids side by side (staging + play) inside the width left after the two side
        // columns and the play rail. Clamped so it stays tappable and never overflows.
        let gridsBudget = size.width - BuildGeom.paletteW - BuildGeom.bridgeW - BuildGeom.railW - BuildGeom.colGap * 4 - 20
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, gridsBudget / 16))
        Group {
            if landscape { buildLandscape(size, cell: cell) }
            else         { buildPortrait(size, cell: cell) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ── LANDSCAPE: four columns (palette · staging · bridge · play) over the full-width machinery snake ───────────
    @ViewBuilder private func buildLandscape(_ size: CGSize, cell: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // PALETTE + STAGING are the two workshop zones — the focus lamp lights one, dims the other (§1).
                buildPaletteColumn().frame(width: BuildGeom.paletteW)
                    .opacity(palLit ? 1 : 0.6).overlay(buildFocusBorder(palLit))
                    .contentShape(Rectangle()).onTapGesture { buildGrabPalette() }   // building the machine pulls the lamp left
                    .animation(.easeInOut(duration: 0.15), value: buildFocus)
                buildStaging(cell: cell)
                    .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                    .animation(.easeInOut(duration: 0.15), value: buildFocus)
                buildBridge().frame(width: BuildGeom.bridgeW)
                buildPlayGrid(cell: cell)                                            // PLAY sits OUTSIDE the focus economy (always sounding, calm)
            }
            buildMachinery()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (part → palette → staging → play → machinery) ────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize, cell: CGFloat) -> some View {
        let pcell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - 20) / 8))
        VStack(spacing: 12) {
            buildPartHeader()
            buildPaletteColumn()
                .opacity(palLit ? 1 : 0.6).overlay(buildFocusBorder(palLit))
                .contentShape(Rectangle()).onTapGesture { buildGrabPalette() }
                .animation(.easeInOut(duration: 0.15), value: buildFocus)
            buildStaging(cell: pcell)
                .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                .animation(.easeInOut(duration: 0.15), value: buildFocus)
            buildLabel("PLAY — the piece (tap a band to receive)")
            buildPlayGrid(cell: pcell)
            buildMachinery()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    // ── LEFT COLUMN: the build flow (part header → INPUT → CHAIN → OUTPUT → cast palette → litter) ─────────────────
    @ViewBuilder private func buildPaletteColumn() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            buildPartHeader()
            buildStep("1 · INPUT")
            HStack(spacing: 4) {
                buildIOChip("R1 ⌨", on: true, keys: true)
                buildIOChip("R2 ⎓"); buildIOChip("R3 ⎓"); buildIOChip("R4 ⎓")
            }
            Text("R1 = PIANO door · ⎓ = MIDI · (keyboard reveals here)")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
            buildStep("2 · CHAIN")
            HStack(spacing: 4) { buildIOChip("BUILD ▾", on: true); buildIOChip("🎲 RANDOMIZE") }
            buildStep("3 · OUTPUT")
            HStack(spacing: 4) { buildIOChip("A", on: true); buildIOChip("B"); buildIOChip("C"); buildIOChip("D") }
            buildStep("4 · PART CAST → drag to staging")
            buildCastPalette()
            buildLitter()
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

    @ViewBuilder private func buildCastPalette() -> some View {
        VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { row in
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

    // ── CENTRE: the STAGING 8×8 (loop keys + variations, simple→complex) ──────────────────────────────────────────
    @ViewBuilder private func buildStaging(cell: CGFloat) -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {                                   // header — the ● badge appears when staging owns the voice, and doubles as the GRAB
                buildLabel("STAGING")
                if stgLit { buildPlayingBadge() }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle()).onTapGesture { buildGrabStaging() }
            HStack(alignment: .top, spacing: 5) {
                buildRowRail(cell: cell, hue: hue)                 // §3: the row-selector rail on staging's LEFT edge (workbench's primary verb)
                VStack(spacing: 5) {
                    HStack(spacing: 5) {                           // the loop-key row — a tap here GRABS the voice onto staging (§2)
                        ForEach(0..<8, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(c == 1 || c == 2 ? buildCyan : buildPanel)
                                .frame(width: cell, height: BuildGeom.loopKeyH)
                        }
                    }
                    .contentShape(Rectangle()).onTapGesture { buildGrabStaging() }
                    VStack(spacing: 5) {                           // 8 variation rows, one colour, dim/act placeholders
                        ForEach(0..<8, id: \.self) { r in
                            HStack(spacing: 5) {
                                ForEach(0..<8, id: \.self) { c in
                                    let filled = (c + r * 3) % 4 != 0
                                    let active = (c + r) % 5 == 0
                                    // §2 silence tell: when staging is DIMMED, active picks show as HOLLOW rings; the voice arriving fills them.
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
            Text("SIMPLE ▲ · rows = variations · ▼ COMPLEX")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
        }
    }

    // §3 the ROW-SELECTOR RAIL — one bar per staging row on the LEFT edge. With a cast colour selected, tapping a row
    // fills it with that colour (the 3-press cycle grammar; exact cycle = Paul's device call). Skeleton: furniture +
    // the selected hue; the fill wires when staging placement lands.
    @ViewBuilder private func buildRowRail(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: 5) {
            Color.clear.frame(width: 14, height: BuildGeom.loopKeyH)       // align the rail past the loop-key row
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(hue.opacity(0.5))
                    .frame(width: 14, height: cell)
                    .overlay(Text("‹").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7)))
            }
        }
    }

    // ── BRIDGE: the action cluster + the band-target strip ────────────────────────────────────────────────────────
    @ViewBuilder private func buildBridge() -> some View {
        VStack(spacing: 8) {
            buildActionBtn("APPLY TO\nSTAGING", pink: true)
            buildActionBtn("MUTATE")
            Text("→").font(.system(size: 15, weight: .bold)).foregroundColor(buildCyan)
            buildActionBtn("FLATTEN")
            buildActionBtn("COPY\nROWS")
            Text("→").font(.system(size: 15, weight: .bold)).foregroundColor(buildCyan)
            Divider().overlay(buildDim)
            // BAND TARGET strip (5 chips) — arm FLATTEN/COPY then tap a chip; here as placeholders.
            ForEach(["3LAD", "2LAD", "LANE", "LANE", "FREE"], id: \.self) { name in
                Text(name).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                    .frame(maxWidth: .infinity).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(buildCell))
            }
        }
    }

    // ── RIGHT: the PLAY grid with the five fixed bands + the glyph rail ───────────────────────────────────────────
    @ViewBuilder private func buildPlayGrid(cell: CGFloat) -> some View {
        // Band shapes: 3-LADDER (3 rows) · 2-LADDER (2) · LANE (1) · LANE (1) · FREE (1).
        let bands: [(rows: Int, glyph: String, free: Bool)] = [
            (3, "⊻", false), (2, "⊻", false), (1, "≡", false), (1, "≡", false), (1, "▶", true),
        ]
        VStack(alignment: .leading, spacing: 5) {
            buildLabel("PLAY — tap a band to receive")
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: BuildGeom.seam) {                  // the glyph rail
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                        let h = cell * CGFloat(b.rows) + BuildGeom.seam * CGFloat(b.rows - 1)
                        Text(b.glyph).font(.system(size: 10, weight: .bold))
                            .foregroundColor(b.free ? buildPink : buildCyan)
                            .frame(width: BuildGeom.railW, height: h)
                            .overlay(Rectangle().fill(b.free ? buildPink : buildCyan).frame(width: 3), alignment: .leading)
                    }
                }
                VStack(spacing: BuildGeom.seam) {                  // the bands
                    ForEach(Array(bands.enumerated()), id: \.offset) { idx, b in
                        VStack(spacing: 5) {
                            ForEach(0..<b.rows, id: \.self) { r in
                                HStack(spacing: 5) {
                                    ForEach(0..<8, id: \.self) { c in
                                        let hue = buildHues[(idx + r + c) % buildHues.count]
                                        let filled = (c + r + idx) % 3 != 0
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(filled ? hue.opacity(0.6) : buildCell)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text("3-LADDER ⊻ · 2-LADDER ⊻ · LANE · LANE · FREE ▶")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
        }
    }

    // ── BOTTOM: the machinery snake (placeholder — the real flow diagram gets wired in a later increment) ─────────
    @ViewBuilder private func buildMachinery() -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        // §1: in the MACHINE phase (palette owns the voice) the snake's thread comes alive. Skeleton = the thread
        // BRIGHTENS to cyan; the animated door→wire PULSE arrives with the real machinery wiring.
        let thread = palLit ? buildCyan : buildDim
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(hue).frame(width: 44, height: 44)
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
            buildSlot("ARP"); Text("┈").foregroundColor(thread)
            buildSlot("MASK"); Text("┈").foregroundColor(thread)
            buildSlot("MOD"); Text("┈").foregroundColor(thread)
            buildSlot("+", dashed: true)
            Text("┈┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
            buildBox("A: MIDI OUT", "ch1")
            Spacer(minLength: 0)
            buildActionBtn("PLAY THIS\nCELL").frame(width: 96)
            buildActionBtn("RANDOMIZE", pink: true).frame(width: 96)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: BuildGeom.machineH, alignment: .leading)
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
