import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Framing per Paul 2026-08-28:
//   • GRID + its edge SELECT buttons = ONE integrated component (Launchpad feel). Column-select row on TOP for SELECT/PART,
//     BOTTOM for PLAY; a row-select column on the right. The selector row sits TIGHT against the grid (no gap).
//   • SELECT / PART = TWO-THIRDS grid + ONE-THIRD MIDI CHAIN. Chain on the RIGHT for SELECT, LEFT for PART (mirrored).
//   • Between the grid and the chain: a THIN VERTICAL nav button (matching the ▲PLAY style) — on the RIGHT for SELECT,
//     LEFT for PART. The ▲PLAY button sits DIRECTLY ABOVE the grid's column-select header.
//   • Placeholder grids/chain for now (framing first). Persistent footer below (mixer/config next). RECORD out for now.
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

    // ── THE INTEGRATED GRID UNIT (grid + edge select buttons = ONE component; selectors TIGHT against the grid) ──
    @ViewBuilder private func roomsLaunchGrid(bottomSelector: Bool) -> some View {
        let rowSelW: CGFloat = 30
        let columnSelectRow = HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { t in colSelCell(t) }
            Color.clear.frame(width: rowSelW)
        }
        VStack(spacing: 3) {
            if !bottomSelector { columnSelectRow }
            HStack(spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: 3) {
                            ForEach(0..<8, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 3) { ForEach(0..<8, id: \.self) { r in rowSelCell(r) } }.frame(width: rowSelW)
            }
            if bottomSelector { columnSelectRow }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func colSelCell(_ t: Int) -> some View {
        let on = t < roomsTrackOn.count && roomsTrackOn[t]
        return RoundedRectangle(cornerRadius: 4).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.11))
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .frame(maxWidth: .infinity).frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture { if t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
            .onLongPressGesture(minimumDuration: 0.4) { /* assign — wired when tracks are real */ }
    }
    private func rowSelCell(_ r: Int) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.11)).frame(maxHeight: .infinity)
            .overlay(Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4)))
    }

    // ── NAVIGATION — accent capsules; the ▲PLAY door + the thin VERTICAL seam share one style ──
    private func navPlayDoor() -> some View {                       // full-width, directly ABOVE the grid header
        Button { roomsRoom = .play } label: {
            HStack(spacing: 5) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 22).background(Capsule().fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    private func verticalSeam(_ chevron: String, to room: Room) -> some View {   // thin vertical, between grid and chain
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
    @ViewBuilder private func chainPanel() -> some View {          // §3b the MIDI-chain panel — placeholder for now
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1.5))
            Text("MIDI CHAIN").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.4))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    // SELECT — grid 2/3 (left) · thin vertical seam → PART (right) · MIDI chain 1/3 (right). ▲PLAY directly above the grid.
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        let navW: CGFloat = 20, inner = size.width - 16 - navW
        let gridW = inner * 2 / 3
        HStack(spacing: 0) {
            VStack(spacing: 3) { navPlayDoor(); roomsLaunchGrid(bottomSelector: false) }.frame(width: gridW)
            verticalSeam("▸", to: .part).frame(width: navW).padding(.horizontal, 4)
            chainPanel().frame(width: inner - gridW)
        }.padding(8)
    }
    // PART — mirror of SELECT: MIDI chain 1/3 (left) · seam → SELECT (left) · grid 2/3 (right).
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        let navW: CGFloat = 20, inner = size.width - 16 - navW
        let gridW = inner * 2 / 3
        HStack(spacing: 0) {
            chainPanel().frame(width: inner - gridW)
            verticalSeam("◂", to: .select).frame(width: navW).padding(.horizontal, 4)
            VStack(spacing: 3) { navPlayDoor(); roomsLaunchGrid(bottomSelector: false) }.frame(width: gridW)
        }.padding(8)
    }
    // PLAY — full-width grid unit, column-select on the BOTTOM. Nav doors above (outside the unit). No chain panel (§3b).
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) { navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part); Spacer() }.padding(.horizontal, 8).padding(.top, 8)
            roomsLaunchGrid(bottomSelector: true).padding(.horizontal, 8).padding(.bottom, 8)
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
