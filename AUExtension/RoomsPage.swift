import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Framing per Paul 2026-08-28:
//   • The GRID + its edge SELECT buttons are ONE integrated component (a hardware Launchpad is one unit — grid + the
//     column/row launch buttons — and must feel one-and-the-same for a future Launchpad mapping). Placeholder grids for now.
//   • The COLUMN-SELECT row is the TOP row on SELECT/PART, the BOTTOM row on PLAY. A ROW-SELECT column sits on the right.
//   • The thin NAVIGATION doors live OUTSIDE the grid unit — never between the select buttons and the grid.
//   • Persistent FOOTER below (placeholder this pass → mixer/config next). RECORD is out for now (Paul); REEL is a placeholder.
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }

    // ── THE FRAME: the room in view + the persistent footer (no separate header strip — the header IS the grid's edge) ──
    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            roomsMiddle(size).frame(maxWidth: .infinity, maxHeight: .infinity)
            roomsFooter()
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder private func roomsMiddle(_ size: CGSize) -> some View {
        switch roomsRoom {
        case .select: roomsSelect()
        case .part:   roomsPart()
        case .play:   roomsPlay()
        case .reel:   roomsReel()
        }
    }

    // §1 the persistent FOOTER STACK (footer → MIXER → CONFIG). Placeholder bar this pass; real layers reuse the I/O
    // console + MIDI/RACK sheets next.
    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 8) {
            Text("FOOTER").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.45))
            Text("›  MIXER  ›  CONFIG").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.28))
            Spacer(); Text("built next").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.22))
        }.padding(.horizontal, 14).padding(.vertical, 9).background(Color.white.opacity(0.04))
    }

    // ── THE INTEGRATED GRID UNIT (grid + edge select buttons = ONE component) ──────────────────────
    @ViewBuilder private func roomsLaunchGrid(bottomSelector: Bool) -> some View {
        let rowSelW: CGFloat = 34
        let columnSelectRow = HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { t in colSelCell(t) }
            Color.clear.frame(width: rowSelW)                    // corner — aligns the 8 selectors with the 8 grid columns
        }
        VStack(spacing: 3) {
            if !bottomSelector { columnSelectRow }               // SELECT / PART: column-select on TOP
            HStack(spacing: 3) {
                VStack(spacing: 3) {                             // the 8×8 grid (placeholder while we settle the framing)
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: 3) {
                            ForEach(0..<8, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 3) { ForEach(0..<8, id: \.self) { r in rowSelCell(r) } }.frame(width: rowSelW)   // ROW-select column (right)
            }
            if bottomSelector { columnSelectRow }                // PLAY: column-select on the BOTTOM
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))            // ONE component: unified panel
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(roomsAccent.opacity(0.35), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // §2 the shared column-select button — the SAME 8 cells everywhere (one-and-the-same for a Launchpad). TAP = play/stop
    // (lights); long-press = assign (stub until tracks are real).
    private func colSelCell(_ t: Int) -> some View {
        let on = t < roomsTrackOn.count && roomsTrackOn[t]
        return RoundedRectangle(cornerRadius: 4).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.11))
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .frame(maxWidth: .infinity).frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { if t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
            .onLongPressGesture(minimumDuration: 0.4) { /* assign — wired when tracks are real */ }
    }
    private func rowSelCell(_ r: Int) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.11)).frame(maxHeight: .infinity)
            .overlay(Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4)))
    }

    // ── NAVIGATION (thin doors, OUTSIDE the grid unit — never between the selectors and the grid) ───
    private func navPlayDoor() -> some View {
        Button { roomsRoom = .play } label: {
            HStack(spacing: 5) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    private func navDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.10)))
        }.buttonStyle(.plain)
    }

    // ── THE ROOMS ─────────────────────────────────────────────────────────────────────────────────
    @ViewBuilder private func roomsSelect() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { navPlayDoor(); navDoor("PART ▸", to: .part); Spacer() }   // nav ABOVE the unit
                .padding(.horizontal, 12).padding(.top, 8)
            roomsLaunchGrid(bottomSelector: false).padding(.horizontal, 12).padding(.bottom, 8)   // column-select TOP
        }
    }
    @ViewBuilder private func roomsPart() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { navPlayDoor(); navDoor("◂ SELECT", to: .select); Spacer() }
                .padding(.horizontal, 12).padding(.top, 8)
            roomsLaunchGrid(bottomSelector: false).padding(.horizontal, 12).padding(.bottom, 8)   // column-select TOP
        }
    }
    @ViewBuilder private func roomsPlay() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { navDoor("◂ SELECT", to: .select); navDoor("PART ▸", to: .part); Spacer() }   // nav ABOVE the unit
                .padding(.horizontal, 12).padding(.top, 8)
            roomsLaunchGrid(bottomSelector: true).padding(.horizontal, 12).padding(.bottom, 8)    // column-select BOTTOM
        }
    }
    @ViewBuilder private func roomsReel() -> some View {
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
