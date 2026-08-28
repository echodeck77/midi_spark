import SwiftUI

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

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }
    private var roomsABCD: [String] { ["A", "B", "C", "D"] }

    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 0) {
                roomsMiddle(size).frame(maxWidth: .infinity, maxHeight: .infinity)
                roomsFooter()
            }
            if roomsMixerOpen { roomsMixerOverlay(size) }   // §1 the strip-controls overlay (two-stage: strips → full config)
            roomsProcessorPicker(size: size)                // empty chain-box → the processor selector window
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder private func roomsMiddle(_ size: CGSize) -> some View {
        switch roomsRoom {
        case .select: roomsSelect(size)
        case .part:   roomsPart(size)
        case .play:   roomsPlay(size)
        case .reel:   roomsReel(size)
        }
    }

    // ── THE FOOTER — the 4 IN (receiver) + 4 OUT (emitter) MIDI strips, reflecting the REAL settings (channel · latch
    // mode) with a live activity indicator that flashes by velocity + density. TAP → the strip-controls overlay. ──
    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in footerStrip(i, isIn: true) }
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30).padding(.horizontal, 2)
            ForEach(0..<4, id: \.self) { i in footerStrip(i, isIn: false) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))   // tap to expand
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity).background(Color.white.opacity(0.05))
        .contentShape(Rectangle()).onTapGesture { roomsMixerOpen = true }
    }
    private func footerStrip(_ i: Int, isIn: Bool) -> some View {
        let door = (isIn && i < receivers.count) ? receivers[i].doorModeResolved : .thru
        let latched = isIn && door != .thru                                   // some capture/latch mode is set on this door
        return HStack(spacing: 5) {
            Text((isIn ? "IN " : "OUT ") + roomsABCD[i]).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            Text(footerChannel(i, isIn: isIn)).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(roomsAccent)
            roomsMidiIndicator(i, isIn: isIn)                                 // flashes by velocity + density (real feed)
            if isIn {
                Text(door == .thru ? "LATCH" : door.rawValue.uppercased()).font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(latched ? .black : .white.opacity(0.5))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(latched ? roomsAccent.opacity(0.8) : Color.white.opacity(0.10)))
            }
        }.padding(.horizontal, 8).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }
    // The real channel label — IN: the receiver's channel mask (OMNI / CH n / CH ×k / OFF); OUT: the emitter's stamp channel.
    private func footerChannel(_ i: Int, isIn: Bool) -> String {
        if isIn {
            guard i < receivers.count else { return "OMNI" }
            let mask = receivers[i].channelMaskResolved
            if mask == 0xFFFF { return "OMNI" }
            if mask == 0 { return "OFF" }
            let n = (0..<16).filter { mask & (UInt16(1) << UInt16($0)) != 0 }
            return n.count == 1 ? "CH\(n[0] + 1)" : "CH×\(n.count)"
        } else {
            let chans = au?.uiBusChannels() ?? []
            return "CH\(i < chans.count ? chans[i] : i + 1)"
        }
    }
    // THE MIDI ACTIVITY INDICATOR — flashes by VELOCITY (bright = high vel, dim = low) AND DENSITY (more held notes =
    // brighter). IN reads recvHeld[i] (held velocities → count = density) + meters.receiverPeak (attack flash); OUT reads
    // meters.emitPeak (velocity only — no per-emitter held count). (Paul 2026-08-28)
    private func roomsMidiIndicator(_ i: Int, isIn: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            let held: Double = isIn && i < recvHeld.count ? (recvHeld[i].max() ?? 0) : 0
            let count = isIn && i < recvHeld.count ? recvHeld[i].count : 0
            let peak = isIn ? (i < meters.receiverPeak.count ? meters.receiverPeak[i] : 0) : (i < meters.emitPeak.count ? meters.emitPeak[i] : 0)
            let peakAt = isIn ? (i < meters.receiverPeakAt.count ? meters.receiverPeakAt[i] : .distantPast) : (i < meters.emitPeakAt.count ? meters.emitPeakAt[i] : .distantPast)
            let flash = peak * max(0, 1 - tl.date.timeIntervalSince(peakAt) / 0.3)   // brief attack flash on note-on
            let vel = max(0, min(1, max(held, flash)))                               // velocity 0…1
            let dens = min(1.0, Double(count) / 6.0)                                 // density 0…1 (IN only)
            let bright = min(1.0, vel * (0.65 + 0.5 * dens))                         // brightness ∝ velocity AND density
            Circle().fill(Color.green.opacity(0.12 + 0.88 * bright))
                .frame(width: 8, height: 8)
                .shadow(color: Color.green.opacity(bright * 0.9), radius: 4 * bright)   // a glow that grows with the flash
        }
    }

    // ── THE MIXER SLIDEOVER (§1 footer → MIXER) — the REAL MIDI-IN / MIDI-OUT console strips reused from the old UI
    // (buildReceiverControl / buildEmitterControl). A bottom slideover, HALF the canvas height; tap the dim backdrop
    // above it → recede. (Paul 2026-08-28) ──
    // TWO-STAGE MIXER (Paul 2026-08-28): STAGE 1 = the strip row (bottom band). Tapping a SPANNER → STAGE 2 = full page,
    // the same strips (selected highlighted, others act as tabs) + the selected control's MIDI config restyled below.
    @ViewBuilder func roomsMixerOverlay(_ size: CGSize) -> some View {
        let expanded = roomsMixerSel != nil
        ZStack(alignment: .bottom) {
            Color.black.opacity(expanded ? 0.6 : 0.4).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { roomsMixerOpen = false; roomsMixerSel = nil }
            VStack(spacing: 10) {
                HStack {
                    Text(expanded ? "MIDI SETTINGS" : "MIDI IN / OUT").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(roomsAccent)
                    Spacer()
                    if expanded {   // collapse back to the strip row (stage 1)
                        Button { roomsMixerSel = nil } label: { Image(systemName: "chevron.compact.down").font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(0.6)).padding(.horizontal, 8) }
                    }
                    Button { roomsMixerOpen = false; roomsMixerSel = nil } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.5)).padding(6) }
                }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in mixerStrip(i, isIn: true) }
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1).padding(.horizontal, 2)
                    ForEach(0..<4, id: \.self) { i in mixerStrip(i, isIn: false) }
                }
                if let k = roomsMixerSel {   // STAGE 2 — the selected control's config, restyled inline, fills the rest
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    ScrollView(.vertical, showsIndicators: false) { roomsMixerConfig(k).padding(.top, 4) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(16)
            .frame(width: size.width)
            .frame(height: expanded ? size.height : nil, alignment: .top)   // STAGE 2 = full page; STAGE 1 = content (the strip band)
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
            .overlay(alignment: .top) { Rectangle().fill(roomsAccent.opacity(0.4)).frame(height: 2) }
            .contentShape(Rectangle()).onTapGesture { }                 // swallow taps inside the panel
        }
    }
    // One mixer strip = the REAL console control + a SPANNER tool button below it. STAGE 1: spanner → expand to stage 2
    // selecting this control. STAGE 2: spanner → switch the selected control (its config shows below); the selected
    // control's spanner is highlighted (the "tab"). (Paul 2026-08-28)
    private func mixerStrip(_ i: Int, isIn: Bool) -> some View {
        let k = isIn ? i : 4 + i
        let selected = roomsMixerSel == k
        return VStack(spacing: 6) {
            if isIn { roomsMixerReceiver(i) } else { roomsMixerEmitter(i) }
            Button { roomsMixerSel = k } label: {
                Image(systemName: "wrench.and.screwdriver").font(.system(size: 13, weight: .bold)).foregroundColor(selected ? .black : roomsAccent)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? roomsAccent : Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(roomsAccent.opacity(selected ? 0 : 0.3), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .overlay(selected ? RoundedRectangle(cornerRadius: 8).stroke(roomsAccent, lineWidth: 2).padding(-3) : nil)   // highlight the selected tab
    }

    // ── THE UNIFORM 9×9 GRID UNIT ──
    @ViewBuilder private func launchUnit(colSelectBottom: Bool, rowSelectLeft: Bool, libraryGrid: Bool = false) -> some View {
        let gap: CGFloat = 3
        let selRow = colSelectBottom ? 8 : 0
        let selCol = rowSelectLeft ? 0 : 8
        VStack(spacing: gap) {
            ForEach(0..<9, id: \.self) { r in
                HStack(spacing: gap) { ForEach(0..<9, id: \.self) { c in launchCell9(r, c, selRow: selRow, selCol: selCol, libraryGrid: libraryGrid) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func launchCell9(_ r: Int, _ c: Int, selRow: Int, selCol: Int, libraryGrid: Bool) -> some View {
        let gridRow = r > selRow ? r - 1 : r
        let gridCol = c > selCol ? c - 1 : c
        if r == selRow && c == selCol {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if r == selRow {
            colSelCell(selCol == 0 ? c - 1 : c)
        } else if c == selCol {
            // THE SIDE BUTTONS = part slots that hold chains — the §4 shared exclusive column (SELECT audition source). (Paul 2026-08-28)
            if libraryGrid { roomsSideButton(gridRow).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { rowSelCell() }
        } else if libraryGrid {
            // THE SELECT GRID = the LIBRARY-backed chain browser — each interior cell is a real chain face (§6 reuse).
            roomsSelectGridCell(gridRow * 8 + gridCol).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func colSelCell(_ t: Int) -> some View {
        let on = t >= 0 && t < roomsTrackOn.count && roomsTrackOn[t]
        return RoundedRectangle(cornerRadius: 4).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.11))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .contentShape(Rectangle())
            .onTapGesture { if t >= 0 && t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
            .onLongPressGesture(minimumDuration: 0.4) { /* assign — wired when tracks are real */ }
    }
    private func rowSelCell() -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.11)).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4)))
    }

    // ── NAVIGATION ──
    // (The ▲PLAY and part↔select nav are now SLIVERS inside the grid box — roomsPlayNavSliver / roomsSeamSliver in
    // BuildPage. The PLAY grid still uses the capsule navDoor below. Paul 2026-08-28.)
    private func navDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.10)))
        }.buttonStyle(.plain)
    }
    // THE MIDI CHAIN panel — the REAL machine strip (play button · receiver toggles · chain + side buttons · emitter
    // toggles) reused verbatim from the old BUILD left column via buildPage's internal roomsMachineStrip. (Paul 2026-08-28)
    @ViewBuilder private func chainPanel(_ room: Room) -> some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                roomsMachineStrip(width: g.size.width, room: room).padding(.top, 2)
            }
        }
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        GeometryReader { g in
            let avail = g.size.width - 16 - 12                             // page padding (16) + 2 HStack gaps (12)
            let gridW = avail * 2 / 3
            let seamW = roomsGridCellW(gridW, cols: 9) * 0.5              // 50% of a grid cell — matches the old in-grid seam
            let chainW = avail - gridW - seamW
            HStack(spacing: 6) {
                roomsSelectGridUnit().frame(width: gridW)                  // the GRID + its edge selectors (2/3, left)
                VStack(spacing: 6) {                                       // CHAIN SECTION — the PLAY header + the machine (1/3, middle)
                    roomsPlayHeader(.select)
                    chainPanel(.select)
                }.frame(width: chainW)
                roomsSeamColumn(to: .part, chevron: "▸").frame(width: seamW)   // the SEAM → PART, FAR RIGHT (opposite the chain)
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
            HStack(spacing: 6) {
                roomsSeamColumn(to: .select, chevron: "◂").frame(width: seamW)   // the SEAM → SELECT, FAR LEFT (opposite the chain)
                VStack(spacing: 6) {                                       // CHAIN SECTION — the PLAY header + the machine (1/3, middle)
                    roomsPlayHeader(.part)
                    chainPanel(.part)
                }.frame(width: chainW)
                roomsPartGrid().frame(width: gridW)                        // the GRID + its edge selectors (2/3, right)
            }.padding(8)
        }
        .onAppear { roomsPartSetup() }                                    // source the MIDI from the part grid + refresh the side-button faces
    }
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part); Spacer() }.padding(.horizontal, 10).padding(.top, 8)
            launchUnit(colSelectBottom: true, rowSelectLeft: false).padding(.horizontal, 10).padding(.bottom, 8)
        }
    }
    @ViewBuilder private func roomsReel(_ size: CGSize) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { navDoor("◂ PLAY", to: .play); Spacer() }.padding(.horizontal, 12).padding(.top, 8)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
                VStack(spacing: 8) {
                    Text("REEL").font(.system(size: 30, weight: .black, design: .monospaced)).foregroundColor(roomsAccent)
                    Text("the tape — recorded passes  ·  housed next").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}
