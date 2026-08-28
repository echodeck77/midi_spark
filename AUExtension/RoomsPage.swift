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
            if roomsMixerOpen { roomsMixerOverlay(size) }   // §1 the strip-controls overlay
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

    // ── THE FOOTER — placeholder MIDI strips (4 IN + 4 OUT). TAP → the strip-controls overlay. ──
    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in footerStrip("IN \(roomsABCD[i])", latch: true) }
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30).padding(.horizontal, 2)
            ForEach(0..<4, id: \.self) { i in footerStrip("OUT \(roomsABCD[i])", latch: false) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))   // tap to expand
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity).background(Color.white.opacity(0.05))
        .contentShape(Rectangle()).onTapGesture { roomsMixerOpen = true }
    }
    private func footerStrip(_ label: String, latch: Bool) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            Text("CH1").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(roomsAccent)
            Circle().fill(Color.green.opacity(0.55)).frame(width: 7, height: 7)
            if latch {
                Text("LATCH").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 4).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.10)))
            }
        }.padding(.horizontal, 8).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }

    // ── THE STRIP-CONTROLS OVERLAY (§1 footer → MIXER). Pops over the grid; tap the dimmed backdrop → recede. ──
    @ViewBuilder func roomsMixerOverlay(_ size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { roomsMixerOpen = false }
            VStack(spacing: 12) {
                HStack {
                    Text("IN / OUT STRIPS").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(roomsAccent)
                    Spacer()
                    Text("tap outside to close").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                    Button { roomsMixerOpen = false } label: { Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.6)).padding(6) }
                }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in mixerStrip("IN \(roomsABCD[i])", isIn: true) }
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1).padding(.horizontal, 4)
                    ForEach(0..<4, id: \.self) { i in mixerStrip("OUT \(roomsABCD[i])", isIn: false) }
                }.frame(maxHeight: .infinity)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.08, green: 0.09, blue: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(roomsAccent.opacity(0.4), lineWidth: 1.5))
            .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 20)
            .contentShape(Rectangle()).onTapGesture { }   // swallow taps inside the panel
        }
    }
    // A placeholder in/out strip control (vertical): label · channel · velocity meter · latch (IN only).
    private func mixerStrip(_ label: String, isIn: Bool) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            Text("CH 1").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(roomsAccent)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.5)).frame(height: 44)   // placeholder velocity level
            }.frame(width: 26).frame(maxHeight: .infinity)
            if isIn {
                Text("LATCH").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 6).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.10)))
            } else {
                Text("OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    // ── THE UNIFORM 9×9 GRID UNIT ──
    @ViewBuilder private func launchUnit(colSelectBottom: Bool, rowSelectLeft: Bool) -> some View {
        let gap: CGFloat = 3
        let selRow = colSelectBottom ? 8 : 0
        let selCol = rowSelectLeft ? 0 : 8
        VStack(spacing: gap) {
            ForEach(0..<9, id: \.self) { r in
                HStack(spacing: gap) { ForEach(0..<9, id: \.self) { c in launchCell9(r, c, selRow: selRow, selCol: selCol) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func launchCell9(_ r: Int, _ c: Int, selRow: Int, selCol: Int) -> some View {
        if r == selRow && c == selCol {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if r == selRow {
            colSelCell(selCol == 0 ? c - 1 : c)
        } else if c == selCol {
            rowSelCell()
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
    private func navPlayDoor() -> some View {   // full-page-width, DOUBLE height (44) — the SELECT/PART header
        Button { roomsRoom = .play } label: {
            HStack(spacing: 6) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 44).background(RoundedRectangle(cornerRadius: 10).fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    private func verticalSeam(_ chevron: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(chevron).font(.system(size: 14, weight: .heavy)).foregroundColor(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Capsule().fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    private func navDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.10)))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func chainPanel() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1.5))
            Text("MIDI CHAIN").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.4))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navW: CGFloat = 40, avail = g.size.width - 16 - navW - 12, gridW = avail * 2 / 3
            VStack(spacing: 6) {
                navPlayDoor()                                             // full-width header (over grid + chain)
                HStack(spacing: 6) {
                    launchUnit(colSelectBottom: false, rowSelectLeft: false).frame(width: gridW)   // grid (2/3, left)
                    chainPanel().frame(width: avail - gridW)              // chain (right)
                    verticalSeam("▸", to: .part).frame(width: navW)       // seam far right → PART
                }
            }.padding(8)
        }
    }
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navW: CGFloat = 40, avail = g.size.width - 16 - navW - 12, gridW = avail * 2 / 3
            VStack(spacing: 6) {
                navPlayDoor()                                             // full-width header (over chain + grid)
                HStack(spacing: 6) {
                    verticalSeam("◂", to: .select).frame(width: navW)     // seam far left → SELECT
                    chainPanel().frame(width: avail - gridW)              // chain (left)
                    launchUnit(colSelectBottom: false, rowSelectLeft: true).frame(width: gridW)     // grid (2/3, right)
                }
            }.padding(8)
        }
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
