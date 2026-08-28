import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (default; cog → DISPLAY → NEW UI
// toggles old BUILD). Restructured 2026-08-28 to a PERSISTENT FRAME (Paul's confirmed shape):
//   ┌ §2 SHARED HEADER — 8 track-heads, SAME on every room (tap = play/stop · long-press = assign) ┐
//   │  THE ROOM (one grid in view): SELECT/PART = grid + panels + ▲PLAY door · PLAY = tracks + band  │
//   └ §1 FOOTER STACK — footer › MIXER (I/O console) › CONFIG (sheets), persistent ─────────────────┘
// BUILD ORDER (Paul): header → footer → panels. THIS pass = the frame + the SHARED HEADER. The FOOTER is a placeholder
// bar (real mixer/config layer next); the SELECT↔PART side seam is still a plain door (the exclusive side-column next);
// PART/PLAY/REEL bodies stay honest placeholders (housed room-by-room, reusing their real components per §6).
// RECORD is intentionally OUT for now (Paul) — returns with the footer; the REEL room is temporarily unreachable.
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }

    // ── THE PERSISTENT FRAME ──────────────────────────────────────────────────────────────────────
    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            roomsHeader()                                    // §2 shared header — top row of every room
            roomsMiddle(size).frame(maxWidth: .infinity, maxHeight: .infinity)   // the room in view
            roomsFooter()                                    // §1 footer stack (placeholder this pass)
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    // §2 THE SHARED HEADER — one component, four surfaces: the 8 track-heads. TAP = play/stop that track; LONG-PRESS =
    // assign (stub until the real tracks land — this pass builds the component + grammar, not the track wiring).
    @ViewBuilder func roomsHeader() -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { t in
                let on = t < roomsTrackOn.count && roomsTrackOn[t]
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(on ? roomsAccent.opacity(0.9) : Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12)))
                    VStack(spacing: 1) {
                        Text("\(t + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55))
                        Image(systemName: on ? "play.fill" : "pause").font(.system(size: 8)).foregroundColor(on ? .black.opacity(0.7) : .white.opacity(0.28))
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 42)
                .contentShape(Rectangle())
                .onTapGesture { if t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }        // TAP = play/stop
                .onLongPressGesture(minimumDuration: 0.4) { /* LONG-PRESS = assign — wired when tracks are real */ }
            }
        }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    // §1 THE FOOTER STACK — persistent; taps outward footer → MIXER (I/O console) → CONFIG (sheets). Placeholder bar this
    // pass; the real mixer/config layers (reusing the existing components) are the NEXT increment.
    @ViewBuilder func roomsFooter() -> some View {
        HStack(spacing: 8) {
            Text("FOOTER").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.45))
            Text("›  MIXER  ›  CONFIG").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.28))
            Spacer()
            Text("built next").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.22))
        }.padding(.horizontal, 14).padding(.vertical, 9).background(Color.white.opacity(0.04))
    }

    // ── THE ROOM IN VIEW (the middle; header + footer are the frame) ───────────────────────────────
    @ViewBuilder private func roomsMiddle(_ size: CGSize) -> some View {
        switch roomsRoom {
        case .select: roomsSelect(size)
        case .part:   roomsPart(size)
        case .play:   roomsPlay(size)
        case .reel:   roomsReel(size)
        }
    }

    // §1 the thin TOP door sweeping UP to the PLAY grid (on SELECT and PART).
    private func topDoorToPlay() -> some View {
        Button { roomsRoom = .play } label: {
            HStack(spacing: 6) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    // §4 SELECT↔PART seam — v1 stand-in for the shared exclusive side column (the real one is the next-but-one increment).
    private func sideDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 14).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
        }.buttonStyle(.plain)
    }
    private func provDoor(_ label: String, dim: Bool = false, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(dim ? 0.3 : 0.7))
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(dim ? 0.04 : 0.09)))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func roomPlaceholder(_ name: String, _ blurb: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(roomsAccent.opacity(0.40), lineWidth: 2))
            VStack(spacing: 8) {
                Text(name).font(.system(size: 32, weight: .black, design: .monospaced)).foregroundColor(roomsAccent)
                Text(blurb).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12)
    }

    // SELECT (the shop) — the REAL grid selector re-housed (§6). ▲PLAY door; a side door to PART. Its right-hand column
    // IS the chain PANEL; the full left/right panel wiring comes with the "panels" increment.
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            topDoorToPlay().padding(.horizontal, 12)
            buildGridSelectorBody(size: CGSize(width: size.width, height: max(160, size.height - 190)))
                .frame(maxHeight: .infinity)
                .onAppear { buildEnsureGridSelOpen() }
                .onDisappear { buildCloseGridSel() }
            HStack { Spacer(); sideDoor("PART ▸", to: .part) }.padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    // PART (the workshop) — placeholder body; ▲PLAY door; side door to SELECT. (Chain panels arrive with the panels increment.)
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            topDoorToPlay().padding(.horizontal, 12)
            roomPlaceholder("PART", "the workshop — build a part  ·  housed next")
            HStack { sideDoor("◂ SELECT", to: .select); Spacer() }.padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    // PLAY (the stage) — 8 vertical tracks (their HEADS are the shared header above); the bottom 10-door PROVENANCE band.
    // No chain panels (§3b). Track interiors reserved (§3).
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(roomsAccent.opacity(0.22)))
                }
            }.frame(maxHeight: .infinity).padding(.horizontal, 12).padding(.top, 4)
            HStack(spacing: 4) {   // §4b THE BOTTOM BAND — 10 provenance doors
                provDoor("SELECT") { roomsRoom = .select }                                   // general (bottom-left corner)
                ForEach(0..<8, id: \.self) { _ in provDoor("·", dim: true) { } }             // per-track (dim; hue/mark/travel wired later)
                provDoor("PART") { roomsRoom = .part }                                       // general (bottom-right corner)
            }.padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    // REEL (the tape) — placeholder; a door back to PLAY (its RECORD entrance returns with the footer).
    @ViewBuilder private func roomsReel(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            roomPlaceholder("REEL", "the tape — recorded passes  ·  housed next").padding(.top, 4)
            HStack { sideDoor("◂ PLAY", to: .play); Spacer() }.padding(.horizontal, 12).padding(.bottom, 10)
        }
    }
}
