//  HocketPopup.swift
//  HOCKET ferry (2026-10-27) §2–§4: the pop-up that holds up to four rules. SwiftUI-only on purpose (GridUI seam rule): every colour, size and word is decided by the pure functions in Derivations.swift
//  (`hocketPopupFrames`, `hocketChipLook`, `hocketTabLook`, `hocketOnOffLook`, `HocketText`, `hocketRouteLines` …) — this file only paints them and wires a finger to `hocketToggleOutput` & co.
//  It opens the way the settings sheet does (scrim, right-aligned under the header, one ScrollView under a fixed header + rule row, closed by ×, the HOCKET button or a tap on the dimmed page).
//  Built for the 1 MB extension main stack: every section is its own small View struct with a flat ZStack of placed leaves (the page's construction chain only ever holds a few of them), no big @State.

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}
private func hocketFont(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .monospaced) }
private func hocketText(_ s: String, _ size: CGFloat, em: CGFloat = 0, weight: Font.Weight = .heavy, _ color: HocketColor) -> Text {
    Text(s).font(hocketFont(size, weight)).tracking(em * size).foregroundColor(Color(color))
}
private extension View {
    /// Put a leaf at a frame inside a `ZStack(alignment: .topLeading)` of known size.
    func place(_ r: CGRect) -> some View { frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY) }
}

struct HocketPopup: View {
    let containerW: CGFloat
    let containerH: CGFloat
    let headerBottomY: CGFloat
    let rules: [HocketRule]                      // as stored; when none are, the pop-up shows one empty rule (stored only once something in it is edited)
    @Binding var showing: Int                    // which rule tab shows — not saved; the pop-up opens on R1
    @ObservedObject var live: HocketLiveModel
    let onEdit: (Bool, @escaping (inout [HocketRule]) -> Void) -> Void
    let onClose: () -> Void

    @State private var deleteFor: Int? = nil

    var body: some View {
        let shown = rules.isEmpty ? [HocketRule()] : rules
        let idx = max(0, min(shown.count - 1, showing))
        let f = hocketPopupFrames(width: HocketPopupMetrics.width(containerW: containerW), ruleCount: shown.count, rule: shown[idx])
        let available = max(1, containerH - headerBottomY - 16)
        let cardH = min(f.totalHeight, available)
        return ZStack(alignment: .topTrailing) {
            Color(hex: 0x0C0E12).opacity(0.58)
                .frame(width: containerW, height: max(0, containerH - headerBottomY))
                .offset(y: headerBottomY)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityHidden(true)
            card(f, cardH: cardH, shown: shown, idx: idx)
                .offset(y: headerBottomY + 8)
        }
    }

    private func card(_ f: HocketPopupFrames, cardH: CGFloat, shown: [HocketRule], idx: Int) -> some View {
        typealias M = HocketPopupMetrics
        let scrollH = max(0, cardH - 2 * M.pad - f.fixedHeight - M.sectionGap)
        let snap = HocketRuleSnap(shown[idx])
        return VStack(alignment: .leading, spacing: M.sectionGap) {
            HocketFixedRegion(f: f, rules: shown, idx: idx, deleteFor: $deleteFor,
                              onClose: onClose,
                              onShow: { showing = $0; deleteFor = nil },
                              onAdd: {
                                  var newIndex = shown.count
                                  onEdit(true) { rs in if let n = hocketAddRule(&rs) { newIndex = n } }
                                  showing = newIndex; deleteFor = nil
                              },
                              onToggleOn: { onEdit(true) { rs in if rs.indices.contains(idx) { rs[idx].on.toggle() } } },
                              onDelete: { i in
                                  var next = 0
                                  onEdit(true) { rs in next = hocketDeleteRule(&rs, at: i) }
                                  showing = next; deleteFor = nil
                              })
                .frame(width: f.contentWidth, height: f.fixedHeight, alignment: .topLeading)
                .zIndex(1)
            ScrollView(.vertical, showsIndicators: false) {
                EuclideousStackBreak {
                    AnyView(HocketBody(f: f, rules: shown, idx: idx, snap: snap, live: live, edit: onEdit)
                                .frame(width: f.contentWidth, height: f.bodyHeight, alignment: .topLeading)
                                .opacity(shown[idx].on ? 1 : hocketOffRuleBodyOpacity))
                }
            }
            .frame(width: f.contentWidth, height: scrollH)
        }
        .padding(M.pad)
        .frame(width: f.width, height: cardH, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: M.radius).fill(Color(HocketPalette.sheet)))
        .overlay(RoundedRectangle(cornerRadius: M.radius).stroke(Color(HocketPalette.sheetBorder), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 11, y: 8)
        .overlay(deleteFor == nil ? nil : AnyView(Color.clear.contentShape(Rectangle()).onTapGesture { deleteFor = nil }.accessibilityHidden(true)).zIndex(0))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HocketAX.popupLabel)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
    }
}

// ── the fixed region: header row + rule row ─────────────────────────────────────────────────────────────────────────────────
private struct HocketFixedRegion: View {
    let f: HocketPopupFrames
    let rules: [HocketRule]
    let idx: Int
    @Binding var deleteFor: Int?
    let onClose: () -> Void
    let onShow: (Int) -> Void
    let onAdd: () -> Void
    let onToggleOn: () -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        typealias M = HocketPopupMetrics
        return ZStack(alignment: .topLeading) {
            hocketText(HocketText.title, 14, em: 0.14, HocketPalette.text).lineLimit(1).fixedSize().place(f.title)
                .accessibilityAddTraits(.isHeader)
            closeButton
            Color(HocketPalette.rule).place(f.ruleLine).accessibilityHidden(true)
            ForEach(0..<f.tabs.count, id: \.self) { i in tab(i).place(f.tabs[i]) }
            if let add = f.add { addButton.place(add) }
            onOffButton.place(f.onOff)
            if let d = deleteFor, d < f.tabs.count { deletePopover(d) }
        }
    }

    private var closeButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color(HocketPalette.plate)).frame(width: f.closePlate.width, height: f.closePlate.height)
            Path { p in
                p.move(to: CGPoint(x: 1.5, y: 1.5)); p.addLine(to: CGPoint(x: 8.5, y: 8.5))
                p.move(to: CGPoint(x: 8.5, y: 1.5)); p.addLine(to: CGPoint(x: 1.5, y: 8.5))
            }
            .stroke(Color(HocketPalette.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 10, height: 10)
        }
        .frame(width: f.closeTarget.width, height: f.closeTarget.height)
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .place(f.closeTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HocketAX.closeLabel).accessibilityAddTraits(.isButton)
    }

    private func tab(_ i: Int) -> some View {
        let look = hocketTabLook(showing: i == idx, lit: rules[i].isLit)
        return EuclideousLockPressable(
            label: HocketAX.tab(rule: i + 1, lit: rules[i].isLit), value: "", hint: "", holdActionName: HocketAX.deleteAction,
            content: { _ in
                AnyView(
                    HStack(spacing: HocketPopupMetrics.tabLabelGap) {
                        hocketText("R\(i + 1)", HocketPopupMetrics.tabFont, look.label)
                        dot(look.dot)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(look.fill)))
                )
            },
            onTap: { onShow(i) },
            onHold: { deleteFor = i }
        )
        .accessibilityAddTraits(i == idx ? .isSelected : [])
    }
    @ViewBuilder private func dot(_ d: HocketTabLook.Dot) -> some View {
        switch d {
        case .filled(let c): Circle().fill(Color(c)).frame(width: HocketPopupMetrics.tabDot, height: HocketPopupMetrics.tabDot)
        case .ring(let c): Circle().strokeBorder(Color(c), lineWidth: 1.5).frame(width: HocketPopupMetrics.tabDot, height: HocketPopupMetrics.tabDot)
        }
    }

    private var addButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color(HocketPalette.dashed), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            Path { p in
                p.move(to: CGPoint(x: 5, y: 0)); p.addLine(to: CGPoint(x: 5, y: 10))
                p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: 10, y: 5))
            }
            .stroke(Color(HocketPalette.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 10, height: 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HocketAX.addLabel).accessibilityAddTraits(.isButton)
    }

    private var onOffButton: some View {
        let look = hocketOnOffLook(on: rules[idx].on)
        return hocketText(look.label, HocketPopupMetrics.onOffFont, em: HocketPopupMetrics.onOffTracking, look.text).lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(look.fill)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(look.border), lineWidth: look.borderWidth))
            .contentShape(Rectangle())
            .onTapGesture { onToggleOn() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HocketAX.onOff(rule: idx + 1, on: rules[idx].on))
            .accessibilityAddTraits(.isButton)
    }

    private func deletePopover(_ d: Int) -> some View {
        let tab = f.tabs[d]
        let w = HocketPopupMetrics.textWidth("DELETE RULE \(d + 1)".count, size: 10) + 24
        return hocketText("DELETE RULE \(d + 1)", 10, HocketPalette.text).lineLimit(1)
            .frame(width: w, height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(HocketPalette.plate)))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            .contentShape(Rectangle())
            .onTapGesture { onDelete(d) }
            .offset(x: min(tab.minX, max(0, f.contentWidth - w)), y: tab.maxY + 4)
            .accessibilityLabel("Delete rule \(d + 1)").accessibilityAddTraits(.isButton)
    }
}

// ── the body: the rule's mode, MAIN, SWAP EVERY, ALT and ROUTES, then the footer ───────────────────────────────────────────
private struct HocketBody: View {
    let f: HocketPopupFrames
    let rules: [HocketRule]
    let idx: Int
    let snap: HocketRuleSnap
    @ObservedObject var live: HocketLiveModel
    let edit: (Bool, @escaping (inout [HocketRule]) -> Void) -> Void

    private var rule: HocketRule { rules[idx] }
    private func change(_ mutate: @escaping (inout HocketRule) -> Void) { let i = idx; edit(true) { rs in if rs.indices.contains(i) { mutate(&rs[i]) } } }

    var body: some View {
        let running = live.running && rule.isLit && rule.on
        let turn = live.turn(rule: idx, snap: snap)
        let liveChips = running ? hocketLiveChips(rule: snap, turn: turn) : (main: 0, alt: 0)
        return ZStack(alignment: .topLeading) {
            modeSection
            mainSection(liveMask: liveChips.main, running: running, turn: turn)
            everySection(running: running)
            altSection(liveMask: liveChips.alt, running: running, turn: turn)
            if let routes = f.routes { routesSection(routes) }
            hocketText(HocketText.footer, 9, em: 0.06, weight: .bold, HocketPalette.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(width: f.footer.width, alignment: .leading).offset(x: f.footer.minX, y: f.footer.minY)
        }
        .frame(width: f.contentWidth, height: f.bodyHeight, alignment: .topLeading)
    }

    // 4.1 mode
    private var modeSection: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(HocketPalette.group)).place(f.mode)
            ForEach(0..<2, id: \.self) { i in
                let m: HocketRuleMode = i == 0 ? .swap : .pass
                segment(i == 0 ? "SWAP PARTS" : "PASS THE LINE", selected: rule.mode == m, size: 11, em: 0.08, radius: 6).place(f.modeSegments[i])
                    .onTapGesture { change { $0.mode = m } }
                    .accessibilityElement(children: .ignore).accessibilityLabel(HocketAX.modeName(m)).accessibilityAddTraits(.isButton).accessibilityAddTraits(rule.mode == m ? .isSelected : [])
            }
            hocketText(rule.mode == .swap ? HocketText.swapNote : HocketText.passNote, 10, em: 0.04, weight: .bold, HocketPalette.dim)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(width: f.modeNote.width, alignment: .leading).offset(x: f.modeNote.minX, y: f.modeNote.minY)
        }
    }
    private func segment(_ label: String, selected: Bool, size: CGFloat, em: CGFloat, radius: CGFloat) -> some View {
        hocketText(label, size, em: em, selected ? HocketPalette.ink : HocketPalette.mid).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: radius).fill(selected ? Color(HocketPalette.light) : Color.clear))
            .contentShape(Rectangle())
    }

    // 4.2 MAIN
    private func mainSection(liveMask: UInt8, running: Bool, turn: HocketTurn) -> some View {
        ZStack(alignment: .topLeading) {
            sectionHeader(bar: f.mainBar, barOn: running && !turn.isAlt, title: "MAIN", hint: HocketText.mainHint(rule.mode), at: f.mainHeader)
            grid(labels: f.mainGridLabels, chips: f.mainChips, group: rule.main, other: rule.alt, isMain: true, liveMask: liveMask)
            if let h = f.mainEmptyHint {
                hocketText(HocketText.mainEmpty, 10, weight: .bold, HocketPalette.amber).frame(width: h.width, alignment: .leading).offset(x: h.minX, y: h.minY)
            }
        }
    }
    private func sectionHeader(bar: CGRect, barOn: Bool, title: String, hint: String?, at r: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(barOn ? HocketPalette.light : HocketPalette.plate)).place(bar)
            hocketText(title, 11, em: 0.12, HocketPalette.text).fixedSize().offset(x: bar.maxX + HocketPopupMetrics.barGap, y: bar.midY - 7)
            if let hint {
                hocketText(hint, 10, em: 0.06, weight: .bold, HocketPalette.dim).lineLimit(1).fixedSize()
                    .offset(x: bar.maxX + HocketPopupMetrics.barGap + HocketPopupMetrics.textWidth(title.count, size: 11, tracking: 0.12) + HocketPopupMetrics.barGap, y: bar.midY - 6)
            }
        }
    }

    // 4.3 / 4.4 the output grid
    private func grid(labels: [CGRect], chips: [[CGRect]], group: [Int], other: [Int], isMain: Bool, liveMask: UInt8) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { row in
                hocketText(row == 0 ? "RIFF" : "NOTES", 9, em: 0.1, HocketPalette.dim).lineLimit(1)
                    .frame(width: labels[row].width, height: labels[row].height, alignment: .leading).offset(x: labels[row].minX, y: labels[row].minY)
                ForEach(0..<4, id: \.self) { lane in
                    chip(row: row, lane: lane, frame: chips[row][lane], group: group, isMain: isMain, liveMask: liveMask)
                }
            }
        }
    }
    private func chip(row: Int, lane: Int, frame r: CGRect, group: [Int], isMain: Bool, liveMask: UInt8) -> some View {
        let bus = lane * 2 + row, cable = bus + 1
        let pos = group.firstIndex(of: cable)
        let owner = hocketOutputOwner(cable: cable, rules: rules, excluding: idx)
        let live = pos != nil && liveMask & (UInt8(1) << UInt8(bus)) != 0
        let look = hocketChipLook(lane: lane, inGroup: pos != nil, live: live, takenBy: owner)
        let badge = hocketOrderBadge(position: pos, groupCount: group.count)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: HocketChipMetrics.glyphGap) {
                glyph(notes: row == 1, look.glyph)
                hocketText(HocketLaneNames.lane[lane], HocketChipMetrics.fontSize, em: HocketChipMetrics.tracking, look.text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HocketChipMetrics.padX)
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: HocketChipMetrics.radius).fill(Color(look.fill)))
            .overlay(RoundedRectangle(cornerRadius: HocketChipMetrics.radius).strokeBorder(Color(look.border), lineWidth: 1))
            .shadow(color: look.glow.count > 1 ? Color(look.glow[1].color) : .clear, radius: look.glow.count > 1 ? look.glow[1].radius / 2 : 0)
            .overlay(look.glow.isEmpty ? nil : AnyView(RoundedRectangle(cornerRadius: HocketChipMetrics.radius + 1).strokeBorder(Color(look.glow[0].color), lineWidth: look.glow[0].spread).padding(-look.glow[0].spread)))
            if let tag = look.tag {
                hocketText(tag, HocketChipMetrics.tagFont, HocketPalette.dim).fixedSize()
                    .padding(.horizontal, HocketChipMetrics.tagPadX).frame(height: HocketChipMetrics.tagHeight)
                    .overlay(RoundedRectangle(cornerRadius: HocketChipMetrics.tagRadius).strokeBorder(Color(HocketPalette.takenTag), lineWidth: 1))
                    .offset(x: r.width - HocketChipMetrics.tagInset - (HocketPopupMetrics.textWidth(tag.count, size: HocketChipMetrics.tagFont) + 2 * HocketChipMetrics.tagPadX + 2), y: HocketChipMetrics.tagInset)
            }
            if let n = badge {
                ZStack {
                    Circle().fill(Color(HocketPalette.sheet)).frame(width: HocketChipMetrics.badgeDisc + 2 * HocketChipMetrics.badgeRing, height: HocketChipMetrics.badgeDisc + 2 * HocketChipMetrics.badgeRing)
                    Circle().fill(Color(HocketPalette.light)).frame(width: HocketChipMetrics.badgeDisc, height: HocketChipMetrics.badgeDisc)
                    hocketText("\(n)", HocketChipMetrics.badgeFont, HocketPalette.ink)
                }
                .offset(x: r.width + HocketChipMetrics.badgeBeyond - (HocketChipMetrics.badgeDisc + 2 * HocketChipMetrics.badgeRing) / 2 - 0,
                        y: -HocketChipMetrics.badgeAbove - (HocketChipMetrics.badgeDisc + 2 * HocketChipMetrics.badgeRing) / 2 + 0)
                .allowsHitTesting(false)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .offset(x: r.minX, y: r.minY)
        .zIndex(badge != nil ? 1 : 0)
        .onTapGesture { if look.responds { change { hocketToggleOutput(&$0, cable: cable, inMain: isMain) } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HocketAX.chip(group: isMain ? "Main" : "Alt", cable: cable, inGroup: pos != nil, position: pos, groupCount: group.count, takenBy: owner))
        .accessibilityAddTraits(look.responds ? .isButton : [])
        .accessibilityHint(look.responds ? "Double-tap to toggle" : "")
        .opacity(owner != nil ? 1 : 1)
    }
    @ViewBuilder private func glyph(notes: Bool, _ g: HocketChipLook.Glyph) -> some View {
        let w: CGFloat = notes ? 6 : 9, h: CGFloat = notes ? 12 : 9, radius: CGFloat = notes ? 1.5 : 2
        switch g {
        case .filled(let c): RoundedRectangle(cornerRadius: radius).fill(Color(c)).frame(width: w, height: h)
        case .outline(let c, let o): RoundedRectangle(cornerRadius: radius).strokeBorder(Color(c).opacity(o), lineWidth: 1.5).frame(width: w, height: h)
        }
    }

    // 4.6 SWAP EVERY
    private func everySection(running: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(HocketPalette.plate)).place(CGRect(x: 0, y: f.everyHeader.minY + (f.everyHeader.height - 14) / 2, width: 3, height: 14))
            hocketText("SWAP EVERY", 11, em: 0.12, HocketPalette.text).fixedSize().offset(x: 3 + HocketPopupMetrics.barGap, y: f.everyHeader.midY - 7)
            RoundedRectangle(cornerRadius: 8).fill(Color(HocketPalette.group)).place(f.unit)
            ForEach(0..<4, id: \.self) { i in
                let u = HocketUnit.allCases[i]
                segment(u.rawValue, selected: rule.unit == u, size: 10, em: 0.08, radius: 6).place(f.unitSegments[i])
                    .onTapGesture { change { $0.unit = u } }
                    .accessibilityElement(children: .ignore).accessibilityLabel(HocketAX.unitName(u)).accessibilityAddTraits(.isButton).accessibilityAddTraits(rule.unit == u ? .isSelected : [])
            }
            stepper("MAIN", HocketText.count(rule.mainLen, rule.unit), frame: f.steppers[0], minus: rule.mainLen <= 1, plus: rule.mainLen >= 8, axName: "Main length", axValue: HocketAX.stepperValue(rule.mainLen, rule.unit),
                    onMinus: { change { hocketStepLength(&$0, main: true, by: -1) } }, onPlus: { change { hocketStepLength(&$0, main: true, by: 1) } })
            stepper("ALT", HocketText.count(rule.altLen, rule.unit), frame: f.steppers[1], minus: rule.altLen <= 1, plus: rule.altLen >= 8, axName: "Alt length", axValue: HocketAX.stepperValue(rule.altLen, rule.unit),
                    onMinus: { change { hocketStepLength(&$0, main: false, by: -1) } }, onPlus: { change { hocketStepLength(&$0, main: false, by: 1) } })
            stepper("OFFSET", "\(rule.offset)", frame: f.steppers[2], minus: false, plus: false, axName: "Offset", axValue: "\(rule.offset)",
                    onMinus: { change { hocketStepOffset(&$0, by: -1) } }, onPlus: { change { hocketStepOffset(&$0, by: 1) } })
            countOnWell
            cycleStrip(running: running)
        }
    }
    private func chevron(left: Bool, disabled: Bool) -> some View {
        Path { p in
            if left { p.move(to: CGPoint(x: 7, y: 1)); p.addLine(to: CGPoint(x: 3, y: 5)); p.addLine(to: CGPoint(x: 7, y: 9)) }
            else { p.move(to: CGPoint(x: 3, y: 1)); p.addLine(to: CGPoint(x: 7, y: 5)); p.addLine(to: CGPoint(x: 3, y: 9)) }
        }
        .stroke(Color(disabled ? HocketPalette.takenTag : HocketPalette.mid), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 10, height: 10)
    }
    private func stepper(_ key: String, _ value: String, frame r: CGRect, minus: Bool, plus: Bool, axName: String, axValue: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        let zone = HocketPopupMetrics.stepperZone
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(HocketPalette.well))
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color(HocketPalette.rule), lineWidth: 1)
            HStack(spacing: 0) {
                chevron(left: true, disabled: minus).frame(width: zone, height: r.height).contentShape(Rectangle()).onTapGesture { if !minus { onMinus() } }
                VStack(spacing: 3) {
                    hocketText(key, 9, em: 0.1, HocketPalette.dim).lineLimit(1)
                    hocketText(value, 12, HocketPalette.text).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                chevron(left: false, disabled: plus).frame(width: zone, height: r.height).contentShape(Rectangle()).onTapGesture { if !plus { onPlus() } }
            }
        }
        .place(r)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axName).accessibilityValue(axValue)
        .accessibilityAdjustableAction { dir in if dir == .increment { if !plus { onPlus() } } else { if !minus { onMinus() } } }
    }
    private var countOnWell: some View {
        let counts = (rule.unit == .hits || rule.unit == .passes) && !rule.main.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(HocketPalette.well))
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color(HocketPalette.rule), lineWidth: 1)
            if counts {
                let cable = rule.main[min(rule.countOn, rule.main.count - 1)]
                HStack(spacing: 0) {
                    chevron(left: true, disabled: false).frame(width: HocketPopupMetrics.countOnZone, height: f.countOn.height).contentShape(Rectangle()).onTapGesture { change { hocketStepCountOn(&$0, by: -1) } }
                    HStack(spacing: 10) {
                        hocketText("COUNT ON", 9, em: 0.1, HocketPalette.dim).lineLimit(1)
                        hocketText(HocketLaneNames.output(bus: cable - 1), 12, em: 0.04, HocketPalette.lane100((cable - 1) / 2)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity)
                    chevron(left: false, disabled: false).frame(width: HocketPopupMetrics.countOnZone, height: f.countOn.height).contentShape(Rectangle()).onTapGesture { change { hocketStepCountOn(&$0, by: 1) } }
                }
            } else {
                hocketText(HocketText.countsOnClock, 10, em: 0.06, HocketPalette.dim).lineLimit(1).truncationMode(.tail)
            }
        }
        .place(f.countOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts ? "Count on" : HocketText.countsOnClock.capitalized)
        .accessibilityValue(counts ? HocketAX.outputName(cable: rule.main[min(rule.countOn, rule.main.count - 1)]) : "")
        .accessibilityAdjustableAction { dir in if counts { change { hocketStepCountOn(&$0, by: dir == .increment ? 1 : -1) } } }
    }
    private func cycleStrip(running: Bool) -> some View {
        let L = f.cycleCells.count
        let ring = running ? Int(live.counts[idx < live.counts.count ? idx : 0] % Int64(max(1, L))) : -1
        return ZStack(alignment: .topLeading) {
            ForEach(0..<L, id: \.self) { i in
                let alt = hocketCycleCellIsAlt(i, offset: rule.offset, mainLen: rule.mainLen, altLen: rule.altLen)
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(alt ? HocketPalette.altCell : HocketPalette.plate))
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color(alt ? HocketPalette.dim : HocketPalette.plate), lineWidth: 1)
                    hocketText(alt ? "A" : "M", 10, alt ? HocketPalette.text : HocketPalette.mid)
                    if i == ring { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(HocketPalette.light), lineWidth: 2) }
                }
                .place(f.cycleCells[i])
            }
            hocketText("CYCLE", 9, em: 0.08, HocketPalette.dim).fixedSize().offset(x: f.cycleCaption.minX, y: f.cycleCaption.minY)
            hocketText(HocketText.cycleCaption(rule), 9, em: 0.08, HocketPalette.dim).lineLimit(1).fixedSize()
                .frame(width: f.cycleCaption.width, alignment: .trailing).offset(x: f.cycleCaption.minX, y: f.cycleCaption.minY)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HocketAX.cycle(rule))
    }

    // 4.7 ALT
    private func altSection(liveMask: UInt8, running: Bool, turn: HocketTurn) -> some View {
        ZStack(alignment: .topLeading) {
            sectionHeader(bar: f.altBar, barOn: running && turn.isAlt && !rule.alt.isEmpty, title: "ALT", hint: nil, at: f.altHeader)
            segmented2(frame: f.several, segs: f.severalSegments, labels: ["TOGETHER", "ROTATE"], selected: rule.several == .together ? 0 : 1, dim: rule.alt.count < 2,
                       names: ["Together", "Rotate"], onSelect: { i in change { $0.several = i == 0 ? .together : .rotate } })
            grid(labels: f.altGridLabels, chips: f.altChips, group: rule.alt, other: rule.main, isMain: false, liveMask: liveMask)
            if let n = f.bothGroupsNote, let t = hocketBothGroupsNote(rule) {
                hocketText(t, 10, em: 0.04, weight: .bold, HocketPalette.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(width: n.width, alignment: .leading).offset(x: n.minX, y: n.minY)
            }
        }
    }
    private func segmented2(frame r: CGRect, segs: [CGRect], labels: [String], selected: Int, dim: Bool, names: [String], onSelect: @escaping (Int) -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(Color(HocketPalette.group)).place(r)
            ForEach(0..<labels.count, id: \.self) { i in
                segment(labels[i], selected: selected == i, size: HocketPopupMetrics.severalFont, em: 0.08, radius: 5).place(segs[i])
                    .onTapGesture { onSelect(i) }
                    .accessibilityElement(children: .ignore).accessibilityLabel(names[i]).accessibilityAddTraits(.isButton).accessibilityAddTraits(selected == i ? .isSelected : [])
            }
        }
        .opacity(dim ? 0.55 : 1)
    }

    // 4.9 ROUTES
    private func routesSection(_ well: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(HocketPalette.well)).place(well)
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color(HocketPalette.rule), lineWidth: 1).place(well)
            if let h = f.routesHeader {
                hocketText("ON ALT TURNS", 9, em: 0.1, HocketPalette.dim).fixedSize().offset(x: h.minX, y: well.minY + HocketPopupMetrics.routesPad.top + 8)
            }
            if let c = f.routesControl {
                let own = rule.own == .replace ? 0 : 1
                let reW = HocketPopupMetrics.textWidth(7, size: HocketPopupMetrics.severalFont, tracking: 0.08) + 2 * HocketPopupMetrics.severalPadX
                let segs = [CGRect(x: c.minX + HocketPopupMetrics.severalInset, y: c.minY + HocketPopupMetrics.severalInset, width: reW, height: HocketPopupMetrics.severalSegHeight),
                            CGRect(x: c.minX + HocketPopupMetrics.severalInset + reW + HocketPopupMetrics.severalSegGap, y: c.minY + HocketPopupMetrics.severalInset,
                                   width: c.width - 2 * HocketPopupMetrics.severalInset - reW - HocketPopupMetrics.severalSegGap, height: HocketPopupMetrics.severalSegHeight)]
                segmented2(frame: c, segs: segs, labels: ["REPLACE", "MERGE"], selected: own, dim: false, names: ["Replace", "Merge"], onSelect: { i in change { $0.own = i == 0 ? .replace : .merge } })
            }
            let lines = hocketRouteLines(rule)
            ForEach(0..<min(lines.count, f.routeLines.count), id: \.self) { i in
                hocketText(lines[i], 11, em: 0.04, HocketPalette.text).fixedSize(horizontal: false, vertical: true)
                    .frame(width: f.routeLines[i].width, alignment: .leading).offset(x: f.routeLines[i].minX, y: f.routeLines[i].minY)
            }
            if let n = f.routesNote, let t = hocketRouteNote(rule) {
                hocketText(t, 10, em: 0.04, weight: .bold, HocketPalette.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(width: n.width, alignment: .leading).offset(x: n.minX, y: n.minY)
            }
        }
    }
}
