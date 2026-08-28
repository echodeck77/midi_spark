import SwiftUI

// INTERFACE REDESIGN (Docs/INSTRUCTIONS-interface-redesign.md) — the parallel NEW-interface shell, behind the preview
// toggle (old BUILD stays the default + fully working; cog → DISPLAY → NEW INTERFACE flips into this).
//
// INCREMENT 1 (2026-08-28): the SCAFFOLD only. The room geography as PLACEHOLDERS + working room navigation (taps on
// door-buttons) + RECORD cornered + a footer-stack placeholder. "One grid in view at a time" (§1). Nothing here touches
// the document. Real room content lands room-by-room, REUSING the existing components per the §6 mandate:
//   SELECT ← the grid selector · PART ← staging/authoring · PLAY ← the multi-row/stack tracks · REEL ← the pass browser
//   footer stack ← the I/O console (mixer) + MIDI/RACK sheets (config) · chain editor ← the summoned overlay.
extension DiagView {
    enum Room: String, CaseIterable {
        case select = "SELECT", part = "PART", play = "PLAY", reel = "REEL"
        var blurb: String {
            switch self {
            case .select: return "the shop — browse chains"
            case .part:   return "the workshop — build a part"
            case .play:   return "the stage — eight tracks"
            case .reel:   return "the tape — recorded passes"
            }
        }
    }

    @ViewBuilder func roomsPage(_ size: CGSize) -> some View {
        let accent = Color(red: 0.19, green: 0.83, blue: 0.91)   // the app cyan (buildCyan is file-private to BuildPage)
        VStack(spacing: 0) {
            // §2 THE SHARED HEADER (8 cells) — placeholder for now.
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06))
                        .frame(height: 34).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.10)))
                }
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            // THE ROOM IN VIEW — one grid at a time (§1). Placeholder body until each room is housed.
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.40), lineWidth: 2))
                VStack(spacing: 8) {
                    Text(roomsRoom.rawValue).font(.system(size: 34, weight: .black, design: .monospaced)).foregroundColor(accent)
                    Text(roomsRoom.blurb).font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    Text("scaffold — content arrives per increment").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.30))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12)

            // §1 THE FOOTER STACK — persistent footer, tapping outward → MIXER → CONFIG. Placeholder.
            HStack {
                Text("FOOTER  ›  MIXER  ›  CONFIG").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.30)).tracking(1)
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.white.opacity(0.03))

            // THE DOOR BAND — tap a door to change room. RECORD stays cornered bottom-left (§1; its corner = the reel's
            // entrance, §4b). This flat band is TEMPORARY — the real door choreography (top doors on SELECT/PART, the
            // 10-door provenance band on PLAY) lands with those rooms.
            HStack(spacing: 6) {
                Button { roomsRoom = .reel } label: {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 42, height: 42)
                        .overlay(Text("REC").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.white))
                }.buttonStyle(.plain)
                ForEach(Room.allCases, id: \.self) { room in
                    let on = room == roomsRoom
                    Button { roomsRoom = room } label: {
                        Text(room.rawValue).font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.6))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? accent : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}
