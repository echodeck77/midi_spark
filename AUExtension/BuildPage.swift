import SwiftUI

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-focus-model.md + -build-page-iteration-2.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (iteration 2 — a verb lives at its SOURCE, pointing at its destination):
//   • TWO GRIDS on top — STAGING (the workshop question) beside PLAY (the piece). The old left palette column and the
//     bridge column are GONE, so both grids breathe.
//   • UNDER STAGING — the workshop's own verb strip: [APPLY TO PLAY] · [MUTATE] · [🎲 re-roll].
//   • THE BUILD-SENTENCE BAR (bottom, full width) reads left→right as the signal flows and absorbs the old left column:
//     [● PLAY CELL] · [PART ▾] · [INPUT R1⌨ R2 R3 R4] · [THE CAST] · [chain slots + ghost] · [OUTPUT A B C D] ·
//     [APPLY TO STAGING →]  (play-and-focus first = the lamp's handle, then who/where/what/to-where, final word applies).
//   • THE TARGET DECIDES THE VERB (iteration 2 §2): APPLY TO PLAY arms the play grid (bands pulse) → tap a LANE =
//     FLATTEN · tap a LADDER = COPY ROWS · tap FREE = takes land · long-press a ladder = flatten-into-one-row. So the
//     old FLATTEN/COPY-ROWS buttons + band-target strip DISSOLVE into one gesture.
//
// THE FOCUS LAMP (focus-model §1: the voice is the cursor): the two WORKSHOP zones are the SENTENCE BAR (the machine)
// and STAGING; one owns the voice (lit: full-sat + pink border + ● PLAYING badge / bright snake), the other dims to
// ~60%. The PLAY grid sits OUTSIDE the economy (always calm). ~150ms crossfade when the lamp changes hands.
//
// ┌─ BUILD STATUS ─ INCREMENT 1 (this file): LAYOUT SKELETON — placeholder content, NO engine wiring. Every dimension
// │ is a named constant in `BuildGeom`; each region is its own helper (placement edits are one-liners). NEXT (region
// │ by region): sentence-bar I/O + cast → staging roll (reuse Dice) → rung picking + loop keys → APPLY TO PLAY arming
// │ + the band-decides-verb landings → the real machinery snake (reuse the flow diagram) → the FREE band tap-to-voice.
// │ Deferred here: LITTER (parks for later placement), the animated snake pulse, the real voice behind the lamp.  ────┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners.
private enum BuildGeom {
    static let colGap:   CGFloat = 14       // gap between the staging + play columns
    static let cellMin:  CGFloat = 22       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 50
    static let loopKeyH: CGFloat = 18       // the staging loop-key row height
    static let rowRailW: CGFloat = 14       // the staging left row-selector rail
    static let playRailW: CGFloat = 26      // the play grid's left band-glyph rail
    static let seam:     CGFloat = 3        // the gap between play bands
    static let barH:     CGFloat = 92       // the build-sentence bar height
}

// Placeholder cast hues (mockup palette). Real colours come from the part's cast when the sentence bar is wired.
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

// focus-model §1: which WORKSHOP zone owns the single voice — the machine (the sentence bar) or staging.
enum BuildFocus { case machine, staging }

extension DiagView {
    // The lamp: is each workshop zone lit (owns the voice) or dimmed (~60%, touchable)?
    fileprivate var machineLit: Bool { buildFocus == .machine }
    fileprivate var stgLit: Bool { buildFocus == .staging }
    // GRAB the voice (focus-model §2). ● PLAY CELL / cast selects pull it to the machine; staging column keys + the ●
    // badge pull it to staging. ~150ms crossfade teaches.
    fileprivate func buildGrabStaging() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .staging } }
    fileprivate func buildGrabMachine() { withAnimation(.easeInOut(duration: 0.15)) { buildFocus = .machine } }
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

    // ── LANDSCAPE: the two grids share the full width, the build-sentence bar spans below ──────────────────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        // one cell size fits BOTH 8×8 grids + the staging row rail + the play glyph rail inside the width.
        let budget = size.width - BuildGeom.rowRailW - BuildGeom.playRailW - BuildGeom.colGap - 34
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, budget / 16))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                buildStagingColumn(cell: cell)
                    .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                    .animation(.easeInOut(duration: 0.15), value: buildFocus)
                buildPlayColumn(cell: cell)                         // PLAY sits OUTSIDE the focus economy (always calm)
            }
            buildSentenceBar()
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → stack (staging → play → sentence bar) ───────────────────────────────────────
    @ViewBuilder private func buildPortrait(_ size: CGSize) -> some View {
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (size.width - BuildGeom.rowRailW - 24) / 8))
        VStack(spacing: 12) {
            buildStagingColumn(cell: cell)
                .opacity(stgLit ? 1 : 0.6).overlay(buildFocusBorder(stgLit))
                .animation(.easeInOut(duration: 0.15), value: buildFocus)
            buildPlayColumn(cell: cell)
            buildSentenceBar()
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── STAGING column: header+badge · rail+loopkeys+grid · the workshop verb strip · simple→complex label ─────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {                                    // header — the ● badge appears when staging owns the voice, and is a GRAB
                buildLabel("STAGING")
                if stgLit { buildPlayingBadge() }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle()).onTapGesture { buildGrabStaging() }
            HStack(alignment: .top, spacing: 5) {
                buildRowRail(cell: cell, hue: hue)                 // §3: the row-selector rail on staging's LEFT edge
                VStack(spacing: 5) {
                    HStack(spacing: 5) {                           // the loop-key row — a tap GRABS the voice onto staging (§2)
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
            // §4 the workshop's OWN verb strip, under its own grid.
            HStack(spacing: 6) {
                buildActionBtn("APPLY TO PLAY", pink: true)        // STAGING's verb → arms the play grid; the band decides FLATTEN|COPY ROWS
                buildActionBtn("MUTATE")
                buildActionBtn("🎲").frame(width: 48)              // re-roll the staging ladder
            }
            Text("SIMPLE ▲ · rows = variations · ▼ COMPLEX  ·  APPLY TO PLAY → tap LANE=flatten · LADDER=copy rows · FREE=takes")
                .font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)
        }
    }

    // §3 the ROW-SELECTOR RAIL — one bar per staging row on the LEFT edge; tinted the selected hue, chevron into the
    // grid. With a cast colour selected, tapping a row fills it (3-press cycle; exact cycle = Paul's device call).
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

    // ── PLAY column: the piece, five fixed bands + glyph rail; arms to receive when APPLY TO PLAY is pressed ────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        let bands: [(rows: Int, glyph: String, free: Bool)] = [
            (3, "⊻", false), (2, "⊻", false), (1, "≡", false), (1, "≡", false), (1, "▶", true),
        ]
        VStack(alignment: .leading, spacing: 6) {
            buildLabel("PLAY — tap a band to receive")
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

    // ── THE BUILD-SENTENCE BAR (bottom, full width): the complete build sentence, absorbing the old left column ────
    // Reads left→right as the signal flows. Horizontally scrollable so it never overflows a narrow window.
    @ViewBuilder private func buildSentenceBar() -> some View {
        let hue = buildSelColour < buildHues.count ? buildHues[buildSelColour] : buildHues[0]
        let thread = machineLit ? buildCyan : buildDim            // §1: the snake's thread comes alive in the MACHINE phase (skeleton = brighten; the animated pulse arrives with wiring)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                buildActionBtn("● PLAY\nCELL", pink: machineLit).frame(width: 70)   // play-and-focus first — the lamp's handle
                buildDivider()
                buildPartChip()
                buildInputGroup(hue: hue)
                buildDivider()
                buildCastStrip()                                  // THE CAST — the part's swatches, compact
                buildDivider()
                buildChainSlots(hue: hue, thread: thread)         // the chain slots + ghost
                buildDivider()
                buildOutputGroup()
                buildDivider()
                buildActionBtn("APPLY TO\nSTAGING →", pink: true).frame(width: 92)  // §1: the machine's verb — the sentence's final word, arrow at staging
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, minHeight: BuildGeom.barH, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .opacity(machineLit ? 1 : 0.6).overlay(buildFocusBorder(machineLit))
        .contentShape(Rectangle()).onTapGesture { buildGrabMachine() }   // building the machine pulls the lamp here
        .animation(.easeInOut(duration: 0.15), value: buildFocus)
    }

    @ViewBuilder private func buildPartChip() -> some View {
        Text("PART 1 ▾").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
    }
    @ViewBuilder private func buildInputGroup(hue: Color) -> some View {
        HStack(spacing: 4) {
            Text("IN").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            buildIOChip("R1 ⌨", on: true, keys: true)
            buildIOChip("R2"); buildIOChip("R3"); buildIOChip("R4")
        }
    }
    @ViewBuilder private func buildOutputGroup() -> some View {
        HStack(spacing: 4) {
            Text("OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            buildIOChip("A", on: true); buildIOChip("B"); buildIOChip("C"); buildIOChip("D")
        }
    }
    @ViewBuilder private func buildCastStrip() -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let hue = i < buildHues.count ? buildHues[i] : buildCell
                RoundedRectangle(cornerRadius: 6).fill(hue).frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3])).opacity(i == buildSelColour ? 1 : 0))
                    .onTapGesture { buildSelColour = i; buildGrabMachine() }   // selecting a cast colour is a workbench act — lamp to the machine
            }
        }
    }
    @ViewBuilder private func buildChainSlots(hue: Color, thread: Color) -> some View {
        HStack(spacing: 6) {
            Text("┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
            buildSlot("ARP"); Text("┈").foregroundColor(thread)
            buildSlot("MASK"); Text("┈").foregroundColor(thread)
            buildSlot("MOD"); Text("┈").foregroundColor(thread)
            buildSlot("+", dashed: true)
            Text("┈▶").foregroundColor(thread).font(.system(size: 10, design: .monospaced))
        }
    }
    @ViewBuilder private func buildDivider() -> some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 44)
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func buildLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(buildPink).tracking(1)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan, lineWidth: keys && !on ? 1 : 0))
    }
    @ViewBuilder private func buildActionBtn(_ s: String, pink: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
            .foregroundColor(pink ? Color.black : Color.white).tracking(0.5)
            .frame(maxWidth: .infinity).frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(pink ? buildPink : buildCell))
    }
    @ViewBuilder private func buildSlot(_ s: String, dashed: Bool = false) -> some View {
        Text(s).font(.system(size: 8, design: .monospaced)).foregroundColor(dashed ? buildDim : .white)
            .frame(width: 44, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(dashed ? Color.clear : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(dashed ? buildDim : Color(white: 0.15),
                                                              style: StrokeStyle(lineWidth: dashed ? 1.3 : 1, dash: dashed ? [4] : [])))
    }
}
