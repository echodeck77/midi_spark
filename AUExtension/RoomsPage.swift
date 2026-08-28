import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the NEW room-based shell (now the default; toggle to old
// BUILD in the cog → DISPLAY → NEW UI). Redone 2026-08-28 to the spec's actual GEOGRAPHY (was a generic tab-band):
//   §1 navigation = thin door-buttons, contextual per room. SELECT & PART wear a TOP door sweeping UP to PLAY. PLAY's
//   BOTTOM row = the 10-door provenance band (§4b: SELECT · 8 per-track · PART). RECORD stays CORNERED (bottom-left; it
//   re-corners TOP-LEFT on PLAY to clear the band) and its corner IS the reel's entrance.
// §6 REUSE MANDATE: the SELECT room houses the REAL grid selector (buildGridSelectorBody, re-housed backdrop-free).
// PART / PLAY / REEL bodies are honest placeholders, housed room-by-room next (each reusing its real component):
//   PART ← staging/authoring · PLAY ← the multi-row/stack tracks · REEL ← the pass browser.
// STILL TO COME (flagged, not yet built): the §2 shared 8-cell header (tap=play/stop · long-press=assign) · the §4
// SELECT↔PART side-button exclusive column (a simple side door stands in for now) · the footer STACK (mixer→config) ·
// provenance marks following the lit slot (§4c) · the chain editor as a summoned overlay (§1).
extension DiagView {
    enum Room: String, CaseIterable { case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL" }

    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        switch roomsRoom {
        case .select: roomsSelect(size)
        case .part:   roomsPart(size)
        case .play:   roomsPlay(size)
        case .reel:   roomsReel(size)
        }
    }

    private var roomsAccent: Color { Color(red: 0.19, green: 0.83, blue: 0.91) }

    // RECORD (the reel's entrance, §4b) is LEFT OUT for now (Paul 2026-08-28) until the headers/footers/panels are right.
    // Consequence: the REEL room is temporarily unreachable — that's fine, it's a placeholder; RECORD returns with the footer.
    // §1 the thin TOP door sweeping UP to the PLAY grid (on SELECT and PART).
    private func topDoorToPlay() -> some View {
        Button { roomsRoom = .play } label: {
            HStack(spacing: 6) { Image(systemName: "chevron.up"); Text("PLAY") }
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(roomsAccent))
        }.buttonStyle(.plain)
    }
    // §4 the SELECT↔PART seam — v1 stand-in for the shared exclusive side column (a labelled side door).
    private func sideDoor(_ label: String, to room: Room) -> some View {
        Button { roomsRoom = room } label: {
            Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 14).frame(height: 42)
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

    // SELECT (the shop) — the REAL grid selector, re-housed backdrop-free (§6). Top door up to PLAY; RECORD cornered
    // bottom-left; a side door to PART. Opened on room entry, torn down on exit (stops the audition voice).
    @ViewBuilder private func roomsSelect(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            topDoorToPlay().padding(.horizontal, 12).padding(.top, 8)
            buildGridSelectorBody(size: CGSize(width: size.width, height: max(140, size.height - 104)))
                .frame(maxHeight: .infinity)
                .onAppear { buildEnsureGridSelOpen() }
                .onDisappear { buildCloseGridSel() }
            HStack { Spacer(); sideDoor("PART ▸", to: .part) }.padding(.horizontal, 12).padding(.bottom, 12)
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    // PART (the workshop) — placeholder body; top door up to PLAY; RECORD cornered; side door to SELECT.
    @ViewBuilder private func roomsPart(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            topDoorToPlay().padding(.horizontal, 12).padding(.top, 8)
            roomPlaceholder("PART", "the workshop — build a part  ·  housed next")
            HStack { sideDoor("◂ SELECT", to: .select); Spacer() }.padding(.horizontal, 12).padding(.bottom, 12)
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    // PLAY (the stage) — RECORD re-cornered TOP-LEFT (§4b) beside the 8 track-heads; 8 vertical tracks; the bottom
    // 10-door PROVENANCE band (SELECT · 8 per-track · PART). No chain panels (§3b). Bodies reserved (§3).
    @ViewBuilder private func roomsPlay(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)).frame(height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.10)))   // §2 track-head placeholder
                }
            }.padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(roomsAccent.opacity(0.22)))   // §3 vertical track (reserved)
                }
            }.frame(maxHeight: .infinity).padding(.horizontal, 12)
            HStack(spacing: 4) {   // §4b THE BOTTOM BAND — 10 provenance doors
                provDoor("SELECT") { roomsRoom = .select }                                   // general (bottom-left corner)
                ForEach(0..<8, id: \.self) { _ in provDoor("·", dim: true) { } }             // per-track (dim; travel-home wired later)
                provDoor("PART") { roomsRoom = .part }                                       // general (bottom-right corner)
            }.padding(.horizontal, 12).padding(.bottom, 12)
        }.frame(width: size.width, height: size.height, alignment: .top)
    }

    // REEL (the tape) — placeholder; reached via RECORD's corner; a door back to PLAY.
    @ViewBuilder private func roomsReel(_ size: CGSize) -> some View {
        VStack(spacing: 6) {
            roomPlaceholder("REEL", "the tape — recorded passes  ·  housed next").padding(.top, 8)
            HStack { sideDoor("◂ PLAY", to: .play); Spacer() }.padding(.horizontal, 12).padding(.bottom, 12)
        }.frame(width: size.width, height: size.height, alignment: .top)
    }
}
