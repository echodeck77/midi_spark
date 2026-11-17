//  RibbonSettingsViews.swift — RIBBON SETTINGS ferry (2026-11-16), slice 5: the settings button (§4) and the settings tab (§5).
//
//  The button sits in the riff panel's bottom-left free space and toggles the tab; the tab replaces the grid and rails inside the
//  panel (the header stays) and holds TOUCH · RELEASE · LATCH · PARTS. Every frame comes from `euclideousRibbonSettingsLayout`
//  (pure, tested); the horizontal placement of a row's controls reads the panel layout's `columnLeft`/`cellW` so the column-aligned
//  halves and lane pairs line up with the grid. No explanatory text anywhere (§14). Device-owed: legibility at portrait-AUM.

import SwiftUI

// MARK: - §4 — the settings button

/// §4.2 — radius 6; closed #2A2D34 with a #AAB0BA sliders icon; open #DFE3EA with a #0D0F14 icon. No text. VoiceOver "Settings", a toggle.
struct EuclideousRibbonSettingsButton: View {
    let open: Bool
    let frame: CGRect
    let onTap: () -> Void
    var body: some View {
        let ink = open ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA)
        return RoundedRectangle(cornerRadius: EuclideousRibbonSettingsMetrics.buttonRadius)
            .fill(open ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34))
            .overlay(Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .regular)).foregroundColor(ink))
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(open ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - §5 — the settings tab

struct EuclideousRibbonSettingsTab: View {
    let box: CGSize
    let panel: EuclideousRiffPanelLayout
    let layout: EuclideousRibbonSettingsLayout
    let settings: RibbonSettings
    let laneAccents: [Color]
    let onSet: (RibbonSettings) -> Void

    private let pad = EuclideousRiffPanelMetrics.padding
    private var cellW: CGFloat { panel.cellW }
    private func colLeft(_ c: Int) -> CGFloat { panel.columnLeft(c) }
    /// A horizontal span covering columns `a…b` inclusive (1-based column pair / half).
    private func columnsSpan(_ a: Int, _ b: Int) -> (x: CGFloat, w: CGFloat) {
        let x = colLeft(a), r = colLeft(b) + cellW; return (x, r - x)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header("RIBBONS", y: layout.ribbonsHeaderY)
            touchRow
            releaseRow
            latchRow
            header("PARTS", y: layout.partsHeaderY)
            partRow(isNotes: false, y: layout.riffY)   // RIFF
            partRow(isNotes: true,  y: layout.stackY)  // STACK
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }

    // §5.3 — a full-width header: 6.5pt heavy, 0.16em tracking, #6E7480, a 0.5pt #26282E rule under the full width.
    private func header(_ title: String, y: CGFloat) -> some View {
        let fullW = box.width - pad * 2
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 6.5, weight: .heavy, design: .monospaced)).tracking(6.5 * 0.16).foregroundColor(Color(hex: 0x6E7480))
            Rectangle().fill(Color(hex: 0x26282E)).frame(width: fullW, height: 0.5)
        }
        .frame(width: fullW, height: layout.headerH, alignment: .topLeading)
        .position(x: pad + fullW / 2, y: y + layout.headerH / 2)
        .accessibilityHidden(true)
    }

    // §5.3 — a row label: 7.5pt heavy, #AAB0BA, right-aligned in the label column, 6pt right padding.
    private func rowLabel(_ title: String, y: CGFloat) -> some View {
        Text(title).font(.system(size: 7.5, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xAAB0BA))
            .frame(width: layout.labelW - 6, height: layout.rowH, alignment: .trailing)
            .position(x: layout.labelX + (layout.labelW - 6) / 2, y: y + layout.rowH / 2)
            .accessibilityHidden(true)
    }

    // §5.3 — an option tile / the RIFF·STACK toggle: radius 4.5; on #DFE3EA/#0D0F14, off #2A2D34/#AAB0BA; 8.5pt heavy, 0.06em tracking.
    private func optionTile(_ title: String, selected: Bool, rect: CGRect, axLabel: String, onTap: @escaping () -> Void) -> some View {
        let ink = selected ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA)
        return RoundedRectangle(cornerRadius: EuclideousRibbonSettingsMetrics.tileRadius)
            .fill(selected ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34))
            .overlay(Text(title).font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(8.5 * 0.06).foregroundColor(ink))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    // §5.3 — a lane tile: on, lane100 fill + #0D0F14 number; off, no fill + a 1pt inner lane100@40% ring + a lane100 number.
    // With the part toggle off, the four lane tiles draw at 35% and keep their own on/off states and stay tappable.
    private func laneTile(lane: Int, on: Bool, dimmed: Bool, rect: CGRect, axLabel: String, onTap: @escaping () -> Void) -> some View {
        let accent = laneAccents[lane % laneAccents.count]
        let r = EuclideousRibbonSettingsMetrics.tileRadius
        return ZStack {
            if on { RoundedRectangle(cornerRadius: r).fill(accent) }
            else  { RoundedRectangle(cornerRadius: r).strokeBorder(accent.opacity(0.40), lineWidth: 1) }
            Text("\(lane + 1)").font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .foregroundColor(on ? Color(hex: 0x0D0F14) : accent)
        }
        .frame(width: rect.width, height: rect.height)
        .opacity(dimmed ? EuclideousRibbonSettingsMetrics.partOffDim : 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axLabel)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    // TOUCH: SCRUB · TUTTI · LOOP, three tiles sharing the eight columns' width equally, 2pt apart (§5.2).
    private var touchRow: some View {
        let g: CGFloat = 2
        let tileW = (layout.controlsW - g * 2) / 3
        let modes: [(RibbonTouchMode, String)] = [(.scrub, "SCRUB"), (.tutti, "TUTTI"), (.loop, "LOOP")]
        return ZStack(alignment: .topLeading) {
            rowLabel("TOUCH", y: layout.touchY)
            ForEach(Array(modes.enumerated()), id: \.offset) { i, m in
                let x = layout.controlsX + CGFloat(i) * (tileW + g)
                optionTile(m.1, selected: settings.touchMode == m.0,
                           rect: CGRect(x: x, y: layout.touchY, width: tileW, height: layout.rowH),
                           axLabel: m.1.capitalized) { var ns = settings; ns.touchMode = m.0; onSet(ns) }
            }
        }
    }

    // RELEASE: SLIP (columns 1–4) · CONTINUE (columns 5–8) (§5.2).
    private var releaseRow: some View {
        let left = columnsSpan(0, 3), right = columnsSpan(4, 7)
        return ZStack(alignment: .topLeading) {
            rowLabel("RELEASE", y: layout.releaseY)
            optionTile("SLIP", selected: settings.release == .slip,
                       rect: CGRect(x: left.x, y: layout.releaseY, width: left.w, height: layout.rowH),
                       axLabel: "Slip") { var ns = settings; ns.release = .slip; onSet(ns) }
            optionTile("CONTINUE", selected: settings.release == .carryOn,
                       rect: CGRect(x: right.x, y: layout.releaseY, width: right.w, height: layout.rowH),
                       axLabel: "Continue") { var ns = settings; ns.release = .carryOn; onSet(ns) }
        }
    }

    // LATCH: OFF (columns 1–4) · ON (columns 5–8) (§5.2).
    private var latchRow: some View {
        let left = columnsSpan(0, 3), right = columnsSpan(4, 7)
        return ZStack(alignment: .topLeading) {
            rowLabel("LATCH", y: layout.latchY)
            optionTile("OFF", selected: !settings.latch,
                       rect: CGRect(x: left.x, y: layout.latchY, width: left.w, height: layout.rowH),
                       axLabel: "Latch off") { var ns = settings; ns.latch = false; onSet(ns) }
            optionTile("ON", selected: settings.latch,
                       rect: CGRect(x: right.x, y: layout.latchY, width: right.w, height: layout.rowH),
                       axLabel: "Latch on") { var ns = settings; ns.latch = true; onSet(ns) }
        }
    }

    // RIFF / STACK: the part toggle in the label column, then lanes 1–4 each two columns wide (§5.2).
    private func partRow(isNotes: Bool, y: CGFloat) -> some View {
        let partOn = isNotes ? settings.stackOn : settings.riffOn
        let laneMask = isNotes ? settings.stackLanes : settings.riffLanes
        let partName = isNotes ? "STACK" : "RIFF"
        return ZStack(alignment: .topLeading) {
            // The part toggle sits in the label column (an option tile, the full label width).
            optionTile(partName, selected: partOn,
                       rect: CGRect(x: layout.labelX, y: y, width: layout.labelW, height: layout.rowH),
                       axLabel: "\(partName), \(partOn ? "on" : "off")") {
                var ns = settings; if isNotes { ns.stackOn.toggle() } else { ns.riffOn.toggle() }; onSet(ns)
            }
            ForEach(0..<4, id: \.self) { lane in
                let span = columnsSpan(2 * lane, 2 * lane + 1)
                let on = (laneMask >> UInt8(lane)) & 1 == 1
                laneTile(lane: lane, on: on, dimmed: !partOn,
                         rect: CGRect(x: span.x, y: y, width: span.w, height: layout.rowH),
                         axLabel: "\(partName.capitalized) lane \(lane + 1), \(on ? "included" : "excluded")") {
                    var ns = settings
                    let bit = UInt8(1) << UInt8(lane)
                    if isNotes { ns.stackLanes ^= bit } else { ns.riffLanes ^= bit }
                    onSet(ns)
                }
            }
        }
    }
}
