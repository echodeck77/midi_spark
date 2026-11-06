//  RestartEditorViews.swift — RESTART UNITS ferry (2026-11-04), slice D; rebuilt by RESTARTS EDITOR V2 (2026-11-06) §2: the FREE pill replaces the on/off switch, a dedicated LINK ROW between the sections carries the melody's WITH RHYTHM, count
//  chips (only the real links) replace the four fixed link slots, and the timeline is brighter. The views only PAINT what `RestartEditorUI.swift` computes (frames, texts, shades, VoiceOver strings) and hand each tap to the page as an
//  `EuclideousRestartEdit` (one undo step each, applied by `euclideousApplyRestartEdit`). Labels and values only — no instruction text anywhere. Positions are the pure frames', in the editor's own coordinates.

import SwiftUI

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// The row switch (ANSWER's pill, parameterised): a `width × height` pill, radius height / 2, a knob (height − 4) inset 2 from the end it sits at. On = the lane colour at 35 % with a 1 pt lane stroke and a lane-coloured knob; off = #2A2D34, a
/// 1 pt #3A3E47 stroke and a #7C828D knob. The ANSWER tab draws it at 26 × 14. (The restart editor no longer uses it — RESTARTS EDITOR V2 replaced it with the FREE pill below.)
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

/// RESTARTS EDITOR V2 §2.2 — the FREE pill: a 40 × 24 pill, radius 12. LIT when the chain is inactive (its text #F2F4F7 on the lane colour at 30 %); dim #2A2D34 with #8A909A text when the chain is active. Tapping it toggles the chain on / off.
struct EuclideousFreePill: View {
    let free: Bool            // the chain is inactive (the pill is lit)
    let accent: Color
    var body: some View {
        Text("FREE").font(heavyMono(8)).tracking(0.48).foregroundColor(free ? Color(hex: 0xF2F4F7) : Color(hex: 0x8A909A))
            .frame(width: 40, height: 24)
            .background(RoundedRectangle(cornerRadius: 12).fill(free ? accent.opacity(0.3) : Color(hex: 0x2A2D34)))
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

    var body: some View {
        FourfoldStackProbe.note()
        let frames = euclideousRestartEditorFramesV2(size: input.size)
        let settings = euclideousRestartSettings(line: input.line, lane: input.lane)
        return ZStack(alignment: .topLeading) {
            header(frames)
            EuclideousRestartSectionView(input: input, focus: focus, frames: frames.rhythm, rhythm: true, settings: settings, showsTimeline: frames.showsTimelines, onEdit: onEdit)
            linkRow(frames, settings: settings)
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

    /// §2.2: the link row tying RHYTHM to MELODY — the WITH RHYTHM button in the label column, and a line across the right block that lights the lane colour when WITH RHYTHM is on. (The melody restarts with every rhythm loop.)
    private func linkRow(_ f: EuclideousRestartEditorFramesV2, settings: EuclideousRestartSettings) -> some View {
        let on = settings.withRhythm, b = f.linkButton, line = f.linkLine
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1).fill(on ? accent : Color(hex: 0x3A3E47)).frame(width: line.width, height: line.height).offset(x: line.minX, y: line.minY)
                .accessibilityHidden(true)
            Image(systemName: "link").font(.system(size: 11, weight: .heavy)).foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0x8A909A))
                .frame(width: b.width, height: b.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.3) : Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture { onEdit(.withRhythm) }
                .offset(x: b.minX, y: b.minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousRestartEditorAX.withRhythm(on: on))
                .accessibilityAddTraits(.isButton).ringToggleTrait()
        }
    }
}

/// One section (RHYTHM or MELODY): row 1 (FREE pill, unit chips, source squares), row 2 (the count chips + the add box), row 3 (the timeline).
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
    private var active: Bool { rhythm ? settings.rhythmActive : settings.melodyActive }
    private var unitIndex: Int { rhythm ? [EuclideousRhythmRestartUnit.pass, .bar, .riff].firstIndex(of: settings.rhythmUnit) ?? 0 : [EuclideousMelodyRestartUnit.hit, .pass, .bar].firstIndex(of: settings.melodyUnit) ?? 0 }
    private var unitWord: String { rhythm ? settings.rhythmUnit.word : settings.melodyUnit.word }
    private var readsSource: Bool { rhythm ? settings.rhythmUnit.readsSource : settings.melodyUnit.readsSource }
    private var sourceLane: Int { rhythm ? settings.rhythmSource : settings.melodySource }
    /// §2.2: an inactive (FREE) chain dims its unit chips, source squares, count chips, + box and timeline to 42 %; the FREE pill and name stay full strength.
    private var dim: Double { active ? 1 : EuclideousLaneDimStyle.opacity }

    var body: some View {
        ZStack(alignment: .topLeading) {
            nameLabel
            freePill
            ForEach(0..<3, id: \.self) { i in chip(i) }
            if readsSource { ForEach(0..<4, id: \.self) { i in sourceSquare(i) } }
            ForEach(Array(0..<max(0, chain.count)), id: \.self) { slot in countChip(slot) }
            if chain.count < 4 { addBox }
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
    /// The FREE pill — lit when the chain is inactive; a tap toggles the chain on / off (and appends a 1 when it was empty, §3). Full strength regardless of `dim`.
    private var freePill: some View {
        let r = frames.freePill
        return EuclideousFreePill(free: !active, accent: accent)
            .frame(width: r.width, height: r.height)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.toggleOn(rhythm: rhythm)) }
            .offset(x: r.minX, y: r.minY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.freePill(rhythm: rhythm, free: !active))
            .accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    private func chip(_ i: Int) -> some View {
        let names = rhythm ? ["PASS", "BAR", "RIFF"] : ["HIT", "PASS", "BAR"]   // §2.2 order
        let selected = unitIndex == i, r = frames.chips[i]
        return Text(names[i]).font(heavyMono(8)).tracking(0.48).foregroundColor(selected ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? accent.opacity(0.3) : Color(hex: 0x2A2D34)))   // §2.2: selected = lane colour @30 %, no outline
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.unit(rhythm: rhythm, index: i)) }
            .offset(x: r.minX, y: r.minY)
            .opacity(dim)
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
        .opacity(dim)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousRestartEditorAX.source(square: i, unavailable: unavailable))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .disabled(unavailable)   // VoiceOver reads "dimmed" (§9.2); the look is §7.4's dashed #3A3E47 stroke itself
    }
    /// A count chip — 44 × 28, radius 6, value 15 pt #F2F4F7 on a #343841 face over a 1 pt #121318 drop edge (offset y 1). A tap steps the value (§3's wrap / drag / long-press-remove arrive in the interaction slice).
    private func countChip(_ slot: Int) -> some View {
        let r = frames.countChips[slot], v = Int(chain.link(slot))
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x121318)).offset(y: 1)   // the drop edge peeking below
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x343841))
            Text("\(v)").font(heavyMono(15)).foregroundColor(Color(hex: 0xF2F4F7))
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(.tapLink(rhythm: rhythm, slot: slot)) }
        .offset(x: r.minX, y: r.minY)
        .opacity(dim)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousRestartEditorAX.link(rhythm: rhythm, slot: slot, value: v, unitWord: unitWord))
        .accessibilityHint(EuclideousRestartEditorAX.linkHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: EuclideousRestartEditorAX.removeLink) { onEdit(.removeLink(rhythm: rhythm, slot: slot)) }
    }
    /// The add box — 28 × 28, shown only when there are fewer than four links.
    private var addBox: some View {
        let r = frames.addBox(count: chain.count) ?? .zero
        return Text("+").font(heavyMono(15)).foregroundColor(Color(hex: 0xAAB0BA))
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.addLink(rhythm: rhythm)) }
            .offset(x: r.minX, y: r.minY)
            .opacity(dim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.addLink(rhythm: rhythm))
            .accessibilityAddTraits(.isButton)
    }

    // MARK: row 3 — the timeline (labels and cells; read-only)
    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !input.running)) { tl in
            let beat = input.beatAt(tl.date)
            let current = euclideousRestartCurrentUnit(rhythm: rhythm, settings: settings, ownLane: input.lane, beat: beat, barBeats: input.barBeats, set: input.scheduleSet)
            let t = euclideousRestartTimeline(chain: chain, active: active, unitWord: unitWord, current: current, rhythm: rhythm)
            let colourLane = (rhythm ? settings.rhythmActive && settings.rhythmUnit.readsSource : settings.melodyActive && settings.melodyUnit.readsSource) ? sourceLane : input.lane
            let c = input.laneColors[colourLane % max(1, input.laneColors.count)]
            ZStack(alignment: .topLeading) {
                if let a = frames.axisLabel {
                    Text(t.axisLabel).font(heavyMono(7)).tracking(0.42).foregroundColor(Color(hex: 0x5C626C)).lineLimit(1).truncationMode(.tail)
                        .padding(.leading, 4).frame(width: a.width, height: a.height, alignment: .leading).offset(x: a.minX, y: a.minY)
                        .accessibilityHidden(true)   // the timeline is ONE element (§9.2); its spoken label already says the window
                }
                ForEach(0..<min(frames.cells.count, t.cells.count), id: \.self) { i in
                    let r = frames.cells[i], cell = t.cells[i]
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3).fill(t.active ? c.opacity(cell.shadeHigh ? 0.34 : 0.16) : Color(hex: 0x2A2D34))   // §2.2 brighter
                        if t.active && cell.isMark { RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xF2F4F7)).frame(width: 2.5, height: 10).offset(x: 1.5, y: 2) }   // §2.2 white mark
                        if input.running, t.currentCell == i { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0xF2F4F7), lineWidth: 1) }   // §2.2 white 100 % ring
                    }
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                }
            }
            .opacity(dim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t.spoken)
        }
    }
}
