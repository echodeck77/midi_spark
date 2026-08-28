import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Framing per Paul 2026-08-28:
//   • GRID + edge SELECT buttons = ONE integrated component. The grid STRETCHES to fill its box (rectangular cells); the
//     column-select row sits TIGHT against the grid (TOP on SELECT/PART, BOTTOM on PLAY); a row-select column on the right.
//   • The ▲PLAY door is as WIDE as the whole grid box, sitting directly on top of it.
//   • SELECT / PART = 2/3 grid + 1/3 MIDI CHAIN (chain RIGHT for SELECT, LEFT for PART). The SELECT↔PART seam is on the FAR
//     side of the chain from the grid.
//   • FOOTER: placeholder MIDI strips (4 IN + 4 OUT — channel · velocity light · latch). Expands to the real strip controls
//     then MIDI config NEXT. RECORD out for now.
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }
    private var roomsABCD: [String] { ["A", "B", "C", "D"] }

    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            roomsMiddle(size).frame(maxWidth: .infinity, maxHeight: .infinity)
            roomsFooter()
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

    // ── THE FOOTER — placeholder MIDI strips (4 IN + 4 OUT). Expands to real strip controls → MIDI config next. ──
    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in footerStrip("IN \(roomsABCD[i])", latch: true) }
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30).padding(.horizontal, 2)
            ForEach(0..<4, id: \.self) { i in footerStrip("OUT \(roomsABCD[i])", latch: false) }
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity).background(Color.white.opacity(0.05))
    }
    private func footerStrip(_ label: String, latch: Bool) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            Text("CH1").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(roomsAccent)   // channel
            Circle().fill(Color.green.opacity(0.55)).frame(width: 7, height: 7)                                    // velocity light
            if latch {
                Text("LATCH").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 4).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.10)))
            }
        }.padding(.horizontal, 8).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }

    // ── THE INTEGRATED GRID UNIT — grid STRETCHES to fill; column-select tight against it ──
    @ViewBuilder private func launchUnit(bottomSelector: Bool) -> some View {
        let gap: CGFloat = 3, rowSelW: CGFloat = 30, selH: CGFloat = 30
        let colSel = HStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { t in colSelCell(t) }
            Color.clear.frame(width: rowSelW)
        }.frame(height: selH)
        VStack(spacing: gap) {
            if !bottomSelector { colSel }
            HStack(spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: gap) { ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(maxWidth: .infinity, maxHeight: .infinity) } }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: gap) { ForEach(0..<8, id: \.self) { _ in rowSelCell() } }.frame(width: rowSelW)
            }.frame(maxHeight: .infinity)
            if bottomSelector { colSel }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func colSelCell(_ t: Int) -> some View {
        let on = t < roomsTrackOn.count && roomsTrackOn[t]
        return RoundedRectangle(cornerRadius: 4).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.11))
            .frame(maxWidth: .infinity)
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .contentShape(Rectangle())
            .onTapGesture { if t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
            .onLongPressGesture(minimumDuration: 0.4) { /* assign — wired when tracks are real */ }
    }
    private func rowSelCell() -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.11)).frame(maxHeight: .infinity)
            .overlay(Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4)))
    }

    // The grid column (SELECT/PART): ▲PLAY as wide as the whole box, directly on top; the grid unit fills the rest.
    @ViewBuilder private func gridColumn() -> some View {
        VStack(spacing: 3) {
            navPlayDoor()                                  // full box width, on top
            launchUnit(bottomSelector: false)              // fills the remaining height
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── NAVIGATION ──
    private func navPlayDoor() -> some View {
        Button { roomsRoom = .play } label: {
            HStack(spacing: 5) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 22).background(Capsule().fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    private func verticalSeam(_ chevron: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(chevron).font(.system(size: 13, weight: .heavy)).foregroundColor(.black)
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
            let navW: CGFloat = 20, avail = g.size.width - 16 - navW - 12, gridW = avail * 2 / 3
            HStack(spacing: 6) {
                gridColumn().frame(width: gridW)                         // grid (2/3, left)
                chainPanel().frame(width: avail - gridW)                 // chain (right of grid)
                verticalSeam("▸", to: .part).frame(width: navW)          // seam on the FAR side (right of chain) → PART
            }.padding(8)
        }
    }
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navW: CGFloat = 20, avail = g.size.width - 16 - navW - 12, gridW = avail * 2 / 3
            HStack(spacing: 6) {
                verticalSeam("◂", to: .select).frame(width: navW)        // seam on the FAR side (left of chain) → SELECT
                chainPanel().frame(width: avail - gridW)                 // chain (left of grid)
                gridColumn().frame(width: gridW)                         // grid (2/3, right)
            }.padding(8)
        }
    }
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part); Spacer() }.padding(.horizontal, 10).padding(.top, 8)
            launchUnit(bottomSelector: true).padding(.horizontal, 10).padding(.bottom, 8)   // full-width grid, column-select BOTTOM
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
