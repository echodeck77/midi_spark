//  EuclideousSettingsSheet.swift
//  "Fourfold settings (a gear, one sheet, three tabs)" (ferry 2026-10-15). A plain overlay on
//  EuclideousPage, the same presentation idiom as its key pop-up/chord grid — the engine never stops.
//  SwiftUI-only, a standalone View struct taking every callback it needs (no implicit page-global
//  access), same shape as CogPage/EuclidLaneBox.

import SwiftUI

/// §2.3: "one fixed height for all three tabs: the tallest tab's natural height at that width" — measured
/// live (not hand-derived as a text-wrap-aware formula, which would drift from real font metrics the first
/// time a description's wording changes) via a hidden copy of PORTS' own content, always rendered
/// off-screen regardless of which tab is actually showing. A disclosed implementation choice: §2.3's own
/// words ask for "one formula, like the header ladder," but the header ladder's own inputs are all fixed
/// numeric constants — these rows include wrapped prose, which a live measurement reproduces exactly and a
/// hand-rolled formula could only approximate.
private struct FFSHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
/// RATCH tab ferry (2026-10-28) §7.4: the CLOCK tab's natural height, measured only in DEBUG (the FX COUNTS block makes it as tall as the others, so the sheet must size to it or it would silently scroll).
private struct FFSClockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
/// SOURCES STACK ferry (2026-10-26) §6.3: the MIDI IN tab's natural height, measured only in DEBUG (the CLASHES
/// block makes it the tallest tab, so the sheet must size to it or it would silently scroll).
private struct FFSMidiInHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct EuclideousSettingsSheet: View {
    @Binding var tab: Int   // 0 MIDI IN · 1 PORTS · 2 CLOCK — owned by the caller so it persists in memory, not saved (§2.6)
    let containerW: CGFloat
    let containerH: CGFloat
    let headerBottomY: CGFloat
    let onCloseSheet: () -> Void

    // MIDI IN (§3)
    let midiInMask: UInt16
    let onSetMidiInMask: (UInt16) -> Void
    let ignoreAllNotesOff: Bool
    let onSetIgnoreAllNotesOff: (Bool) -> Void

    // PORTS (CARD BACKS, 2026-10-28 — the nine ports' eight steppers are four again): one channel per OUTPUT, A–D in order
    let busChannels: [Int]        // 1-based, one per output: A, B, C, D (index = output, `FourfoldPorts`)
    let allOutputName: String     // the REAL host-visible name for the "All" cable — NOT assumed "FOURFOLD ALL"
    let onSetBusChannel: (Int, Int) -> Void   // (output 0...3, new 1-based channel)
    let onAllNotesOff: () -> Void

    // CLOCK (§5)
    let hostStopBehavior: EuclideousHostStopBehavior
    let onSetHostStopBehavior: (EuclideousHostStopBehavior) -> Void
    /// false (the standalone Fourfold app, 2026-10-23): the app's own transport is the clock, so "when the host stops" has no meaning and the row is not shown.
    var showsHostStopBehavior: Bool = true

    // PULSE (ferry 2026-10-20, §7.1): a device-wide display preference — 0 OFF · 1 SUBTLE · 2 FULL — shown beside CLOCK's own row. Not in the document, no undo.
    let pulseLevel: Int
    let onSetPulseLevel: (Int) -> Void

    // SOURCES STACK ferry (2026-10-26) §6: CLASHES — a DEV-build-only rig setting (ALLOW/DROP, judged by ear).
    // The inputs are carried unconditionally; the control + the second height-measure below are `#if DEBUG`.
    let clashPolicy: ClashPolicy
    let onSetClashPolicy: (ClashPolicy) -> Void
    // RATCH tab ferry (2026-10-28) §7: FX COUNTS — a DEV-build-only rig setting (HITS · STEPS, judged by ear), on the CLOCK tab. Carried unconditionally; the control + the third height measure are `#if DEBUG`.
    let fxCounts: FxCountsMode
    let onSetFxCounts: (FxCountsMode) -> Void

    @State private var portsNaturalHeight: CGFloat = 0
    @State private var midiInNaturalHeight: CGFloat = 0   // §6.3: measured only in DEBUG (the CLASHES block makes MIDI IN the tallest tab)
    @State private var clockNaturalHeight: CGFloat = 0    // RATCH tab §7.4: measured only in DEBUG (the FX COUNTS block grows CLOCK)
    @State private var allNotesOffSentAt: Date? = nil

    private let laneColours = EuclideousRingPalette.laneMark

    var body: some View {
        let cardW = euclideousSettingsSheetWidth(containerW: containerW)
        let fixedChrome: CGFloat = 44 + 8 + 36 + 8 + 16 + 8 /* title+gap+tabs+gap+footer+gap-before-footer */ + 16 /* card padding ×2, sp8 each side */
        // §6.3: PORTS is normally the tallest tab, but in DEBUG the CLASHES block makes MIDI IN taller — size to the max.
        #if DEBUG
        let desired = max(1, max(portsNaturalHeight, max(midiInNaturalHeight, clockNaturalHeight))) + fixedChrome
        #else
        let desired = max(1, portsNaturalHeight) + fixedChrome
        #endif
        let available = max(1, containerH - headerBottomY - 16)
        let cardH = min(desired, available)

        return ZStack(alignment: .topTrailing) {
            Color(hex: 0x0C0E12).opacity(0.58)
                .frame(width: containerW, height: max(0, containerH - headerBottomY))
                .offset(y: headerBottomY)
                .contentShape(Rectangle())
                .onTapGesture { onCloseSheet() }
                .accessibilityHidden(true)

            card(width: cardW, height: cardH)
                .offset(y: headerBottomY + 8)
                .background(
                    // Hidden PORTS measurement — always rendered, never shown, drives the ONE fixed height.
                    portsTabContent(measuring: true)
                        .frame(width: cardW - 16, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: FFSHeightKey.self, value: g.size.height) })
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                )
                .onPreferenceChange(FFSHeightKey.self) { portsNaturalHeight = $0 }
                #if DEBUG
                .background(   // §6.3: the DEBUG-only second measure — MIDI IN (with its CLASHES block) is now the tallest tab
                    midiInTabContent
                        .frame(width: cardW - 16, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: FFSMidiInHeightKey.self, value: g.size.height) })
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                )
                .onPreferenceChange(FFSMidiInHeightKey.self) { midiInNaturalHeight = $0 }
                .background(   // RATCH tab §7.4: the DEBUG-only third measure — CLOCK with its FX COUNTS block
                    clockTabContent
                        .frame(width: cardW - 16, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: FFSClockHeightKey.self, value: g.size.height) })
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                )
                .onPreferenceChange(FFSClockHeightKey.self) { clockNaturalHeight = $0 }
                #endif
        }
    }

    private func card(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            titleRow
            tabRow
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tab {
                    case 0: midiInTabContent
                    case 1: portsTabContent(measuring: false)
                    default: clockTabContent
                    }
                }
            }
            .frame(maxHeight: .infinity)
            footerRow
        }
        .padding(8)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1B1D23)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 16)
        // `.contain` makes the card ONE labelled group around its children; without it SwiftUI stamps "Settings" over every child's own label (the tabs, the close button, the scroll view all read "Settings").
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Title row (§2.5)

    private var titleRow: some View {
        HStack {
            Text("SETTINGS").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.16 * 11)
                .foregroundColor(Color(hex: 0xF2F4F7))
            Spacer()
            Image(systemName: "xmark").font(.system(size: 18, weight: .regular)).foregroundColor(Color(hex: 0x8A909A))
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { onCloseSheet() }
                .accessibilityLabel("Close settings").accessibilityAddTraits(.isButton)
        }
        .padding(.leading, 8)
        .frame(height: 44)
    }

    // MARK: - Tab row (§2.6)

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                let selected = tab == i
                let name = ["MIDI IN", "PORTS", "CLOCK"][i]
                VStack(spacing: 0) {
                    Text(name).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.08 * 11)
                        .foregroundColor(selected ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(selected ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { tab = i }
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(name)
            }
        }
        .frame(height: 36)
    }

    // MARK: - Shared block/control chrome (§2.7/§2.8)

    private func block<Content: View>(name: String, value: String? = nil, description: String? = nil, @ViewBuilder control: () -> Content) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(name).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.14 * 9)
                    .foregroundColor(Color(hex: 0x8A909A))
                if let value {
                    Spacer()
                    Text(value).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.06 * 11)
                        .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(height: 16)
            control()
            if let description {   // SOURCES STACK §6.2: the DEBUG CLASHES block passes none — no description line
                Text(description).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: 0xAAB0BA)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
    }

    /// §2.8: the header source control's own segmented shape — container 32 tall #2A2D34 radius 8 sp4 inset;
    /// segments 24 tall radius 6 fixed widths; selected #DFE3EA/ink, unselected no-fill/#AAB0BA. Leading-
    /// aligned, never stretched.
    private func segmented(_ items: [(label: String, width: CGFloat)], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let sel = selected == i
                Text(items[i].label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.06 * 10)
                    .foregroundColor(sel ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                    .frame(width: items[i].width, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Color(hex: 0xDFE3EA) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(i) }
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2A2D34)))
    }

    // MARK: - MIDI IN tab (§3)

    private var midiInTabContent: some View {
        VStack(spacing: 8) {
            block(name: "LISTEN ON", value: euclideousListenOnValueLabel(mask: midiInMask),
                  description: "MIDI IN plays notes from these channels.") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        let allOn = euclideousListenOnAllIsLit(midiInMask)
                        Text("ALL").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.06 * 10)
                            .foregroundColor(allOn ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                            .frame(width: 44, height: 68)
                            .background(RoundedRectangle(cornerRadius: 6).fill(allOn ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                            .contentShape(Rectangle())
                            .onTapGesture { onSetMidiInMask(euclideousListenOnAfterAllTap()) }
                            .accessibilityLabel("All channels").accessibilityAddTraits(.isButton).accessibilityAddTraits(allOn ? .isSelected : [])
                        channelGrid
                    }
                }
            }
            block(name: "ALL-NOTES-OFF", description: "Some apps send all-notes-off between chords. IGNORE keeps your chord; real note-offs still work.") {
                segmented([("IGNORE", 64), ("OBEY", 48)], selected: ignoreAllNotesOff ? 0 : 1) { i in
                    onSetIgnoreAllNotesOff(i == 0)
                }
            }
            #if DEBUG
            // SOURCES STACK ferry (2026-10-26) §6: dev-only CLASHES — ALLOW keeps every stacked note, DROP thins a
            // lower layer's note a semitone from a higher layer's. No description line (§6.2 overrides §2.7 here).
            block(name: "CLASHES") {
                segmented([("ALLOW", 56), ("DROP", 48)], selected: clashPolicy == .allow ? 0 : 1) { i in
                    onSetClashPolicy(i == 0 ? .allow : .drop)
                }
            }
            #endif
        }
    }
    private var channelGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(1...8, id: \.self) { col in
                        let ch = row * 8 + col
                        let lit = euclideousListenOnChannelIsLit(mask: midiInMask, channel1based: ch)
                        Text("\(ch)").font(.system(size: 11, weight: .heavy, design: .monospaced)).monospacedDigit()
                            .foregroundColor(lit ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(lit ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                            .contentShape(Rectangle())
                            .onTapGesture { onSetMidiInMask(euclideousListenOnAfterChannelTap(mask: midiInMask, channel1based: ch)) }
                            .accessibilityLabel("Channel \(ch)").accessibilityAddTraits(.isButton).accessibilityAddTraits(lit ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: - PORTS tab (CARD BACKS, 2026-10-28: one channel stepper per output A–D)

    private func portsTabContent(measuring: Bool) -> some View {
        VStack(spacing: 8) {
            block(name: "CHANNELS", description: "Each output stamps its notes with its own channel. \(allOutputName.uppercased()) carries all four together, told apart by these.") {
                VStack(spacing: 4) {
                    ForEach(euclideousPortsTabRows(), id: \.lane) { row in
                        portsLaneRow(row, interactive: !measuring)
                    }
                }
            }
            block(name: "STUCK NOTES", value: (allNotesOffSentAt.map { Date().timeIntervalSince($0) < 0.9 } ?? false) ? "SENT" : nil,
                  description: "Ends every note Fourfold is sounding.") {
                let sent = allNotesOffSentAt.map { Date().timeIntervalSince($0) < 0.9 } ?? false
                Text("ALL NOTES OFF").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.06 * 10)
                    .foregroundColor(sent ? Color(hex: 0x0D0F14) : Color(hex: 0xF2F4F7))
                    .frame(height: 32).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 8).fill(sent ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard measuring == false else { return }
                        onAllNotesOff()
                        withAnimation(.easeInOut(duration: 0.15)) { allNotesOffSentAt = Date() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            withAnimation(.easeInOut(duration: 0.15)) { allNotesOffSentAt = nil }
                        }
                    }
                    .accessibilityLabel("All notes off")
            }
        }
    }
    /// One output's row: its letter in the lane colour, then its channel stepper.
    private func portsLaneRow(_ row: EuclideousPortsTabRow, interactive: Bool) -> some View {
        let letter = Text(row.letter).font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundColor(row.lane < laneColours.count ? laneColours[row.lane] : Color(hex: 0xF2F4F7))
            .frame(width: EuclideousPortsRowMetrics.letterW)
            .accessibilityHidden(true)
        return HStack(spacing: EuclideousPortsRowMetrics.gap) {
            letter
            ForEach(row.ports, id: \.bus) { port in portsStepper(port, interactive: interactive) }
        }
        .frame(height: 32)
    }
    private func portsStepper(_ port: EuclideousPortsTabPort, interactive: Bool) -> some View {
        let ch = port.bus < busChannels.count ? busChannels[port.bus] : port.bus + 1
        let atMin = ch <= 1, atMax = ch >= 16
        return HStack(spacing: 4) {
            Text(port.label).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.14 * 9)
                .foregroundColor(Color(hex: 0x8A909A)).lineLimit(1)
                .frame(width: 36, alignment: .leading)
            HStack(spacing: 0) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                    .foregroundColor(Color(hex: 0xAAB0BA)).opacity(atMin ? 0.4 : 1)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
                    .onTapGesture { if interactive, !atMin { onSetBusChannel(port.bus, ch - 1) } }
                    .accessibilityLabel("Decrease channel")
                Text("\(ch)").font(.system(size: 12, weight: .heavy, design: .monospaced)).monospacedDigit()
                    .foregroundColor(Color(hex: 0xF2F4F7)).frame(width: 20)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy))
                    .foregroundColor(Color(hex: 0xAAB0BA)).opacity(atMax ? 0.4 : 1)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
                    .onTapGesture { if interactive, !atMax { onSetBusChannel(port.bus, ch + 1) } }
                    .accessibilityLabel("Increase channel")
            }
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2A2D34)))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(euclideousPortChannelAccessibilityLabel(bus: port.bus, channel: ch))
    }

    // MARK: - CLOCK tab (§5)

    private var clockTabContent: some View {
        VStack(spacing: 8) {
            if showsHostStopBehavior {
                block(name: "WHEN THE HOST STOPS",
                      description: "KEEP PLAYING runs Fourfold on its own clock while the host is stopped. STOP waits for the host.") {
                    segmented([("KEEP PLAYING", 104), ("STOP", 48)], selected: hostStopBehavior == .keepPlaying ? 0 : 1) { i in
                        onSetHostStopBehavior(i == 0 ? .keepPlaying : .stop)
                    }
                }
            }
            #if DEBUG
            // RATCH tab ferry (2026-10-28) §7: dev-only FX COUNTS — what an output's ratchet counts: HITS (the emitter hits that leave on the output) or STEPS (the striking lane's pattern step). No value, no description line.
            block(name: "FX COUNTS") {
                segmented([("HITS", 48), ("STEPS", 56)], selected: fxCounts == .hits ? 0 : 1) { i in
                    onSetFxCounts(i == 0 ? .hits : .steps)
                }
                // §8.5: ONE element, "FX counts", its selected state as the value; a swipe up / down flips it
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("FX counts")
                .accessibilityValue(fxCounts == .hits ? "HITS" : "STEPS")
                .accessibilityAddTraits(.isButton)
                .accessibilityAdjustableAction { _ in onSetFxCounts(fxCounts == .hits ? .steps : .hits) }
            }
            #endif
            // PULSE §7.1: how strongly a strike shows on the comet bars, riff arrows and MIX pads. OFF shows none (gaps still draw); SUBTLE is 60%. Reduce Motion is honoured on top of this.
            block(name: "STRIKE PULSE",
                  description: "How strongly each strike shows, by how hard it played. OFF shows none; SUBTLE is softer. Reduce Motion also turns off dips, swells, tails and ripples.") {
                segmented([("OFF", 48), ("SUBTLE", 64), ("FULL", 56)], selected: max(0, min(2, pulseLevel))) { i in onSetPulseLevel(i) }
            }
        }
    }

    // MARK: - Footer (§2.9/§7.1)

    private var footerRow: some View {
        HStack {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Text("FOURFOLD \(v) (\(b))").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.14 * 9)
                .foregroundColor(Color(hex: 0x8A909A))
            Spacer()
        }
        .padding(.leading, 8)
        .frame(height: 16)
    }
}
