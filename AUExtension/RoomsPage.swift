import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Framing per Paul 2026-08-28:
//   • GRID + edge SELECT buttons = ONE integrated component with SQUARE cells (real Launchpad geometry) — the column-select
//     row sits TIGHT against the grid (fixed cell size, not fill-stretched). Column-select TOP on SELECT/PART, BOTTOM on PLAY;
//     a row-select column on the right.
//   • The ▲PLAY door sits DIRECTLY ON TOP of the column-select cells.
//   • SELECT / PART = 2/3 grid + 1/3 MIDI CHAIN. Chain on the RIGHT for SELECT, LEFT for PART. The SELECT↔PART seam nav is
//     on the OPPOSITE side of the chain FROM the grid — so [grid | chain | seam→PART] on SELECT, [seam→SELECT | chain | grid]
//     on PART. Thin vertical, matching the ▲PLAY accent.
//   • Placeholder grid/chain (framing first). Persistent footer below (mixer/config next). RECORD out for now.
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }

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

    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 8) {
            Text("FOOTER").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.45))
            Text("›  MIXER  ›  CONFIG").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.28))
            Spacer(); Text("built next").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.22))
        }.padding(.horizontal, 14).padding(.vertical, 9).background(Color.white.opacity(0.04))
    }

    // ── SQUARE-CELL LAUNCH GEOMETRY ───────────────────────────────────────────────────────────────
    // 9 columns (8 grid + 1 row-select) × 9 rows (8 grid + 1 column-select). Fit the square cell to the box, reserving
    // `playDoor` height on top for SELECT/PART's ▲PLAY button.
    private func launchCell(_ box: CGSize, playDoor: CGFloat) -> CGFloat {
        let gap: CGFloat = 3, pad: CGFloat = 6
        let cw = (box.width  - 2 * pad - 8 * gap) / 9
        let ch = (box.height - 2 * pad - playDoor - 8 * gap) / 9
        return max(12, min(cw, ch))
    }
    private func colSelCell(_ t: Int) -> some View {
        let on = t < roomsTrackOn.count && roomsTrackOn[t]
        return RoundedRectangle(cornerRadius: 4).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.11))
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .contentShape(Rectangle())
            .onTapGesture { if t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
            .onLongPressGesture(minimumDuration: 0.4) { /* assign — wired when tracks are real */ }
    }
    private func gridCellPH() -> some View { RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)) }
    private func rowSelCell() -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.11))
            .overlay(Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4)))
    }
    // The integrated unit at a fixed square `cell` — column-select tight against the grid.
    @ViewBuilder private func launchUnit(cell: CGFloat, bottomSelector: Bool) -> some View {
        let gap: CGFloat = 3
        let colSel = HStack(spacing: gap) {
            ForEach(0..<8, id: \.self) { t in colSelCell(t).frame(width: cell, height: cell) }
            Color.clear.frame(width: cell, height: cell)                                   // corner (over the row-select column)
        }
        VStack(spacing: gap) {
            if !bottomSelector { colSel }
            HStack(spacing: gap) {
                VStack(spacing: gap) { ForEach(0..<8, id: \.self) { _ in
                    HStack(spacing: gap) { ForEach(0..<8, id: \.self) { _ in gridCellPH().frame(width: cell, height: cell) } } } }
                VStack(spacing: gap) { ForEach(0..<8, id: \.self) { _ in rowSelCell().frame(width: cell, height: cell) } }
            }
            if bottomSelector { colSel }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
    }

    // ── NAVIGATION (accent capsules; ▲PLAY + the vertical seam share the style) ──
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

    // The grid column (SELECT/PART): ▲PLAY directly on top of the 8 column-select cells, then the square unit.
    @ViewBuilder private func gridColumn(_ box: CGSize) -> some View {
        let gap: CGFloat = 3, playH: CGFloat = 22
        let cell = launchCell(box, playDoor: playH + gap)
        let selW = cell * 8 + 7 * gap
        VStack(alignment: .leading, spacing: gap) {
            navPlayDoor().frame(width: selW).padding(.leading, 6)     // aligned above the 8 column-select cells (panel inset 6)
            launchUnit(cell: cell, bottomSelector: false)
            Spacer(minLength: 0)
        }.frame(width: box.width, alignment: .leading)
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navW: CGFloat = 20
            let avail = g.size.width - 16 - navW - 8, gridW = avail * 2 / 3
            HStack(spacing: 4) {
                gridColumn(CGSize(width: gridW, height: g.size.height - 16))     // grid (left)
                chainPanel().frame(width: avail - gridW)                         // chain (right of grid)
                verticalSeam("▸", to: .part).frame(width: navW)                 // seam on the FAR side (right of chain) → PART
            }.padding(8)
        }
    }
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        GeometryReader { g in
            let navW: CGFloat = 20
            let avail = g.size.width - 16 - navW - 8, gridW = avail * 2 / 3
            HStack(spacing: 4) {
                verticalSeam("◂", to: .select).frame(width: navW)               // seam on the FAR side (left of chain) → SELECT
                chainPanel().frame(width: avail - gridW)                         // chain (left of grid)
                gridColumn(CGSize(width: gridW, height: g.size.height - 16))     // grid (right)
            }.padding(8)
        }
    }
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part); Spacer() }.padding(.horizontal, 10).padding(.top, 8)
            GeometryReader { g in
                let cell = launchCell(g.size, playDoor: 0)
                HStack { Spacer(minLength: 0); launchUnit(cell: cell, bottomSelector: true); Spacer(minLength: 0) }
            }.padding(.horizontal, 10).padding(.bottom, 8)
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
