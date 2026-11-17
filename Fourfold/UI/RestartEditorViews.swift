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
        // STYLE PASS 1 §3.2: on = the selected pair (knob in ink), off = the control tone (knob in the label grey), no
        // border (was lane@35 + lane border + lane knob / #2A2D34 + #3A3E47 + #7C828D).
        ZStack(alignment: on ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: height / 2).fill(Color(hex: FourfoldSelect.switchFill(on)))
            Circle().fill(Color(hex: on ? FourfoldStyle.selectedInk : FourfoldStyle.label)).frame(width: height - 4, height: height - 4).padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
    }
}

/// RESTARTS EDITOR V2 §2.2 — the FREE pill: a 40 × 24 pill, radius 12. LIT when the chain is inactive (its text #F2F4F7 on the lane colour at 30 %); dim #2A2D34 with #8A909A text when the chain is active. Tapping it toggles the chain on / off.
struct EuclideousFreePill: View {
    let free: Bool            // the chain is inactive (the pill is lit)
    let accent: Color
    var body: some View {
        // STYLE PASS 1 §3.2 (FREE pills named): lit = #DFE3EA/#0D0F14, off = control/#B4BAC4 (was lane@30/#F2F4F7 · #2A2D34/#8A909A).
        Text("FREE").font(heavyMono(8)).tracking(0.48).foregroundColor(Color(hex: FourfoldSelect.switchInk(free)))
            .frame(width: 40, height: 24)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: FourfoldSelect.switchFill(free))))
    }
}

/// RESETS TAB §1.5 — the WITH RHYTHM link row that divides a card's RHYTHM and MELODY halves: the link button (editor v2's own look — the `link` glyph, off #8A909A on #2A2D34 / on #F2F4F7 on lane@30 %; "source wins" over the spec's
/// "arrow.down" wording — the editor only drew `link`) in a wider x 0–40 hit area, and a tie line from x 42 to TW that lights when WITH RHYTHM is on. Never dims (§1.6). The line's off/on colours (#2F333B / lane100 at 60 %) are the card's own —
/// the page passes them in computed, so this view needs no colour helpers. The drawn pill sits leading in the hit frame; the whole thing is offset AFTER its tap target is formed (so the hit area moves with it — a recurring page bug if reversed).
struct EuclideousRestartLinkRow: View {
    let on: Bool
    let accent: Color          // the button's on-background (accent at 30 %)
    let lineOn: Color          // §1.5: lane100 at 60 %
    let lineOff: Color         // §1.5: #2F333B
    let button: CGRect         // the drawn pill (34 × 20, or 34 × 16 in case c)
    let hit: CGRect            // the hit area (x 0–40 by linkH)
    let line: CGRect           // draft 3 §3.4: x 42 → TW − 56
    let glyphSize: CGFloat     // 11 (full) or 9 (case c)
    let axLabel: String
    let onToggle: () -> Void
    // draft 3 §3: the lane's resolve count "N OF P" at the row's trailing end (never taps, never dims — §3.5).
    var countBox: CGRect = .zero
    var countForm: EuclideousResolveCountForm = .dash
    var countAX: String = ""
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: line.height / 2).fill(on ? lineOn : lineOff)
                .frame(width: line.width, height: line.height).offset(x: line.minX, y: line.minY)
                .accessibilityHidden(true)
            countView
                .frame(width: countBox.width, height: countBox.height, alignment: .trailing)
                .offset(x: countBox.minX, y: countBox.minY)
            HStack(spacing: 1) { Image(systemName: "link"); Image(systemName: "arrow.down") }   // RESETS V2 §3.7: editor v2 §2.7's two glyphs — link then arrow.down
                .font(.system(size: glyphSize, weight: .heavy))
                .foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0x8A909A))
                .frame(width: button.width, height: button.height)
                .background(RoundedRectangle(cornerRadius: button.height <= 16 ? 8 : 6).fill(on ? accent.opacity(0.3) : Color(hex: 0x2A2D34)))
                .frame(width: hit.width, height: hit.height, alignment: .leading)   // widen to the §1.5 hit area, pill leading + vertically centred
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }
                .offset(x: hit.minX, y: hit.minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(axLabel)
                .accessibilityAddTraits(.isButton).ringToggleTrait()
        }
    }
    /// §3.3: "N OF P" (N/P 11 pt, "OF" 7 pt 0.08 em #8A909A sp3), trailing-aligned and vertically centred; ">99" / "—" alone. #F2F4F7, or #8A909A when P is 1.
    @ViewBuilder private var countView: some View {
        let ink = Color(hex: 0xF2F4F7), grey = Color(hex: 0x8A909A)
        Group {
            switch countForm {
            case .dash: Text("\u{2014}").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(grey)
            case .over99: Text(">99").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(ink)
            case .np(let n, let p, let isGrey):
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(n)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(isGrey ? grey : ink)
                    Text("OF").font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(0.56).foregroundColor(grey)
                    Text("\(p)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(isGrey ? grey : ink)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore).accessibilityLabel(countAX)
    }
}

/// RESTARTS EDITOR V2 §3 — a count chip: a tap steps the value (wrapping 8 → 1), a vertical drag sets it live (6 pt to begin, 12 pt a step, one undo step), a long press (≥ 0.5 s, then lift) removes the link. The drag is a `highPriorityGesture` so it wins over
/// any gesture on a view behind it. The value redraws from the document as the drag writes it. (Gesture FEEL is device-owed — there is no macOS test reach.)
struct EuclideousCountChipView: View {
    let value: Int
    let frame: CGRect
    let accent: Color
    let dim: Double
    let hit: Bool
    let label: String
    let onDrag: (Int, Bool) -> Void      // (new value, firstUpdate — true opens a fresh undo step)
    let onRemove: () -> Void
    var progressFraction: Double? = nil  // RESETS V2 §3.6: the running link's chip draws a lane-colour progress bar (nil = not the running link / stopped / FREE)

    @State private var dragging = false
    @State private var startValue = 0
    @State private var pressStart: Date? = nil
    @State private var lastEmitted = Int.min
    /// §review follow-up: `@GestureState` returns to `false` when the drag ends OR is SYSTEM-CANCELLED (a call, an alert). `.onChange` below clears the transient `@State` on that edge, so a cancelled drag can never leave stale `startValue` /
    /// `dragging` that would mis-step the NEXT drag or fold it into a prior undo step (`onEnded` alone does not fire on a cancel).
    @GestureState private var gestureActive = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x121318)).offset(y: 1)   // the 1 pt drop edge peeking below
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x343841))
            Text("\(value)").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
            chevrons   // §4.7: up / down marks for the two tap halves
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .bottomLeading) {   // §3.6: the running link's progress bar — 2 tall, r1, from x 4, 3 above the bottom, width 0→36 by the span fraction
            if let f = progressFraction {
                RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: CGFloat(max(0, min(1, f))) * 36, height: 2).padding(.leading, 4).padding(.bottom, 3)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .updating($gestureActive) { _, state, _ in state = true }
                .onChanged { v in
                    if pressStart == nil { pressStart = Date(); startValue = value; dragging = false; lastEmitted = Int.min }
                    if abs(v.translation.height) >= 6 {
                        let nv = euclideousRestartCountChipDragValue(startValue: startValue, translationY: v.translation.height, hit: hit)
                        if nv != lastEmitted { onDrag(nv, !dragging); dragging = true; lastEmitted = nv }
                    }
                }
                .onEnded { v in
                    let held = (pressStart.map { Date().timeIntervalSince($0) } ?? 0) >= 0.5
                    if !dragging, abs(v.translation.height) < 6, abs(v.translation.width) < 6 {
                        if held { onRemove() }
                        else {   // §4.7: top half steps up, bottom half steps down, both clamped at the ladder's ends (no wrap); one undo step
                            let up = v.startLocation.y < frame.height / 2
                            let nv = euclideousRestartCountChipDragValue(startValue: value, translationY: up ? -12 : 12, hit: hit)
                            if nv != value { onDrag(nv, true) }
                        }
                    }
                    dragging = false; pressStart = nil; lastEmitted = Int.min
                }
        )
        .onChange(of: gestureActive) { active in if !active { dragging = false; pressStart = nil; lastEmitted = Int.min } }   // reset on end AND on a system cancel
        .offset(x: frame.minX, y: frame.minY)
        .opacity(dim)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (progressFraction != nil ? ", playing" : ""))   // RESETS V2 §4.2: the running link's chip says it is playing
        .accessibilityHint(EuclideousRestartEditorAX.linkHint)
        // §5: the adjustable action confers the adjustable trait in SwiftUI — VoiceOver swipes the value up / down one ladder step (clamped, no wrap)
        .accessibilityAdjustableAction { direction in
            let nv = euclideousRestartCountChipDragValue(startValue: value, translationY: direction == .increment ? -12 : 12, hit: hit)
            if nv != value { onDrag(nv, true) }
        }
        .accessibilityAction(named: EuclideousRestartEditorAX.removeLink) { onRemove() }
    }
    /// §4.7: a quiet up chevron 3 below the top and a down chevron 3 above the bottom (7 × 4, or 6 × 3 on a 24-tall chip), centred across the width, #8A909A, 1.3 pt. The value stays centred between them.
    @ViewBuilder private var chevrons: some View {
        let big = frame.height >= 28, cw: CGFloat = big ? 7 : 6, ch: CGFloat = big ? 4 : 3, edge: CGFloat = big ? 3 : 2
        let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round), c = Color(hex: 0x8A909A)
        ZStack {
            Path { p in p.move(to: CGPoint(x: 0, y: ch)); p.addLine(to: CGPoint(x: cw / 2, y: 0)); p.addLine(to: CGPoint(x: cw, y: ch)) }
                .stroke(c, style: stroke).frame(width: cw, height: ch).position(x: frame.width / 2, y: edge + ch / 2)
            Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: cw / 2, y: ch)); p.addLine(to: CGPoint(x: cw, y: 0)) }
                .stroke(c, style: stroke).frame(width: cw, height: ch).position(x: frame.width / 2, y: frame.height - edge - ch / 2)
        }
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(false)
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
    /// `newStep` true = a fresh undo checkpoint (a discrete tap, or the FIRST update of a drag); false = write into the step already open (a drag's later updates), so a whole drag is one undo step.
    let onEdit: (EuclideousRestartEdit, Bool) -> Void
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
            HStack(spacing: 1) { Image(systemName: "link"); Image(systemName: "arrow.down") }   // RESETS V2 §3.7: link then arrow.down
                .font(.system(size: 11, weight: .heavy)).foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0x8A909A))
                .frame(width: b.width, height: b.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.3) : Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture { onEdit(.withRhythm, true) }
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
    /// RESETS TAB §1.4: the card doesn't draw the RHYTHM / MELODY name — the tile above names the half. Defaults true (the overlay editor still draws it).
    var showsName: Bool = true
    let onEdit: (EuclideousRestartEdit, Bool) -> Void
    /// RESETS V2 §3.6: given a date, the chain's running link + the span fraction (nil = no bar: stopped / FREE / not this chain). nil closure ⇒ the count chips never animate (the overlay editor, the RHYTHM-tab surface).
    var runningBar: ((Date) -> (link: Int, fraction: Double)?)? = nil

    private var accent: Color { input.laneColors[input.lane % max(1, input.laneColors.count)] }
    private var chain: EuclideousRestartChain { rhythm ? settings.rhythm : settings.melody }
    private var active: Bool { rhythm ? settings.rhythmActive : settings.melodyActive }
    private var unitIndex: Int { rhythm ? [EuclideousRhythmRestartUnit.pass, .bar, .riff].firstIndex(of: settings.rhythmUnit) ?? 0 : [EuclideousMelodyRestartUnit.pass, .bar, .hit].firstIndex(of: settings.melodyUnit) ?? 0 }   // RESETS V2 §3.1: MELODY PASS·BAR·HIT
    private var unitWord: String { rhythm ? settings.rhythmUnit.word : settings.melodyUnit.word }
    private var isHitUnit: Bool { !rhythm && settings.melodyUnit == .hit }   // the link ladder is 1…8 for HIT, [1,2,3,4,6,8] otherwise
    private var readsSource: Bool { rhythm ? settings.rhythmUnit.readsSource : settings.melodyUnit.readsSource }
    private var sourceLane: Int { rhythm ? settings.rhythmSource : settings.melodySource }
    /// RESETS V2 §3.3: an inactive (FREE) chain dims its unit chips, source squares, count chips, + box and timeline to 60 % (a RESETS-local constant, NOT the shared lane-dim); the name stays full strength.
    private var dim: Double { active ? 1 : euclideousResetsFreeDim }
    /// §3.4: a linked MELODY with its chain inactive dims its FREE pill too (otherwise the pill is full strength). RHYTHM and an active melody keep the pill full.
    private var freePillDim: Double { (!rhythm && settings.withRhythm && !active) ? euclideousResetsFreeDim : 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsName { nameLabel }   // §1.4: the card names each half with its tile, not a label
            freePill
            ForEach(0..<3, id: \.self) { i in chip(i) }
            if readsSource { ForEach(0..<4, id: \.self) { i in sourceSquare(i) } }
            if let runningBar {   // §3.6: the running link's bar animates at 60 fps while the transport runs
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !input.running)) { tl in
                    let rb = runningBar(tl.date)
                    countChips(progressLink: rb?.link, fraction: rb?.fraction ?? 0)
                }
            } else {
                countChips(progressLink: nil, fraction: 0)
            }
            if chain.count < 4 { addBox }
            if chain.count >= 2 { minusBox }   // §4.8
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
            .opacity(freePillDim)   // §3.4: a linked MELODY with an inactive chain dims its FREE pill too (stays live)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.toggleOn(rhythm: rhythm), true) }
            .offset(x: r.minX, y: r.minY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.freePill(rhythm: rhythm, free: !active))
            .accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    /// The count chips (one per link); `progressLink` is the running link that carries the §3.6 bar (nil = none).
    private func countChips(progressLink: Int?, fraction: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(0..<max(0, chain.count)), id: \.self) { slot in
                EuclideousCountChipView(value: Int(chain.link(slot)), frame: frames.countChips[slot], accent: accent, dim: dim, hit: isHitUnit,
                                        label: EuclideousRestartEditorAX.link(rhythm: rhythm, slot: slot, value: Int(chain.link(slot)), unitWord: unitWord),
                                        onDrag: { v, first in onEdit(.setLink(rhythm: rhythm, slot: slot, value: v), first) },   // §4.7: the half-tap step and the drag both land on .setLink (one undo step, clamped, no wrap)
                                        onRemove: { if chain.count > 1 { onEdit(.removeLink(rhythm: rhythm, slot: slot), true) } },
                                        progressFraction: slot == progressLink ? fraction : nil)
            }
        }
    }
    private func chip(_ i: Int) -> some View {
        let names = rhythm ? ["PASS", "BAR", "RIFF"] : ["PASS", "BAR", "HIT"]   // RESETS V2 §3.1: MELODY PASS·BAR·HIT, so PASS and BAR line up in both halves
        let selected = unitIndex == i, r = frames.chips[i]
        let setSelected = selected && active   // §3.2: a SET row's selection keeps the lane tint; a FREE row's selection is OUTLINED, not tinted (no second-selection look)
        // STYLE PASS 1 §3.1 (was lane@30/#F2F4F7 · #2A2D34/#AAB0BA); the FREE-row selected outline below is a kept state stroke (§2.6).
        return Text(names[i]).font(heavyMono(8)).tracking(0.48).foregroundColor(Color(hex: FourfoldSelect.switchInk(setSelected)))
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: FourfoldSelect.switchFill(setSelected))))
            .overlay { if selected && !active { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x6A707A), lineWidth: 1) } }   // §3.2: FREE selected = #2A2D34 fill, #AAB0BA text, 1 pt #6A707A inner stroke
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.unit(rhythm: rhythm, index: i), true) }
            .offset(x: r.minX, y: r.minY)
            .opacity(dim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.unitChip(rhythm: rhythm, index: i))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    @ViewBuilder private func sourceSquare(_ i: Int) -> some View {
        let r = frames.sources[i]
        let unavailable = euclideousRestartSourceUnavailable(rhythm: rhythm, line: input.line, ownLane: input.lane, square: i)
        if unavailable {
            // §3.5: the unavailable own-lane square (RHYTHM PASS) isn't drawn — its slot stays empty and takes no taps.
            Color.clear.frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY).accessibilityHidden(true)
        } else {
            let selected = sourceLane == i
            let c = input.laneColors[i % max(1, input.laneColors.count)]
            ZStack {
                if selected { RoundedRectangle(cornerRadius: 2.5).fill(c).frame(width: 12, height: 12) }
                else { RoundedRectangle(cornerRadius: 2.5).strokeBorder(c.opacity(0.55), lineWidth: 1.5).frame(width: 12, height: 12) }
                Text("\(i + 1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(selected ? Color(hex: 0x0D0F14) : c)   // §3.5: the lane number, #0D0F14 on a selected square, lane100 on an unselected one
            }
            .frame(width: r.width, height: r.height)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.source(rhythm: rhythm, lane: i), true) }
            .offset(x: r.minX, y: r.minY)
            .opacity(dim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.source(square: i, unavailable: false))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }
    /// The add box — 28 × 28, shown only when there are fewer than four links.
    private var addBox: some View {
        let r = frames.addBox(count: chain.count) ?? .zero
        return Text("+").font(heavyMono(15)).foregroundColor(Color(hex: 0xAAB0BA))
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
            .contentShape(Rectangle())
            .onTapGesture { onEdit(.addLink(rhythm: rhythm), true) }
            .offset(x: r.minX, y: r.minY)
            .opacity(dim)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousRestartEditorAX.addLink(rhythm: rhythm))
            .accessibilityAddTraits(.isButton)
    }
    /// §4.8: the − box — 28 × 28 with the + box's looks, sp4 after the + box (or where + would be at four links); removes the LAST link (one undo step; `.removeLink`'s own guard never removes the only link). Shown only at 2+ links.
    @ViewBuilder private var minusBox: some View {
        if let r = frames.minusBox(count: chain.count) {
            Text("\u{2212}").font(heavyMono(15)).foregroundColor(Color(hex: 0xAAB0BA))
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture { onEdit(.removeLink(rhythm: rhythm, slot: chain.count - 1), true) }
                .offset(x: r.minX, y: r.minY)
                .opacity(dim)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rhythm ? "Remove the last rhythm link" : "Remove the last melody link")
                .accessibilityAddTraits(.isButton)
        }
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
