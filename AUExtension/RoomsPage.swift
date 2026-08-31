import SwiftUI

// THE ROOM LATTICE (design ferry INSTRUCTIONS-layout-lattice, 2026-08-29) — the ONE source of truth for the grid's
// vertical bands, computed once per room from the shared column height and threaded to the grid, the seam, and the
// left panel so all three rhyme (kills the duplicated gap/nf/pad/(9+nf) literals). Height-derived only; each view
// still computes its own cell WIDTH. gap 3 · pad 3 · nf 0.5 (the ▲PLAY door bar = 50% of a cell). Rows top→bottom:
// ▲PLAY door (navH) · header row (ch) · 8 interior rows (ch each).
struct RoomsMetrics {
    static let gap: CGFloat = 3
    static let pad: CGFloat = 3
    let ch: CGFloat            // one grid row height
    let navH: CGFloat          // the ▲PLAY door-bar band height (= ch·0.5)
    let interiorTop: CGFloat   // y where the 8 interior rows begin (below the ▲PLAY door + header row)
    let interiorH: CGFloat     // total height of the 8 interior rows
    init(height: CGFloat) {
        // Delegate to the pure, unit-tested lattice (Derivations.roomsLattice) — one source of truth for the geometry.
        let g = roomsLattice(height: Double(height), gap: Double(RoomsMetrics.gap), pad: Double(RoomsMetrics.pad))
        ch = CGFloat(g.ch); navH = CGFloat(g.navH); interiorTop = CGFloat(g.interiorTop); interiorH = CGFloat(g.interiorH)
    }
}

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Framing per Paul 2026-08-28:
//   • GRID + edge buttons = ONE uniform 9×9 component (every cell the same size, filling the box). Column-select TOP on
//     SELECT/PART / BOTTOM on PLAY. Row-select column RIGHT on SELECT, LEFT on PART.
//   • ▲PLAY = a full-page-WIDTH, DOUBLE-HEIGHT header on SELECT/PART (sits over the grid AND the chain).
//   • SELECT / PART = 2/3 grid + 1/3 MIDI CHAIN (chain RIGHT for SELECT, LEFT for PART). SELECT↔PART seam on the FAR side.
//   • FOOTER = placeholder MIDI strips (4 IN + 4 OUT). TAP the footer → the in/out STRIP-CONTROLS overlay pops over the grid;
//     TAP OUTSIDE → it recedes. (Real strip controls + MIDI config reuse comes next.)
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    // §8b: the footer/mixer are PLUMBING — room-neutral (only door affordances tint). So the footer's accent is a
    // neutral light grey now (was cyan). The per-strip mixer hues (green/blue/red/purple) stay their own identity.
    private var roomsAccent: Color { Color(white: 0.62) }

    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        roomsChrome {                                       // .fileImporter · the IO-hold banner · scene-switch (Paul 2026-08-30, old-UI removal)
            ZStack {
                VStack(spacing: 0) {
                    roomsMiddle(size).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if roomsMixerOpen { roomsMixerOverlay(size) }   // §1 the strip-controls overlay (two-stage: strips → full config)
                roomsProcessorPicker(size: size)                // empty chain-box → the processor selector window
                roomsSharedOverlays(size)                       // the config sheets · stage-eye · reel · ROW 8 (were dead in rooms until now)
            }.frame(width: size.width, height: size.height, alignment: .top)
        }
    }

    @ViewBuilder private func roomsMiddle(_ size: CGSize) -> some View {
        ZStack {
            roomsField(roomsRoom).ignoresSafeArea()                        // §8b: charcoal floor everywhere; PLAY = the near-black stage
            switch roomsRoom {
            case .select: roomsSelect(size)
            case .part:   roomsPart(size)
            case .play:   roomsPlay(size)
            case .reel:   roomsReel(size)
            }
        }
    }

    // ── THE MIXER — the REAL MIDI-IN / MIDI-OUT console strips reused from the old UI (buildReceiverControl /
    // buildEmitterControl). ENTRY: the machine-column strip SPANNERS (a receiver → this door selected, an emitter → this
    // OUT selected) open it EXPANDED (stage 2) on the tapped strip. The old extend-page FOOTER that used to open it is
    // retired (Paul 2026-08-31). Tap the dim backdrop → recede. ──
    // TWO-STAGE MIXER (Paul 2026-08-28): STAGE 1 = the strip row (bottom band, reached by collapsing from stage 2). A
    // SPANNER opens STAGE 2 = full page, all 8 strips (the selected highlighted, the others act as tabs) + the selected
    // control's MIDI config restyled below.
    @ViewBuilder func roomsMixerOverlay(_ size: CGSize) -> some View {
        let expanded = roomsMixerSel != nil
        let bandH = min(size.height * 0.5, 262)                          // STAGE 1 = a bottom BAND that fits the console strips (NOT full page)
        ZStack(alignment: .bottom) {
            Color.black.opacity(expanded ? 0.6 : 0.4).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { roomsMixerOpen = false; roomsMixerSel = nil }
            VStack(spacing: 10) {
                HStack(spacing: 6) {                                     // group labels: MIDI IN over the receivers · MIDI OUT over the emitters (both stages, Paul 2026-08-28)
                    Text("MIDI IN").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(roomsAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text("MIDI OUT").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(roomsAccent)
                        Spacer(minLength: 0)
                        if expanded {   // collapse back to the strip band (stage 1)
                            Button { roomsMixerSel = nil } label: { Image(systemName: "chevron.compact.down").font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(0.6)).padding(.horizontal, 8) }
                        }
                        Button { roomsMixerOpen = false; roomsMixerSel = nil } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.5)).padding(6) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 6) {                    // the 8 strips, no IN/OUT divider (Paul 2026-08-28)
                    ForEach(0..<4, id: \.self) { i in mixerStrip(i, isIn: true, expanded: expanded) }
                    ForEach(0..<4, id: \.self) { i in mixerStrip(i, isIn: false, expanded: expanded) }
                }
                if let k = roomsMixerSel {   // STAGE 2 — the selected control's config, restyled inline, fills the rest (the per-control label is dropped — the highlighted strip identifies it, Paul 2026-08-28)
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    ScrollView(.vertical, showsIndicators: false) { roomsMixerConfig(k).padding(.top, 4) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(16)
            .frame(width: size.width, height: expanded ? size.height : bandH, alignment: .top)   // STAGE 2 full; STAGE 1 the band
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
            .overlay(alignment: .top) { Rectangle().fill(roomsAccent.opacity(0.4)).frame(height: 2) }
            .contentShape(Rectangle()).onTapGesture { }                 // swallow taps inside the panel
        }
    }
    // The hue of a mixer control (IN A–D use the door hues; OUT uses the accent) — shared by the selected strip's
    // highlight AND the config header, so the two clearly read as the SAME control. (Paul 2026-08-28)
    private func roomsMixerHue(_ k: Int) -> Color {
        k < 4 ? [Color(red: 0.36, green: 0.92, blue: 0.52), Color(red: 0.29, green: 0.49, blue: 1.0), Color(red: 0.91, green: 0.36, blue: 0.44), Color(red: 0.69, green: 0.42, blue: 0.91)][k] : roomsAccent
    }
    // One mixer strip = the REAL console control + a SPANNER tab button below it. STAGE 1: spanner → expand to stage 2
    // selecting this control. STAGE 2: spanner → switch the selected control; the selected strip is HIGHLIGHTED in its
    // hue and the others DIM, so it clearly matches the form below. (Paul 2026-08-28)
    private func mixerStrip(_ i: Int, isIn: Bool, expanded: Bool) -> some View {
        let k = isIn ? i : 4 + i
        let selected = roomsMixerSel == k
        let hue = roomsMixerHue(k)
        return VStack(spacing: 6) {
            if isIn { roomsMixerReceiver(i) } else { roomsMixerEmitter(i) }
            Button { roomsMixerSel = k } label: {
                Image(systemName: "wrench.and.screwdriver").font(.system(size: 13, weight: .bold)).foregroundColor(selected ? .black : hue)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? hue : Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(hue.opacity(selected ? 0 : 0.35), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(selected ? RoundedRectangle(cornerRadius: 8).fill(hue.opacity(0.14)) : nil)   // the selected strip wears its hue …
        .overlay(selected ? RoundedRectangle(cornerRadius: 8).stroke(hue, lineWidth: 2) : nil)     // … + a hue border
        .opacity(expanded && !selected ? 0.4 : 1)                                                  // non-selected DIM in stage 2 (the tabs recede)
    }

    // (The old uniform 9×9 launchUnit/launchCell9/colSelCell/rowSelCell were the PLACEHOLDER play grid — retired
    // 2026-08-29 when the PLAY room became a real 2/3-width grid, roomsPlayGrid in BuildPage. See roomsPlay below.)

    // ── NAVIGATION ──
    // (The ▲PLAY and part↔select nav are now SLIVERS inside the grid box — roomsPlayNavSliver / roomsSeamSliver in
    // BuildPage. The PLAY grid still uses the capsule navDoor below. Paul 2026-08-28.)
    private func navDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(roomsDoorInk(to: room))
                .padding(.horizontal, 12).frame(height: 22)
                .background(roomsDoorBar(to: room, corner: 11))            // §8b: the door wears its DESTINATION's signature
        }.buttonStyle(.plain)
    }
    // THE MIDI CHAIN panel — the REAL machine strip (play button · receiver toggles · chain + side buttons · emitter
    // toggles) reused verbatim from the old BUILD left column via buildPage's internal roomsMachineStrip. (Paul 2026-08-28)
    @ViewBuilder private func chainPanel(_ room: Room, _ m: RoomsMetrics) -> some View {
        GeometryReader { g in
            // THREE SECTIONS (Paul 2026-08-30, footer-retirement stage 1): the RECEIVER strip on top · the MACHINE (as it is)
            // in the middle · the EMITTER strip at the bottom. The machine takes a REDUCED metric so it fits between the strips
            // (it no longer rhymes with the grid rows — an accepted trade for the console-on-the-column layout).
            let stripH = 2 * m.ch + RoomsMetrics.gap                         // the strips are exactly TWO GRID CELLS tall (Paul 2026-08-30)
            let mid = max(150, g.size.height - 2 * stripH - 12)
            VStack(spacing: 6) {
                roomsColumnReceivers(height: stripH).frame(height: stripH)    // TOP — the 4 MIDI IN controls
                roomsMachineStrip(width: g.size.width, room: room, m: RoomsMetrics(height: mid)).frame(height: mid)   // MIDDLE — the machine, unchanged
                roomsColumnEmitters(height: stripH).frame(height: stripH)     // BOTTOM — the 4 MIDI OUT controls
            }
        }
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        GeometryReader { g in
            let avail = g.size.width - 16 - 12                             // page padding (16) + 2 HStack gaps (12)
            let gridW = avail * 2 / 3
            let seamW = roomsGridCellW(gridW, cols: 10) * 0.5             // 50% of a grid cell (SELECT is now 10 cols: left page rail + 8 + right side)
            let chainW = avail - gridW - seamW
            let m = RoomsMetrics(height: g.size.height - 16)              // the ONE lattice for this room (HStack content height = page − padding 8·2)
            HStack(spacing: 6) {
                roomsSelectGridUnit(m: m).frame(width: gridW)             // the GRID + its edge selectors (2/3, left)
                chainPanel(.select, m).frame(width: chainW)               // the MACHINE box — its bands rhyme with the grid (1/3, middle)
                roomsSeamColumn(to: .part, chevron: "▸", m: m).frame(width: seamW)   // the SEAM → PART, FAR RIGHT (opposite the chain)
            }.padding(8)
        }
        .onAppear { roomsSelectSetup() }                                  // open the library-backed grid selector on SELECT (idempotent)
    }
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        GeometryReader { g in
            let avail = g.size.width - 16 - 12
            let gridW = avail * 2 / 3
            let seamW = roomsGridCellW(gridW, cols: 10) * 0.5
            let chainW = avail - gridW - seamW
            let m = RoomsMetrics(height: g.size.height - 16)              // the ONE lattice for this room
            HStack(spacing: 6) {
                roomsSeamColumn(to: .select, chevron: "◂", m: m).frame(width: seamW)   // the SEAM → SELECT, FAR LEFT (opposite the chain)
                chainPanel(.part, m).frame(width: chainW)                  // the MACHINE box — its bands rhyme with the grid (1/3, middle)
                roomsPartGrid(m: m).frame(width: gridW)                    // the GRID + its edge selectors (2/3, right)
            }.padding(8)
        }
        .onAppear { roomsPartSetup() }                                    // source the MIDI from the part grid + refresh the side-button faces
    }
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navH: CGFloat = 30
            let avail = g.size.width - 16 - 6                              // page padding (16) + 1 HStack gap (6)
            let gridW = avail * 2 / 3                                      // THE GRID = 2/3 of the width (Paul 2026-08-29)
            let chainW = avail - gridW                                     // the remaining 1/3 (reserved)
            let bodyH = g.size.height - 16 - navH - 6                      // content height below the nav bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part)
                    Spacer()
                    roomsPlayStartStop().frame(width: max(120, gridW * 0.4))   // START/STOP the play grid (Paul 2026-08-29)
                }.frame(height: navH)
                HStack(spacing: 6) {
                    roomsPlayGrid().frame(width: gridW, height: bodyH)     // the clean 8×8 (rung-per-column + per-column transport on the bottom row)
                    Color.clear.frame(width: chainW, height: bodyH)       // the remaining 1/3 is RESERVED (Paul 2026-08-29 — no I/O toggles; ferried cells carry their own I/O)
                }
            }.padding(8)
        }
        // The PLAY room owns NO extra shared voice — only the persistent play layer sounds here. Gating it OFF on appear (the
        // sibling of roomsSelect/roomsPart's .onAppear) stops a SELECT/PART audition from leaking onto the play page (Paul 2026-08-31).
        .onAppear { roomsSyncVoice(.play) }
        // (buildPlaySel inits to ROW 1 for every column — no per-appear seed needed; a user deselect then persists.)
    }
    @ViewBuilder private func roomsReel(_ size: CGSize) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { navDoor("◂ PLAY", to: .play); Spacer() }.padding(.horizontal, 12).padding(.top, 8)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsRedSig.opacity(0.5), lineWidth: 1.5))   // §8b REEL = RED signature
                VStack(spacing: 8) {
                    Text("REEL").font(.system(size: 30, weight: .black, design: .monospaced)).foregroundColor(roomsRedSig)
                    Text("the tape — recorded passes  ·  housed next").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}
