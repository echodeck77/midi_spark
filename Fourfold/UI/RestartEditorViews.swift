//  RestartEditorViews.swift — RESTART UNITS ferry (2026-11-04), slice D: the restart editor's views. They only PAINT what `RestartEditorUI.swift` computes (frames, texts, shades, VoiceOver strings) and hand each tap to the page
//  as an `EuclideousRestartEdit` (one undo step each, applied by `euclideousApplyRestartEdit`). Labels and values only — no instruction text anywhere. Positions are the pure frames', in the editor's own coordinates.

import SwiftUI

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// The row switch (ANSWER's pill, parameterised): a `width × height` pill, radius height / 2, a knob (height − 4) inset 2 from the end it sits at. On = the lane colour at 35 % with a 1 pt lane stroke and a lane-coloured knob; off = #2A2D34, a
/// 1 pt #3A3E47 stroke and a #7C828D knob. The ANSWER tab draws it at 26 × 14 (its look, unchanged); the restart editor at 34 × 20.
struct EuclideousRowSwitchPill: View {
    let on: Bool
    let accent: Color
    var width: CGFloat = 26
    var height: CGFloat = 14
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: height / 2).fill(on ? accent.opacity(0.35) : Color(hex: 0x2A2D34))
            RoundedRectangle(cornerRadius: height / 2).stroke(on ? accent : Color(hex: 0x3A3E47), lineWidth: 1)
            Circle().fill(on ? accent : Color(hex: 0x7C828D)).frame(width: height - 4, height: height - 4).padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
    }
}

/// VoiceOver focus targets: a section of the editor (focus goes to the tapped tile's section when it opens), or a tile (focus goes back to it when it closes).
enum EuclideousRestartFocus: Hashable {
    case section(rhythm: Bool)
    case tile(lane: Int, rhythm: Bool)
}

/// What the editor needs from the page.
struct EuclideousRestartEditorInput {
    /// Which tile opened the editor (focus returns to it, and goes to its section on open).
    var openedFromRhythm = true
    var lane: Int
    var line: EuclidLine
    var laneColors: [Color]
    var size: CGSize
    var scheduleSet: EuclideousRestartScheduleSet?
    var barBeats: Double
    /// The engine's musical beat at a date, and whether the lane is running (transport playing, lane on).
    var beatAt: (Date) -> Double
    var running: Bool
}

struct EuclideousRestartEditorView: View {
    let input: EuclideousRestartEditorInput
    let focus: AccessibilityFocusState<EuclideousRestartFocus?>.Binding
    let onEdit: (EuclideousRestartEdit) -> Void
    let onClose: () -> Void

    private var accent: Color { input.laneColors[input.lane % max(1, input.laneColors.count)] }
    private func lane20(_ c: Color) -> Color { c.opacity(0.2) }

    var body: some View {
        FourfoldStackProbe.note()
        let frames = euclideousRestartEditorFramesV2(size: input.size)
        let settings = euclideousRestartSettings(line: input.line, lane: input.lane)
        return ZStack(alignment: .topLeading) {
            header(frames)
            EuclideousRestartSectionView(input: input, focus: focus, frames: frames.rhythm, rhythm: true, settings: settings, showsTimeline: frames.showsTimelines, onEdit: onEdit)
            EuclideousRestartSectionView(input: input, focus: focus, frames: frames.melody, rhythm: false, settings: settings, showsTimeline: frames.showsTimelines, onEdit: onEdit)
        }
        .onAppear { let rhythm = input.openedFromRhythm; DispatchQueue.main.async { focus.wrappedValue = .section(rhythm: rhythm) } }
        .frame(width: input.size.width, height: input.size.height, alignment: .topLeading)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousRestartEditorAX.dialog(lane: input.lane))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
    }

    private func header(_ f: EuclideousRestartEditorFramesV2) -> some View {
        ZStack(alignment: .topLeading) {
            Text("RESTARTS").font(heavyMono(8)).tracking(0.48).foregroundColor(Color(hex: 0xAAB0BA))
                .padding(.leading, 4).frame(width: 160, height: f.header.height, alignment: .leading)
                .offset(x: f.header.minX, y: f.header.minY)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(hex: 0xAAB0BA))
                    .frame(width: 28, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                    .contentShape(Rectangle().path(in: CGRect(x: 0, y: -2, width: 28, height: 24)))   // the drawn 28 × 20, a 28 × 24 hit area
            }
            .offset(x: f.header.maxX - 28, y: f.header.minY)
            .accessibilityLabel(EuclideousRestartEditorAX.close)
        }
    }
}

/// One section (RHYTHM or MELODY): row 1 (name, unit chips, source squares, switch), row 2 (the WITH RHYTHM button, the four link slots), row 3 (the timeline).
struct EuclideousRestartSectionView: View {
    let input: EuclideousRestartEditorInput
    let focus: AccessibilityFocusState<EuclideousRestartFocus?>.Binding
    let frames: EuclideousRestartSectionFramesV2
    let rhythm: Bool
    let settings: EuclideousRestartSettings
    let showsTimeline: Bool
    let onEdit: (EuclideousRestartEdit) -> Void

    private var accent: Color { input.laneColors[input.lane % max(1, input.laneColors.count)] }
    private var chain: EuclideousRestartChain { rhythm ? settings.rhythm : settings.melody }
    private var isOn: Bool { rhythm ? settings.rhythmOn : settings.melodyOn }
    private var unitIndex: Int { rhythm ? [EuclideousRhythmRestartUnit.bar, .pass, .riff].firstIndex(of: settings.rhythmUnit) ?? 0 : [EuclideousMelodyRestartUnit.pass, .bar, .hit].firstIndex(of: settings.melodyUnit) ?? 0 }
    private var unitWord: String { rhythm ? settings.rhythmUnit.word : settings.melodyUnit.word }
    private var readsSource: Bool { rhythm ? settings.rhythmUnit.readsSource : settings.melodyUnit.readsSource }
    private var sourceLane: Int { rhythm ? settings.rhythmSource : settings.melodySource }
    /// §7.5: a switched-off row dims its link slots and timeline cells to the OFF-dim value; the chips, squares, switch and WITH RHYTHM stay full strength.
    private var rowDim: Double { isOn ? 1 : EuclideousLaneDimStyle.opacity }
    private func rect(_ r: CGRect) -> some View { Color.clear.frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            nameLabel
            ForEach(0..<3, id: \.self) { i in chip(i) }
            if readsSource { ForEach(0..<4, id: \.self) { i in sourceSquare(i) } }
            switchControl
            if !rhythm { withRhythmButton }
            ForEach(0..<4, id: \.self) { slot in linkSlot(slot) }
            if showsTimeline { timeline }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rhythm ? EuclideousRestartEditorAX.rhythmGroup : EuclideousRestartEditorAX.melodyGroup)
        .accessibilityFocused(focus, equals: .section(rhythm: rhythm))
    }

    private var nameLabel: some View {
        Text(rhythm ? "RHYTHM" : "MELODY").font(heavyMono(9)).tracking(0.9).foregroundColor(Color(hex: 0xF2F4F7))
            .padding(.leading, 4).frame(width: frames.labelColumn.width, height: frames.labelColumn.height, alignment: .leading)
            .offset(x: frames.labelColumn.minX, y: frames.labelColumn.minY)
            .accessibilityHidden(true)
    }
    private func chip(_ i: Int) -> some View {
        let names = rhythm ? ["BAR", "PASS", "RIFF"] : ["PASS", "BAR", "HIT"]
        let selected = unitIndex == i, r = frames.chips[i]
        return Text(names[i]).font(heavyMono(8)).tracking(0.48).foregroundColor(selected ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? accent.opacity(0.2) : Color(hex: 0x2A2D34)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.unit(rhythm: rhythm, index: i)) }
            .offset(x: r.minX, y: r.minY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.unitChip(rhythm: rhythm, index: i))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func sourceSquare(_ i: Int) -> some View {
        let r = frames.sources[i]
        let unavailable = euclideousRestartSourceUnavailable(rhythm: rhythm, line: input.line, ownLane: input.lane, square: i)
        let selected = !unavailable && sourceLane == i
        let c = input.laneColors[i % max(1, input.laneColors.count)]
        return ZStack {
            if unavailable {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color(hex: 0x3A3E47), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 12, height: 12)
            } else if selected {
                RoundedRectangle(cornerRadius: 2.5).fill(c).frame(width: 12, height: 12)
            } else {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(c.opacity(0.55), lineWidth: 1.5).frame(width: 12, height: 12)
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .onTapGesture { if !unavailable { onEdit(.source(rhythm: rhythm, lane: i)) } }
        .offset(x: r.minX, y: r.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousRestartEditorAX.source(square: i, unavailable: unavailable))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .opacity(unavailable ? 0.6 : 1)
    }
    private var switchControl: some View {
        let t = frames.switchTrack, h = frames.switchHit
        return ZStack { EuclideousRowSwitchPill(on: isOn, accent: accent, width: t.width, height: t.height) }
            .frame(width: h.width, height: h.height)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.toggleOn(rhythm: rhythm)) }
            .offset(x: h.minX, y: h.minY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.switchLabel(rhythm: rhythm, on: isOn))
            .accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    private var withRhythmButton: some View {
        let r = frames.withRhythm ?? .zero, on = settings.withRhythm
        return VStack(spacing: 3) {
            Image(systemName: "link").font(.system(size: 11, weight: .heavy))
            Text("RHYTHM").font(heavyMono(7)).tracking(0.56)
        }
        .foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0x8A909A))
        .frame(width: r.width, height: r.height)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.2) : Color(hex: 0x2A2D34)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onEdit(.withRhythm) }
        .offset(x: r.minX, y: r.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousRestartEditorAX.withRhythm(on: on))
        .accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    private func linkSlot(_ slot: Int) -> some View {
        let r = frames.slots[slot], count = chain.count
        return Group {
            if slot < count {
                let v = Int(chain.link(slot))
                Text("\(v)").font(heavyMono(15)).foregroundColor(Color(hex: 0xF2F4F7))
                    .frame(width: r.width, height: r.height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.2)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(.tapLink(rhythm: rhythm, slot: slot)) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EuclideousRestartEditorAX.link(rhythm: rhythm, slot: slot, value: v, unitWord: unitWord))
                    .accessibilityHint(EuclideousRestartEditorAX.linkHint)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: EuclideousRestartEditorAX.removeLink) { removeLink(slot) }
            } else if slot == count {
                Text("+").font(heavyMono(15)).foregroundColor(Color(hex: 0xAAB0BA))
                    .frame(width: r.width, height: r.height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(.addLink(rhythm: rhythm)) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EuclideousRestartEditorAX.addLink(rhythm: rhythm))
                    .accessibilityAddTraits(.isButton)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)).frame(width: r.width, height: r.height).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .opacity(rowDim)
        .offset(x: r.minX, y: r.minY)
    }
    /// VoiceOver's "Remove link": taps the link until it falls off the ladder (the same edits a sighted tap makes, one step each would be wrong — the removal is ONE action).
    private func removeLink(_ slot: Int) {
        let hit = !rhythm && settings.melodyUnit == .hit
        let steps = euclideousRestartLinkLadder(hit: hit).count
        for _ in 0..<steps { onEdit(.tapLink(rhythm: rhythm, slot: slot)); if Int(chain.link(slot)) == Int(euclideousRestartLinkLadder(hit: hit).last ?? 8) { break } }
    }

    // MARK: row 3 — the timeline (labels and cells; read-only)
    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !input.running)) { tl in
            let beat = input.beatAt(tl.date)
            let current = euclideousRestartCurrentUnit(rhythm: rhythm, settings: settings, ownLane: input.lane, beat: beat, barBeats: input.barBeats, set: input.scheduleSet)
            let t = euclideousRestartTimeline(chain: chain, active: rhythm ? settings.rhythmActive : settings.melodyActive, unitWord: unitWord, current: current, rhythm: rhythm)
            let colourLane = (rhythm ? settings.rhythmActive && settings.rhythmUnit.readsSource : settings.melodyActive && settings.melodyUnit.readsSource) ? sourceLane : input.lane
            let c = input.laneColors[colourLane % max(1, input.laneColors.count)]
            ZStack(alignment: .topLeading) {
                if let a = frames.axisLabel {
                    Text(t.axisLabel).font(heavyMono(7)).tracking(0.42).foregroundColor(Color(hex: 0x5C626C)).lineLimit(1).truncationMode(.tail)
                        .padding(.leading, 4).frame(width: a.width, height: a.height, alignment: .leading).offset(x: a.minX, y: a.minY)
                }
                ForEach(0..<min(frames.cells.count, t.cells.count), id: \.self) { i in
                    let r = frames.cells[i], cell = t.cells[i]
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3).fill(t.active ? c.opacity(cell.shadeHigh ? 0.26 : 0.12) : Color(hex: 0x2A2D34))
                        if t.active && cell.isMark { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 2.5, height: 10).offset(x: 1.5, y: 2) }
                        if input.running, t.currentCell == i { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0xF2F4F7).opacity(0.75), lineWidth: 1) }
                    }
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                }
            }
            .opacity(rowDim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t.spoken)
        }
    }
}
