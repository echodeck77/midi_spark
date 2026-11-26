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
    var onShift: (Int) -> Void = { _ in }              // KIT EDITOR V2 §3.2: OCT ±12 / SEMI ±1 — move every rank's note
    var onCopy: (EuclideousKitCopyDir) -> Void = { _ in }   // §3.7: ▼ / ▲ copy the selected rank down / up
    // KIT TEMPLATES (ferry 2026-11-25): the header's RESET GM slot becomes a template button that opens a picker over the body.
    var templateName: String = "GM"
    var currentTemplateId: String = "gm"
    var templatePickerOpen: Bool = false
    var pickerTemplates: [EuclideousKitTemplate] = []
    var onTemplateButton: () -> Void = { }
    var onPickTemplate: (String) -> Void = { _ in }
    var template: EuclideousKitTemplate? = nil   // §4: the lane's current template, for key names (nil ⇒ GM names)

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
            if templatePickerOpen && !isDrumPicker {   // KIT TEMPLATES §3.2: the picker replaces the ranks / NAME·VEL / keyboard; the header stays
                templatePicker(L)
            } else {
                if !isDrumPicker { ranks(L); nameVel(L) }
                octaveButtons(L)
                keyboard(L)
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }

    // MARK: KIT TEMPLATES §3.3 — the picker over the editor body: a full-width GM row, then APPS | HARDWARE columns.
    private func templatePicker(_ L: EuclideousKitEditorLayout) -> some View {
        let pad: CGFloat = 16
        let innerX = L.card.minX + pad, innerW = max(1, L.card.width - pad * 2)
        let top = L.header.maxY + 12, bottom = L.card.maxY - pad
        let apps = pickerTemplates.filter { $0.group == .apps }, hw = pickerTemplates.filter { $0.group == .hardware }
        let gm = pickerTemplates.first { $0.group == .gm }
        func row(_ t: EuclideousKitTemplate, width: CGFloat) -> some View {
            let cur = t.id == currentTemplateId
            return HStack(spacing: 8) {
                if cur { Circle().fill(laneColor).frame(width: 8, height: 8) }
                Text(t.name).font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(0.06 * 13).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundColor(Color(hex: cur ? 0x0D0F14 : 0xF2F4F7))
                Spacer(minLength: 0)
            }
            .padding(.leading, 12).frame(width: width, height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(cur ? Color(hex: 0xEDEFF3) : Color(hex: 0x2A2D34)))
            .contentShape(Rectangle()).onTapGesture { onPickTemplate(t.id) }
            .accessibilityElement(children: .ignore).accessibilityLabel(t.name).accessibilityAddTraits(cur ? [.isButton, .isSelected] : .isButton)
        }
        func sectionLabel(_ s: String) -> some View { Text(s).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.1 * 10).foregroundColor(Color(hex: 0x8A909A)).frame(maxWidth: .infinity, alignment: .leading) }
        let colGap: CGFloat = 10, colW = max(1, (innerW - colGap) / 2)
        // §3.3: a FIXED GM row + section labels; the two columns scroll together under them and open scrolled to the current row.
        return VStack(alignment: .leading, spacing: 6) {
            if let gm = gm { row(gm, width: innerW) }
            HStack(spacing: colGap) { sectionLabel("APPS"); sectionLabel("HARDWARE") }
            ScrollViewReader { sv in
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: colGap) {
                        VStack(alignment: .leading, spacing: 6) { ForEach(apps, id: \.id) { row($0, width: colW).id($0.id) } }.frame(width: colW, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) { ForEach(hw, id: \.id) { row($0, width: colW).id($0.id) } }.frame(width: colW, alignment: .leading)
                    }.frame(width: innerW, alignment: .topLeading)
                }
                .onAppear { if currentTemplateId != "gm" { sv.scrollTo(currentTemplateId, anchor: .center) } }
            }
        }
        .frame(width: innerW, height: max(1, bottom - top), alignment: .topLeading)
        .position(x: innerX + innerW / 2, y: top + max(1, bottom - top) / 2)
        .accessibilityElement(children: .contain).accessibilityLabel("Templates")
    }

    // MARK: header (§2.2/§2.3) — KIT · OCT − + · SEMI − + · flex · DRUM · RESET GM · close, each positioned absolutely inside the overlay (no escaping, no overlap).
    @ViewBuilder private func header(_ L: EuclideousKitEditorLayout) -> some View {
        at(L.kitLabel) {
            Text(isDrumPicker ? "DRUM" : "KIT").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(Color(hex: 0xF2F4F7))
                .frame(width: L.kitLabel.width, height: L.kitLabel.height, alignment: .leading).accessibilityAddTraits(.isHeader)
        }
        if !isDrumPicker {   // §3.1 OCT / SEMI wells (kit editor only)
            shiftWell(L.octWell, label: "OCT", minus: L.octMinus, plus: L.octPlus, delta: 12, axDown: "Kit down an octave", axUp: "Kit up an octave")
            shiftWell(L.semiWell, label: "SEMI", minus: L.semiMinus, plus: L.semiPlus, delta: 1, axDown: "Kit down a semitone", axUp: "Kit up a semitone")
            if onMakeDrum != nil { headerBtn(L.drumBtn, "DRUM", "Make drum", action: { onMakeDrum?() }) }
            templateButton(L.resetBtn)   // KIT TEMPLATES §3.1: the RESET GM slot is now the template button (name + chevron)
        }
        headerBtn(L.closeBtn, nil, "Close kit editor", systemImage: "xmark", action: onClose)
    }
    private func at<V: View>(_ r: CGRect, @ViewBuilder _ v: () -> V) -> some View { v().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY) }
    /// §3.1 the template button — the lane's template name (ellipsis-truncated, never widened) + a down chevron; a tap opens/closes the picker.
    private func templateButton(_ r: CGRect) -> some View {
        Button(action: onTemplateButton) {
            HStack(spacing: 8) {
                Text(templateName).font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).truncationMode(.tail).foregroundColor(Color(hex: 0xC6CBD3))
                EuclideousChevronDown().stroke(Color(hex: 0xAAB0BA), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).frame(width: 10, height: 6)
            }
            .padding(.horizontal, 8).frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x24262C)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
        }.accessibilityElement(children: .ignore).accessibilityLabel("Template, \(templateName)").accessibilityAddTraits(.isButton).position(x: r.midX, y: r.midY)
    }
    private func headerBtn(_ r: CGRect, _ title: String?, _ ax: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let s = systemImage { Image(systemName: s).font(.system(size: 13, weight: .bold)) }
                else { Text(title ?? "").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6) }
            }
            .foregroundColor(Color(hex: 0xC6CBD3)).frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x24262C)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x33363D), lineWidth: 1))
        }.accessibilityLabel(ax).position(x: r.midX, y: r.midY)
    }
    /// §3.1 one OCT / SEMI well: a #17191E background, a label, and − / + buttons (disabled + 42 % when a shift of ±`delta` would push any note out of 0…127, §3.4).
    @ViewBuilder private func shiftWell(_ well: CGRect, label: String, minus: CGRect, plus: CGRect, delta: Int, axDown: String, axUp: String) -> some View {
        at(well) { RoundedRectangle(cornerRadius: 8).fill(Color(hex: FourfoldStyle.card)) }
        at(CGRect(x: well.minX + 10, y: well.minY, width: minus.minX - (well.minX + 10) - 3, height: well.height)) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.1 * 10).foregroundColor(Color(hex: 0x8A909A)).frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
        }
        shiftBtn(minus, "−", enabled: euclideousKitCanShift(notes, by: -delta), ax: axDown) { onShift(-delta) }
        shiftBtn(plus, "+", enabled: euclideousKitCanShift(notes, by: delta), ax: axUp) { onShift(delta) }
    }
    private func shiftBtn(_ r: CGRect, _ glyph: String, enabled: Bool, ax: String, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(glyph).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
                .frame(width: r.width, height: r.height).background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
        }.disabled(!enabled).opacity(enabled ? 1 : 0.42).accessibilityLabel(ax).position(x: r.midX, y: r.midY)
    }
    /// §3.6/§3.7 the ▼ / ▲ copy button — a filled triangle; disabled + 42 % on rank 1 (▼) / rank 8 (▲).
    private func copyBtn(_ r: CGRect, down: Bool, enabled: Bool) -> some View {
        Button(action: { if enabled { onCopy(down ? .below : .above) } }) {
            Image(systemName: down ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0xF2F4F7))
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2A2D34)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x3A3E47), lineWidth: 1))
        }.disabled(!enabled).opacity(enabled ? 1 : 0.42)
        .accessibilityLabel(down ? "Copy to every rank below" : "Copy to every rank above").position(x: r.midX, y: r.midY)
    }

    // MARK: 8 rank cells (§4.3) — rank · name · note; the selected one lane-tinted.
    private func ranks(_ L: EuclideousKitEditorLayout) -> some View {
        ForEach(0..<min(8, L.ranks.count), id: \.self) { r in
            let sel = r == selectedRank
            let rect = L.ranks[r]
            let note = r < notes.count ? Int(notes[r]) : 0
            let vel = r < vels.count ? Int(vels[r]) : 100
            let ink = Color(hex: sel ? 0x0D0F14 : 0xF2F4F7), sub = Color(hex: sel ? 0x0D0F14 : 0x8A909A)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7).fill(sel ? laneColor : Color(hex: 0x24262C))
                // §2.6 velocity fill behind — lane colour on an unselected cell, #0D0F14 @ 12 % on the selected (lane-fill) cell so it still reads.
                RoundedRectangle(cornerRadius: 7).fill(sel ? Color(hex: 0x0D0F14).opacity(0.12) : laneColor.opacity(0.16)).frame(height: max(0, rect.height * CGFloat(vel) / 100))
                VStack(spacing: 1) {
                    Text("\(r + 1)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(sub)
                    Text(r < names.count ? names[r] : "").font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5).foregroundColor(ink)
                    Text("\(note) · \(vel)%").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundColor(sub).lineLimit(1).minimumScaleFactor(0.6)
                }.padding(.horizontal, 2)
            }
            .frame(width: rect.width, height: rect.height).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: sel ? 0x000000 : 0x33363D).opacity(sel ? 0.25 : 1), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onSelectRank(r) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rank \(r + 1), \(r < names.count ? names[r] : ""), note \(note), velocity \(vel) percent")
            .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: NAME · VEL (§4.4)
    private func nameVel(_ L: EuclideousKitEditorLayout) -> some View {
        let vel = selectedRank < vels.count ? Int(vels[selectedRank]) : 100
        return Group {
            // §3.6 the selected-rank tile
            at(L.rankTile) {
                VStack(spacing: 0) {
                    Text("\(selectedRank + 1)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    Text(selectedRank < names.count ? names[selectedRank] : "").font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5).foregroundColor(Color(hex: 0xF2F4F7))
                }
                .frame(width: L.rankTile.width, height: L.rankTile.height)
                .background(RoundedRectangle(cornerRadius: 8).fill(laneColor)).accessibilityHidden(true)
            }
            // §3.7 ▼ / ▲ copy the selected rank down / up (velocities untouched); disabled on rank 1 / rank 8
            copyBtn(L.copyDown, down: true, enabled: selectedRank > 0)
            copyBtn(L.copyUp, down: false, enabled: selectedRank < 7)
            // NAME — a text field seeded with the rank's current label. KIT EDITOR V2 §2.1: it commits on RETURN only (the page also commits on rank-switch / close). It MUST NOT commit on every change: the page reseeds `nameDraft` when a rank is selected, and a per-change commit wrote that new name onto the PREVIOUS rank (the stale view's `rank`), shifting names vs notes.
            TextField("NAME", text: $nameDraft, onCommit: { onSetName(nameDraft) })
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0xF2F4F7))
                .autocorrectionDisabled(true)
                .multilineTextAlignment(.leading)
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
                // KIT EDITOR V2 §2.4: the names of the FIRST and LAST notes (e.g. "C2–B3"), not the next C — the last note's own name.
                Text("\(euclideousNoteViewName(UInt8(max(0, min(127, lowC))), flatKey: false))–\(euclideousNoteViewName(UInt8(max(0, min(127, hi))), flatKey: false))").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
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
        // §2.5 helpers: the GM short name (nil outside 35…81) and, in the kit editor, the rank badge for this key's note.
        // §4.1: a key in the template's `keys` shows the device's name; other keys keep their GM name. (GM's own keys are the GM table, so a GM lane is unchanged.)
        func gmName(_ note: UInt8) -> String? { template?.keyName(note) ?? ((35...81).contains(Int(note)) ? euclideousGMDrumName(note) : nil) }
        func badge(_ note: UInt8) -> String { isDrumPicker ? "" : euclideousKitRankBadge((0..<min(8, notes.count)).filter { notes[$0] == note }.map { $0 + 1 }) }
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
                let isC = Int(k.note) % 12 == 0
                let ink = Color(hex: on ? 0x0D0F14 : (isC ? 0x15171C : 0x6B7280))
                // §2.5 bottom-up: NUMBER (C keys as "C2 36"), GM NAME above, rank BADGE above that.
                ctx.draw(Text(isC ? "C\(Int(k.note) / 12 - 1) \(Int(k.note))" : "\(Int(k.note))").font(.system(size: 8, weight: isC ? .heavy : .semibold, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: r.midX, y: r.maxY - 8))
                if let nm = gmName(k.note) { ctx.draw(Text(nm).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: r.midX, y: r.maxY - 19)) }
                let b = badge(k.note)
                if !b.isEmpty { ctx.draw(Text(b).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: on ? 0x0D0F14 : 0x15171C)), at: CGPoint(x: r.midX, y: r.maxY - 30)) }
            }
            for k in L.blackKeys {
                let r = k.rect.offsetBy(dx: -L.keyboard.minX, dy: -L.keyboard.minY)
                let path = Path(roundedRect: r, cornerRadius: 2.5)
                let on = (selNote != nil && k.note == selNote!)
                ctx.fill(path, with: .color(on ? laneColor : Color(hex: 0x1F2227)))
                if let p = prevNote, p == k.note, !on {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 2), with: .color(laneColor), lineWidth: 2)
                }
                // §2.5 black keys show their number (device-owed legibility at the narrow width); GM name above where it fits.
                let ink = Color(hex: on ? 0x0D0F14 : 0xAAB0BA)
                ctx.draw(Text("\(Int(k.note))").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: r.midX, y: r.maxY - 7))
                if let nm = gmName(k.note), r.height > 40 { ctx.draw(Text(nm).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: r.midX, y: r.maxY - 16)) }
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
