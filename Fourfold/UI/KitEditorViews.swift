//  KitEditorViews.swift — KIT SOURCE ferry (2026-11-23), §4: the kit editor overlay.
//
//  A full overlay over the lane-cards block (mounted in `pageBody` like HARMONY). Eight rank cells, a NAME · VEL
//  row for the selected rank, and a two-octave keyboard (14 white + 10 black keys) with octave ‹ / › buttons. A key
//  tap assigns the note + its GM name to the selected rank and auditions it (§4.6); the rank's previous note is
//  marked (§4.7). RESET GM restores the default kit (§4.10). Labels and values only — no explanatory text (Paul).
//
//  A standalone View (not closures over the page's big @State) so it costs the page's 1 MB main stack nothing beyond
//  one `EuclideousStackBreak`. Every frame comes from the pure `euclideousKitEditorLayout`.

import SwiftUI

struct EuclideousKitEditorView: View {
    let lane: Int
    let selectedRank: Int            // 0-based
    let notes: [UInt8]               // 8, the lane's kit notes (resolved)
    let names: [String]              // 8
    let vels: [UInt8]                // 8
    let lowC: Int                    // the keyboard's low C
    let prevNote: UInt8?             // §4.7 the selected rank's previous note
    let laneColor: Color             // the lane's lane100 accent
    let box: CGSize                  // the lane-cards block size

    var onSelectRank: (Int) -> Void
    var onAssignNote: (UInt8) -> Void   // assign note (+ GM name + audition) to the selected rank
    var onSetName: (String) -> Void
    var onSetVel: (Int, Bool) -> Void   // value, isFirstOfDrag (one undo step per drag)
    var onOctave: (Bool) -> Void        // true = up (›)
    var onResetGM: () -> Void
    var onClose: () -> Void

    var isDrumPicker: Bool = false       // DRUM MODE §4.1: the DRUM picker variant — title DRUM, no RESET / ranks / NAME; the keyboard sets the lane's drum note
    var selectedNote: UInt8? = nil       // the note to highlight on the keyboard (the drum note in the picker; else the selected rank's note)
    var onMakeDrum: (() -> Void)? = nil  // §4.5: the kit editor's DRUM button (nil in the picker)

    @Binding var nameDraft: String
    @State private var velDragging = false

    private var layout: EuclideousKitEditorLayout { euclideousKitEditorLayout(box: box, lowC: lowC, showsRanksAndName: !isDrumPicker) }

    var body: some View {
        let L = layout
        ZStack(alignment: .topLeading) {
            // §4.1 surface #1B1D23, border #2E3138, r12, shadow
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1B1D23))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0x2E3138), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.6), radius: 22, x: 0, y: 8)
                .frame(width: L.card.width, height: L.card.height)
                .position(x: L.card.midX, y: L.card.midY)

            header(L)
            if !isDrumPicker { ranks(L); nameVel(L) }
            octaveButtons(L)
            keyboard(L)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }

    // MARK: header — title · RESET GM · close (§4.2)
    private func header(_ L: EuclideousKitEditorLayout) -> some View {
        let headerBtn: (String, String, @escaping () -> Void) -> AnyView = { title, ax, action in AnyView(
            Button(action: action) {
                Text(title).font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xC6CBD3))
                    .frame(width: L.resetBtn.width, height: L.resetBtn.height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x24262C)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
            }.accessibilityLabel(ax)) }
        return ZStack(alignment: .leading) {
            Text(isDrumPicker ? "DRUM" : "KIT \(lane + 1)").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(1)
                .foregroundColor(Color(hex: 0xF2F4F7))
                .frame(width: L.header.width, alignment: .leading)
            if !isDrumPicker {
                headerBtn("RESET GM", "Reset to GM kit", onResetGM)
                    .frame(width: L.header.width, alignment: .trailing).padding(.trailing, L.closeBtn.width + 8)
                if let mk = onMakeDrum {   // §4.5: the DRUM button, 8 before RESET GM
                    headerBtn("DRUM", "Make drum", mk)
                        .frame(width: L.header.width, alignment: .trailing).padding(.trailing, L.closeBtn.width + 8 + L.resetBtn.width + 8)
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: 0xC6CBD3))
                    .frame(width: L.closeBtn.width, height: L.closeBtn.height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x24262C)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
            }
            .frame(width: L.header.width, alignment: .trailing)
            .accessibilityLabel("Close kit editor")
        }
        .frame(width: L.header.width, height: L.header.height)
        .position(x: L.header.midX, y: L.header.midY)
    }

    // MARK: 8 rank cells (§4.3) — rank · name · note; the selected one lane-tinted.
    private func ranks(_ L: EuclideousKitEditorLayout) -> some View {
        ForEach(0..<min(8, L.ranks.count), id: \.self) { r in
            let sel = r == selectedRank
            let rect = L.ranks[r]
            VStack(spacing: 2) {
                Text("\(r + 1)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: sel ? 0x0D0F14 : 0x8A909A))
                Text(r < names.count ? names[r] : "").font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundColor(Color(hex: sel ? 0x0D0F14 : 0xF2F4F7))
                Text("\(r < notes.count ? Int(notes[r]) : 0)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: sel ? 0x0D0F14 : 0x8A909A))
            }
            .frame(width: rect.width, height: rect.height)
            .background(RoundedRectangle(cornerRadius: 7).fill(sel ? laneColor : Color(hex: 0x24262C)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: sel ? 0x000000 : 0x33363D).opacity(sel ? 0.25 : 1), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onSelectRank(r) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rank \(r + 1), \(r < names.count ? names[r] : ""), note \(r < notes.count ? Int(notes[r]) : 0)")
            .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: NAME · VEL (§4.4)
    private func nameVel(_ L: EuclideousKitEditorLayout) -> some View {
        let vel = selectedRank < vels.count ? Int(vels[selectedRank]) : 100
        return Group {
            // NAME — a text field seeded with the rank's current label; it saves on every change (not only on return — §4.4).
            TextField("NAME", text: $nameDraft, onCommit: { onSetName(nameDraft) })
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0xF2F4F7))
                .autocorrectionDisabled(true)
                .multilineTextAlignment(.leading)
                .onChange(of: nameDraft) { onSetName($0) }
                .padding(.horizontal, 10)
                .frame(width: L.nameField.width, height: L.nameField.height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x14151A)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
                .accessibilityLabel("Name, rank \(selectedRank + 1)")
                .position(x: L.nameField.midX, y: L.nameField.midY)
            // VEL — a horizontal fill tile, tap/drag sets 0…100 %
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x14151A))
                RoundedRectangle(cornerRadius: 7).fill(laneColor.opacity(0.35))
                    .frame(width: max(0, L.velField.width * CGFloat(vel) / 100))
                Text("VEL \(vel)%").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
                    .padding(.leading, 10)
            }
            .frame(width: L.velField.width, height: L.velField.height)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let v = Int((g.location.x / max(1, L.velField.width) * 100).rounded())
                let first = !velDragging; velDragging = true
                onSetVel(max(0, min(100, v)), first)
            }.onEnded { _ in velDragging = false })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Velocity, rank \(selectedRank + 1)")
            .accessibilityValue("\(vel) percent")
            .position(x: L.velField.midX, y: L.velField.midY)
        }
    }

    // MARK: octave ‹ / › (§4.9)
    private func octaveButtons(_ L: EuclideousKitEditorLayout) -> some View {
        let hi = min(127, lowC + 23)
        return Group {
            octButton("‹", rect: L.octDown, enabled: lowC > 0) { onOctave(false) }
            octButton("›", rect: L.octUp, enabled: lowC < 96) { onOctave(true) }
            // the visible note range, so it's clear which octaves are shown (Paul 2026-11-23)
            VStack(spacing: 1) {
                Text("\(lowC)–\(hi)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
                Text("C\(lowC / 12 - 1)–C\(hi / 12 - 1)").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
            }
            .frame(width: L.octUp.maxX - L.octDown.minX)
            .position(x: (L.octDown.minX + L.octUp.maxX) / 2, y: L.octDown.maxY + 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Showing notes \(lowC) to \(hi)")
        }
    }
    private func octButton(_ glyph: String, rect: CGRect, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: enabled ? 0xC6CBD3 : 0x4A4E57))
                .frame(width: rect.width, height: rect.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x24262C)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
        }
        .disabled(!enabled)
        .accessibilityLabel(glyph == "‹" ? "Octave down" : "Octave up")
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: keyboard (§4.5/§4.6/§4.7)
    private func keyboard(_ L: EuclideousKitEditorLayout) -> some View {
        let selNote = selectedNote ?? (selectedRank < notes.count ? notes[selectedRank] : nil)
        return Canvas { ctx, _ in
            for k in L.whiteKeys {
                let r = k.rect.offsetBy(dx: -L.keyboard.minX, dy: -L.keyboard.minY).insetBy(dx: 0.5, dy: 0.5)
                let path = Path(roundedRect: r, cornerRadius: 3)
                let on = (selNote != nil && k.note == selNote!)
                ctx.fill(path, with: .color(on ? laneColor : Color(hex: 0xE4E7EC)))
                ctx.stroke(path, with: .color(Color(hex: 0x33363D)), lineWidth: 1)
                if let p = prevNote, p == k.note, !on {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 3, dy: 3), cornerRadius: 2), with: .color(laneColor), lineWidth: 2)   // §4.7 previous-note mark
                }
                // Every white key is labelled with its MIDI note number so the visible range reads at a glance (Paul 2026-11-23); a C is emphasised (dark, with its octave) as the octave anchor.
                let isC = Int(k.note) % 12 == 0
                let ink = Color(hex: on ? 0x0D0F14 : (isC ? 0x15171C : 0x6B7280))
                let num = Text("\(Int(k.note))").font(.system(size: 8.5, weight: isC ? .heavy : .semibold, design: .monospaced)).foregroundColor(ink)
                ctx.draw(num, at: CGPoint(x: r.midX, y: r.maxY - 9))
                if isC {
                    let oct = Text("C\(Int(k.note) / 12 - 1)").font(.system(size: 7.5, weight: .heavy, design: .monospaced)).foregroundColor(ink)
                    ctx.draw(oct, at: CGPoint(x: r.midX, y: r.maxY - 18))
                }
            }
            for k in L.blackKeys {
                let r = k.rect.offsetBy(dx: -L.keyboard.minX, dy: -L.keyboard.minY)
                let path = Path(roundedRect: r, cornerRadius: 2.5)
                let on = (selNote != nil && k.note == selNote!)
                ctx.fill(path, with: .color(on ? laneColor : Color(hex: 0x1F2227)))
                if let p = prevNote, p == k.note, !on {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 2), with: .color(laneColor), lineWidth: 2)
                }
            }
        }
        .frame(width: L.keyboard.width, height: L.keyboard.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in
            let p = CGPoint(x: g.location.x + L.keyboard.minX, y: g.location.y + L.keyboard.minY)
            if let note = euclideousKitKeyAt(p, layout: L) { onAssignNote(note) }
        })
        .accessibilityHidden(true)   // the ranks carry the accessible note values; the keyboard is a visual assign surface (§6.2)
        .position(x: L.keyboard.midX, y: L.keyboard.midY)
    }
}

// MARK: - DRUM MODE (ferry 2026-11-23) — small shapes + the two-thumb VEL slider used on the lane card.

/// §3.4 a 10 × 6 down chevron (open path; stroked by the caller).
struct EuclideousChevronDown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); return p
    }
}

/// §3.4 the ramp icon — four bars (4 wide, 2 apart, radius 1) rising (UP: 5, 8, 12, 16) or falling (DOWN: the reverse), bottom-aligned in a 26 × 18 box. A Shape, so the caller's `.foregroundColor` fills it.
struct EuclideousRampBars: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let heights: [CGFloat] = up ? [5, 8, 12, 16] : [16, 12, 8, 5]
        let bw: CGFloat = 4, gap: CGFloat = 2
        let total = bw * 4 + gap * 3
        var x = r.midX - total / 2
        for h in heights {
            p.addRoundedRect(in: CGRect(x: x, y: r.maxY - h, width: bw, height: h), cornerSize: CGSize(width: 1, height: 1))
            x += bw + gap
        }
        return p
    }
}

/// §3.5 the two-thumb velocity slider. Track 8 tall; the span between the thumbs in the lane colour; thumbs 22 × 30. The full height is the touch area, each side going to the nearer thumb. 0…100 step 1; the thumbs meet but never cross.
/// A drag sounds nothing and reports (low, high, isFirstOfDrag) so the page records one undo step per drag.
struct EuclideousDrumVelSlider: View {
    let low: Int; let high: Int; let laneColor: Color; let width: CGFloat; let height: CGFloat
    var onChange: (Int, Int, Bool) -> Void
    @Binding var dragging: Bool
    @State private var active: Int = 0   // 0 = none, 1 = low, 2 = high (which thumb this drag grabbed)

    private let thumbW: CGFloat = 22, thumbH: CGFloat = 30, trackH: CGFloat = 8
    private func x(_ v: Int) -> CGFloat { let inset = thumbW / 2; return inset + (width - thumbW) * CGFloat(max(0, min(100, v))) / 100 }
    private func valueAt(_ px: CGFloat) -> Int { let inset = thumbW / 2; return Int((((px - inset) / max(1, width - thumbW)) * 100).rounded()) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x2A2D34)).frame(width: width, height: trackH)
            RoundedRectangle(cornerRadius: 4).fill(laneColor).frame(width: max(0, x(high) - x(low)), height: trackH).offset(x: x(low))
            thumb.offset(x: x(low) - thumbW / 2)
            thumb.offset(x: x(high) - thumbW / 2)
        }
        .frame(width: width, height: height, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let first = active == 0
            if first { active = abs(g.location.x - x(low)) <= abs(g.location.x - x(high)) ? 1 : 2; dragging = true }
            let v = max(0, min(100, valueAt(g.location.x)))
            if active == 1 { onChange(min(v, high), high, first) } else { onChange(low, max(v, low), first) }   // §3.5 meet but never cross
        }.onEnded { _ in active = 0; dragging = false })
    }
    private var thumb: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF2F4F7)).frame(width: thumbW, height: thumbH).shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 2)
    }
}
