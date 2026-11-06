//  HarmonyPage.swift — INPUTS + HARMONY ferry (2026-11-06) §4–§7: the HARMONY page, a full-size page over the four lane cards. It replaces the SOURCES panel and the CHORDS page: the key (a large title, twelve root keys, one row of scales),
//  CHORDS (both grids side by side, each with a summary pill whose popover holds ADVANCE and RESTART) and a bottom band with PICK and MIDI IN. Every frame comes from `euclideousHarmonyLayout` (HarmonyLayout.swift); every setter is the one the
//  SOURCES panel / CHORDS page used (the page hands them in), so each edit is one undo step exactly as before. Opening or closing the page, a popover and the CHORDS · COLOUR switch are UI state: no undo step.
//  Several small leaf functions return AnyView (like the rest of the page): the extension's 1 MB main-thread stack.

import SwiftUI
import UIKit

enum EuclideousHarmonyPopover: Equatable { case none, pill(Int), pick }

private extension Color {
    init(h: UInt32) { self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1) }
}
private func mono(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .monospaced) }

/// The frames of the two summary pills and the EDIT button in the page's coordinates, so one tap catcher can let those three through while a popover is open (a tap on the other pill opens THAT popover, a tap on EDIT opens the PICK editor).
private struct HarmonyAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
private extension View {
    func harmonyAnchor(_ id: String, space: String) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: HarmonyAnchorKey.self, value: [id: g.frame(in: .named(space))]) })
    }
}

struct EuclideousHarmonyPage: View {
    let size: CGSize                         // the lane cards' block
    let keyRoot: Int
    let keyType: ScaleType
    let plan: SourcePlan
    let heldNotes: [UInt8]                   // MIDI IN's held notes (lane-1 status feed), ascending
    let midiPlaying: Bool
    let lines: [EuclidLine]
    let chordSets: [MachineParams]
    let laneHex: [UInt32]                    // lane100 of lanes 1–4
    let playing: Bool
    let playingColumn: (Int, Double) -> Int  // (grid, beat) → the column the grid is on (the engine's `chordColumn`)
    let beatAt: (Date) -> Double
    @Binding var rows: EuclideousHarmonyRows
    @Binding var popover: EuclideousHarmonyPopover
    @Binding var pickOctave: Int
    let onSetKeyRoot: (Int) -> Void
    let onSetKeyType: (ScaleType) -> Void
    let onEditChordSet: (Int, @escaping (inout MachineParams) -> Void) -> Void
    let onSetPlan: (SourcePlan) -> Void
    let onClose: () -> Void

    private static let space = "euclideousHarmonyPage"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchors: [String: CGRect] = [:]
    private var L: EuclideousHarmonyLayout { euclideousHarmonyLayout(block: size, scaleCount: ScaleType.allCases.count) }
    private var rootPc: Int { ((keyRoot % 12) + 12) % 12 }
    private var minorKey: Bool { euclideousScaleIsMinor(keyType.intervals) }
    private var flat: Bool { euclideousKeyIsFlat(rootPc, scaleType: keyType) }

    var body: some View {
        let L = self.L
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(h: 0x1A1C21))
                .overlay(RoundedRectangle(cornerRadius: 12).inset(by: 0.5).stroke(Color(h: 0x2E3138), lineWidth: 1))   // 4.1
            ZStack(alignment: .topLeading) {
                titleRow(L)
                rootRow(L)
                scaleRows(L)
                chordsHeading(L)
                column(0, L)
                column(1, L)
                pickStrip(L)
                midiStrip(L)
            }
            .frame(width: L.content.width, height: L.content.height, alignment: .topLeading)
            .offset(x: L.content.minX, y: L.content.minY)
            if popover != .none { catcher }
            popoverView(L)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: popover)   // 5.9: a 120 ms fade, none with Reduce Motion
        .onPreferenceChange(HarmonyAnchorKey.self) { anchors = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Harmony")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if popover != .none { popover = .none } else { onClose() } }
        .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    // MARK: the tap catcher (5.9): a tap outside the popover closes it; a tap on a pill or on EDIT does what that control does
    private var catcher: some View {
        Color.clear.contentShape(Rectangle())
            .frame(width: size.width, height: size.height)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onEnded { v in
                if let p = anchors["pill0"], p.contains(v.location) { togglePill(0) }
                else if let p = anchors["pill1"], p.contains(v.location) { togglePill(1) }
                else if let e = anchors["edit"], e.contains(v.location) { togglePick() }
                else { popover = .none }
            })
            .accessibilityHidden(true)
    }
    private func togglePill(_ set: Int) { popover = popover == .pill(set) ? .none : .pill(set) }
    private func togglePick() {
        if popover == .pick { popover = .none; return }
        pickOctave = euclideousPickEditorDefaultOctave(plan.pickNotesR)   // 1.6: the shown octave starts on the lowest picked note's, else middle C
        popover = .pick
    }

    // MARK: 5.1 title row
    private func titleRow(_ L: EuclideousHarmonyLayout) -> some View {
        HStack(spacing: 0) {
            Text(euclideousKeyLabel(root: keyRoot, type: keyType)).font(mono(24)).tracking(0.02 * 24)
                .foregroundColor(Color(h: 0xF2F4F7)).lineLimit(1).truncationMode(.tail)
                .accessibilityAddTraits(.isHeader).accessibilityLabel("Key, " + euclideousKeySpokenName(root: keyRoot, type: keyType))
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(Color(h: 0xAAB0BA))
                    .frame(width: EuclideousHarmonyMetrics.closeSize, height: EuclideousHarmonyMetrics.closeSize)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(h: 0x2A2D34)))
                    .frame(width: EuclideousHarmonyMetrics.closeTarget, height: EuclideousHarmonyMetrics.closeTarget)
            }
            .buttonStyle(.plain).accessibilityLabel("Close harmony")
        }
        .frame(width: L.titleRow.width, height: L.titleRow.height).offset(x: L.titleRow.minX, y: L.titleRow.minY)
        .accessibilitySortPriority(100)
    }

    // MARK: 5.2 root keys
    private static let noteNames = ["C", "C\u{266F}", "D", "D\u{266F}", "E", "F", "F\u{266F}", "G", "G\u{266F}", "A", "A\u{266F}", "B"]
    private static let isSharp = [false, true, false, true, false, false, true, false, true, false, true, false]
    private func rootRow(_ L: EuclideousHarmonyLayout) -> some View {
        HStack(spacing: EuclideousHarmonyMetrics.rootKeyGap) {
            ForEach(0..<12, id: \.self) { pc in rootKey(pc, width: L.rootKeyW) }
        }
        .frame(width: L.rootRow.width, height: L.rootRow.height, alignment: .leading).offset(x: L.rootRow.minX, y: L.rootRow.minY)
        .accessibilityElement(children: .contain).accessibilitySortPriority(90)
    }
    private func rootKey(_ pc: Int, width: CGFloat) -> some View {
        let selected = pc == rootPc
        let sharp = Self.isSharp[pc]
        let inScale = keyType.intervals.contains(((pc - rootPc) + 12) % 12)
        let fill = selected ? Color(h: 0xF2F4F7) : (sharp ? Color(h: 0x1B1D23) : Color(h: 0x2E3138))
        let ink = selected ? Color(h: 0x0D0F14) : (sharp ? Color(h: 0xAAB0BA) : Color(h: 0xF2F4F7))
        return ZStack {
            RoundedRectangle(cornerRadius: EuclideousHarmonyMetrics.rootRadius).fill(fill)
            if sharp && !selected { RoundedRectangle(cornerRadius: EuclideousHarmonyMetrics.rootRadius).inset(by: 0.5).stroke(Color(h: 0x2E3138), lineWidth: 1) }
            VStack(spacing: 0) {
                Group {
                    if selected { Circle().fill(Color(h: 0x0D0F14)) }
                    else if inScale { Circle().fill(Color(h: EuclideousSourceColour.key.fill)) }
                    else { Color.clear }
                }
                .frame(width: 5, height: 5).padding(.top, 9)
                Spacer(minLength: 0)
                Text(Self.noteNames[pc]).font(mono(13)).foregroundColor(ink).padding(.bottom, 8)
            }
        }
        .frame(width: width, height: EuclideousHarmonyMetrics.rootH)
        .contentShape(Rectangle()).onTapGesture { onSetKeyRoot(pc) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.noteNames[pc] + (inScale && !selected ? ", in scale" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 5.3 scales (one row; two when a chip would be under 44 wide)
    private func scaleRows(_ L: EuclideousHarmonyLayout) -> some View {
        let all = ScaleType.allCases
        return VStack(alignment: .leading, spacing: EuclideousHarmonyMetrics.scaleChipGap) {
            ForEach(0..<L.scaleRows.count, id: \.self) { r in
                HStack(spacing: EuclideousHarmonyMetrics.scaleChipGap) {
                    ForEach(0..<L.scalePerRow, id: \.self) { c in
                        let i = r * L.scalePerRow + c
                        if i < all.count { scaleChip(all[i], width: L.scaleChipW) }
                    }
                }
                .frame(height: EuclideousHarmonyMetrics.scaleH, alignment: .leading)
            }
        }
        .frame(width: L.content.width, alignment: .leading)
        .offset(x: L.scaleRows[0].minX, y: L.scaleRows[0].minY)
        .accessibilityElement(children: .contain).accessibilitySortPriority(80)
    }
    private func scaleChip(_ t: ScaleType, width: CGFloat) -> some View {
        let selected = keyType == t
        return Text(t.label).font(mono(7.5)).tracking(0.02 * 7.5).lineLimit(1).truncationMode(.tail)
            .foregroundColor(selected ? Color(h: 0x0D0F14) : Color(h: 0xAAB0BA))
            .padding(.horizontal, 2)
            .frame(width: width, height: EuclideousHarmonyMetrics.scaleH)
            .background(RoundedRectangle(cornerRadius: EuclideousHarmonyMetrics.scaleRadius).fill(selected ? Color(h: 0xDFE3EA) : Color(h: 0x24262C)))
            .contentShape(Rectangle()).onTapGesture { onSetKeyType(t) }
            .accessibilityElement(children: .ignore).accessibilityLabel(t.label)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 5.4 the CHORDS heading and the CHORDS · COLOUR switch
    private func chordsHeading(_ L: EuclideousHarmonyLayout) -> some View {
        HStack(spacing: 0) {
            Text("CHORDS").font(mono(9)).tracking(0.14 * 9).foregroundColor(Color(h: 0x8A909A)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            twoSegment([(EuclideousHarmonyRows.chords.label, EuclideousHarmonyRows.chords.spoken, rows == .chords), (EuclideousHarmonyRows.colour.label, EuclideousHarmonyRows.colour.spoken, rows == .colour)]) { i in
                rows = i == 0 ? .chords : .colour
            }
        }
        .frame(width: L.chordsHeading.width, height: L.chordsHeading.height).offset(x: L.chordsHeading.minX, y: L.chordsHeading.minY)
        .accessibilityElement(children: .contain).accessibilitySortPriority(70)
    }
    /// The two-segment switch of 5.4 (also OCTAVES' IGNORE · KEEP, 5.10): container #22252C radius 6, 2 inset, 2 between; segments padding 0 10, radius 4, 8 pt heavy 0.06 em; selected #DFE3EA with ink #0D0F14, the other #AAB0BA.
    private func twoSegment(_ segs: [(label: String, spoken: String, selected: Bool)], tap: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segs.count, id: \.self) { i in
                let s = segs[i]
                Text(s.label).font(mono(8)).tracking(0.06 * 8).lineLimit(1)
                    .foregroundColor(s.selected ? Color(h: 0x0D0F14) : Color(h: 0xAAB0BA))
                    .padding(.horizontal, 10).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(s.selected ? Color(h: 0xDFE3EA) : Color.clear))
                    .contentShape(Rectangle()).onTapGesture { tap(i) }
                    .accessibilityElement(children: .ignore).accessibilityLabel(s.spoken)
                    .accessibilityAddTraits(s.selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 6).fill(Color(h: 0x22252C)))
    }

    // MARK: 5.5 a grid column: title row, step strip, grid
    private func column(_ set: Int, _ L: EuclideousHarmonyLayout) -> some View {
        let cfg = chordSets[min(set, max(0, chordSets.count - 1))]
        let steps = cfg.chordsStepsResolved
        let col = set == 0 ? L.column0 : L.column1
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { tl in
            let pc = playingColumn(set, beatAt(tl.date))   // stopped: the column the next play would start on (the beat is frozen at the anchor)
            ZStack(alignment: .topLeading) {
                gridTitleRow(set, cfg: cfg, steps: steps, L: L).offset(y: L.gridTitleY)
                stepStrip(steps: steps, playing: pc, L: L).offset(y: L.stripY)
                grid(set, cfg: cfg, steps: steps, playing: playing ? pc : -1, L: L).offset(y: L.gridY)
            }
            .frame(width: L.columnW, height: col.height, alignment: .topLeading)
        }
        .frame(width: L.columnW, height: col.height, alignment: .topLeading)
        .offset(x: col.minX, y: col.minY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid \(set + 1), \(lanesSpoken(set))")
        .accessibilitySortPriority(set == 0 ? 60 : 50)
    }
    private func lanesOnGrid(_ set: Int) -> [Int] {
        (0..<min(4, lines.count)).filter { lines[$0].poolChordsOn && euclideousLaneChordGrid(lines[$0].poolSrcMaskResolved) == set }
    }
    private func lanesSpoken(_ set: Int) -> String {
        let l = lanesOnGrid(set).map { $0 + 1 }
        switch l.count {
        case 0: return "no lanes"
        case 1: return "lane \(l[0])"
        default: return "lanes " + l.dropLast().map(String.init).joined(separator: ", ") + " and \(l.last!)"
        }
    }

    // MARK: 5.6 title row and its pill
    private func gridTitleRow(_ set: Int, cfg: MachineParams, steps: Int, L: EuclideousHarmonyLayout) -> some View {
        let pill = harmonyPill(cfg)
        let open = popover == .pill(set)
        return HStack(spacing: 6) {
            Text("\(set + 1)").font(mono(15)).foregroundColor(Color(h: 0xF2F4F7)).frame(width: 18, alignment: .leading).layoutPriority(2)
            HStack(spacing: 6) {
                ForEach(lanesOnGrid(set), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color(h: laneHex[min(3, i)])).frame(width: 8, height: 8)
                }
            }
            .layoutPriority(2)
            summaryPill(set, pill: pill, open: open)
            Spacer(minLength: 6)
            stepsStepper(set, steps: steps).layoutPriority(2)
        }
        .frame(width: L.columnW, height: EuclideousHarmonyMetrics.gridTitleH, alignment: .leading)
    }
    private func stepsStepper(_ set: Int, steps: Int) -> some View {
        HStack(spacing: 0) {
            stepButton("\u{2212}", disabled: steps <= 1, spoken: "Fewer steps") { onEditChordSet(set) { $0.chordsSteps = max(1, steps - 1) } }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(steps)").font(mono(12)).foregroundColor(Color(h: 0xF2F4F7))
                Text("STEPS").font(mono(8)).foregroundColor(Color(h: 0x8A909A))
            }
            .frame(width: 42).lineLimit(1)
            .accessibilityElement(children: .ignore).accessibilityLabel("Steps").accessibilityValue("\(steps)")
            stepButton("+", disabled: steps >= 16, spoken: "More steps") { onEditChordSet(set) { $0.chordsSteps = min(16, steps + 1) } }
        }
    }
    private func stepButton(_ glyph: String, disabled: Bool, spoken: String, _ act: @escaping () -> Void) -> some View {
        Text(glyph).font(.system(size: 13)).foregroundColor(Color(h: disabled ? 0x4A4E57 : 0xAAB0BA))
            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 5).fill(Color(h: 0x2A2D34)))
            .frame(width: 30, height: 44).contentShape(Rectangle()).onTapGesture { if !disabled { act() } }
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityAddTraits(.isButton)
    }
    private func laneSquare(_ lane: Int) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color(h: laneHex[min(3, max(0, lane))])).frame(width: 8, height: 8)
    }
    private func pillText(_ s: String, _ hex: UInt32) -> some View {
        Text(s).font(mono(8.5)).tracking(0.06 * 8.5).foregroundColor(Color(h: hex)).lineLimit(1)   // truncated when the room runs out, never shrunk
    }
    private func summaryPill(_ set: Int, pill: HarmonyPill, open: Bool) -> some View {
        HStack(spacing: 6) {
            pillText(pill.advanceUnit, 0xF2F4F7)
            if let l = pill.advanceLane { laneSquare(l) }
            pillText(pill.advanceValue, 0xAAB0BA)
            if let r = pill.restart {
                Rectangle().fill(Color(h: 0x3A3E47)).frame(width: 1, height: 10)
                Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold)).foregroundColor(Color(h: 0xAAB0BA))
                pillText(r.unit, 0xAAB0BA)
                if let l = r.lane { laneSquare(l) }
                pillText(r.value, 0xAAB0BA)
            }
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(Color(h: 0xAAB0BA))
                .rotationEffect(.degrees(open ? 180 : 0)).fixedSize()
        }
        .padding(.leading, 10).padding(.trailing, 8).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(h: open ? 0x2A2D34 : 0x24262C)))
        .overlay(open ? RoundedRectangle(cornerRadius: 6).inset(by: 0.5).stroke(Color(h: 0x5C626C), lineWidth: 1) : nil)
        .harmonyAnchor("pill\(set)", space: Self.space)
        .frame(height: 44).contentShape(Rectangle())
        .onTapGesture { togglePill(set) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grid \(set + 1) timing")
        .accessibilityValue(pill.spoken + (open ? ", expanded" : ", collapsed"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 5.7 step strip
    private func stepStrip(steps: Int, playing: Int, L: EuclideousHarmonyLayout) -> some View {
        let c = max(8, steps)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<c, id: \.self) { i in
                let isPlaying = i == playing
                let within = i < steps
                let fill = isPlaying ? Color(h: 0xDFE3EA) : (within ? Color(h: 0x24262C) : Color(h: 0x1F2126))
                let ink = isPlaying ? Color(h: 0x0D0F14) : (within ? Color(h: 0x7C828D) : Color(h: 0x4A4E57))
                RoundedRectangle(cornerRadius: 3).fill(fill)
                    .overlay(Text("\(i + 1)").font(mono(7)).foregroundColor(ink))
                    .frame(width: L.cellW(steps: steps), height: EuclideousHarmonyMetrics.stripH)
                    .offset(x: L.columnLeft(steps: steps, i))
            }
        }
        .frame(width: L.columnW, height: EuclideousHarmonyMetrics.stripH, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Column \(min(steps, max(0, playing) + 1)) of \(steps)\(self.playing ? ", playing" : "")")
    }

    // MARK: 5.8 grid
    private func grid(_ set: Int, cfg: MachineParams, steps: Int, playing: Int, L: EuclideousHarmonyLayout) -> some View {
        let degrees = cfg.chordsDegreesResolved16(), colours = cfg.chordsColoursResolved16()
        let c = max(8, steps)
        let mode = rows
        let rowH = L.rowH(mode)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<mode.rowCount, id: \.self) { p in
                Text(euclideousChordsRowLabel(row: mode.firstRow + p, scaleTones: keyType.intervals, minorKey: minorKey))
                    .font(mono(10)).foregroundColor(Color(h: 0xAAB0BA)).lineLimit(1)
                    .frame(width: EuclideousHarmonyMetrics.gridLabelW, height: rowH, alignment: .leading)
                    .offset(y: L.rowTop(mode, position: p))
                    .accessibilityHidden(true)
            }
            ForEach(0..<c, id: \.self) { col in
                ForEach(0..<mode.rowCount, id: \.self) { p in
                    cell(set, row: mode.firstRow + p, column: col, degrees: degrees, colours: colours, steps: steps, playing: playing)
                        .frame(width: L.cellW(steps: steps), height: rowH)
                        .offset(x: L.columnLeft(steps: steps, col), y: L.rowTop(mode, position: p))
                }
            }
        }
        .frame(width: L.columnW, height: L.gridH, alignment: .topLeading)
    }
    @ViewBuilder private func cell(_ set: Int, row r: Int, column c: Int, degrees: [Int], colours: [Int], steps: Int, playing: Int) -> some View {
        let beyond = c >= steps
        let isPlaying = c == playing
        let (_, isRest) = chordsDegreeAt(step: c, degrees: Array(degrees.prefix(max(1, steps))), rotate: 0)
        let label = euclideousChordsRowLabel(row: r, scaleTones: keyType.intervals, minorKey: minorKey)
        let unlit = Color(h: isPlaying ? 0x2E3138 : 0x22242A)
        if r >= 12 {                                                     // the colour rows
            let colourVal = r - 11
            let on = c < colours.count && colours[c] == colourVal
            RoundedRectangle(cornerRadius: 4).fill(on ? Color(h: isPlaying ? 0xD6CBFB : 0xB9A8FF) : unlit)
                .opacity(isRest ? 0.42 : (beyond ? 0.30 : 1))
                .contentShape(Rectangle())
                .onTapGesture { onEditChordSet(set) { p in var a = p.chordsColoursResolved16(); if c < a.count { a[c] = (a[c] == colourVal ? 0 : colourVal) }; p.chordsColours = a } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Column \(c + 1), \(label), \(on ? "on" : "off")")
        } else if let deg = euclideousChordsRowDegree(r) {
            let cellState = chordsMatrixCell(Array(degrees.prefix(16)), step: c, steps: steps)
            let on = cellState.bright == deg
            let lit = deg == 7 ? Color(h: 0x5C626C) : Color(h: isPlaying ? 0xD6CBFB : 0xB9A8FF)
            RoundedRectangle(cornerRadius: 4).fill(on ? lit : unlit).opacity(beyond ? 0.30 : 1)
                .contentShape(Rectangle())
                .onTapGesture { onEditChordSet(set) { p in var a = p.chordsDegreesResolved16(); if c < a.count { a[c] = deg }; p.chordsDegrees = a } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Column \(c + 1), \(label), \(on ? "selected" : "not selected")")
        }
    }

    // MARK: 5.10 the bottom band
    private func bandChip(_ text: String, fill: UInt32, ink: UInt32, outlined: Bool = false, ghost: Bool = false, dim: Bool = false) -> some View {
        Text(text).font(mono(10)).lineLimit(1)
            .foregroundColor(Color(h: dim ? 0x5C626C : (outlined ? fill : ink)))
            .padding(.horizontal, 4).frame(minWidth: 28, minHeight: 22, maxHeight: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(outlined || ghost ? Color.clear : Color(h: fill)))
            .overlay((outlined || ghost) ? RoundedRectangle(cornerRadius: 4).strokeBorder(Color(h: ghost ? 0x3A3E47 : fill), lineWidth: 1) : nil)
    }
    /// The chips' room: the strip less its padding (10 + 6), the 52 pt label and the trailing control, and the gaps.
    private func chipFit(room: CGFloat, count: Int) -> (shown: Int, overflow: Int) {
        let w: CGFloat = 28, gap: CGFloat = 6
        let fit = max(1, Int((room + gap) / (w + gap)))
        if count <= fit { return (count, 0) }
        let shown = max(0, fit - 1)
        return (shown, count - shown)
    }
    private func pickStrip(_ L: EuclideousHarmonyLayout) -> some View {
        let notes = plan.pickNotesR
        let names = notes.map { euclideousNoteViewName($0, flatKey: flat) }
        let editOpen = popover == .pick
        let room = L.pickStrip.width - 16 - 52 - 8 - 44 - 8
        let fit = chipFit(room: room, count: notes.count)
        let src = EuclideousSourceColour.pick
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("PICK").font(mono(8)).tracking(0.12 * 8).foregroundColor(Color(h: 0x8A909A)).frame(width: 52, alignment: .leading)
                HStack(spacing: 6) {
                    if notes.isEmpty { bandChip("", fill: 0x3A3E47, ink: 0, ghost: true) }
                    else {
                        ForEach(Array(names.prefix(fit.shown).enumerated()), id: \.offset) { _, n in bandChip(n, fill: src.fill, ink: src.ink) }
                        if fit.overflow > 0 { Text("+\(fit.overflow)").font(mono(10)).foregroundColor(Color(h: 0x8A909A)).lineLimit(1) }
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Pick notes").accessibilityValue(names.isEmpty ? "none" : names.joined(separator: ", "))
            Text("EDIT").font(mono(8)).tracking(0.08 * 8).foregroundColor(Color(h: editOpen ? 0x0D0F14 : 0xAAB0BA))
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(h: editOpen ? 0xDFE3EA : 0x2A2D34)))
                .harmonyAnchor("edit", space: Self.space)
                .frame(height: 36).contentShape(Rectangle())
                .onTapGesture { togglePick() }
                .accessibilityElement(children: .ignore).accessibilityLabel("Edit pick notes").accessibilityValue(editOpen ? "expanded" : "collapsed").accessibilityAddTraits(.isButton)
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .frame(width: L.pickStrip.width, height: L.pickStrip.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(h: 0x1F2126)))
        .offset(x: L.pickStrip.minX, y: L.pickStrip.minY)
        .accessibilityElement(children: .contain).accessibilitySortPriority(40)
    }
    private func midiStrip(_ L: EuclideousHarmonyLayout) -> some View {
        let octaves = plan.midiOctavesR
        let names = heldNotes.map { euclideousMidiChipName(note: Int($0), octaves: octaves, flatKey: flat) }
        let room = L.midiStrip.width - 16 - 52 - 8 - 150 - 8
        let fit = chipFit(room: room, count: names.count)
        let src = EuclideousSourceColour.midi
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("MIDI IN").font(mono(8)).tracking(0.12 * 8).foregroundColor(Color(h: 0x8A909A)).frame(width: 52, alignment: .leading).lineLimit(1)
                HStack(spacing: 6) {
                    if names.isEmpty { bandChip("", fill: 0x3A3E47, ink: 0, ghost: true) }
                    else {
                        ForEach(Array(names.prefix(fit.shown).enumerated()), id: \.offset) { _, n in bandChip(n, fill: src.fill, ink: src.ink, outlined: !midiPlaying) }
                        if fit.overflow > 0 { Text("+\(fit.overflow)").font(mono(10)).foregroundColor(Color(h: 0x8A909A)).lineLimit(1) }
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("MIDI in notes").accessibilityValue(names.isEmpty ? "none" : names.joined(separator: ", "))
            HStack(spacing: 6) {
                Text("OCTAVES").font(mono(7.5)).tracking(0.1 * 7.5).foregroundColor(Color(h: 0x8A909A)).lineLimit(1).accessibilityHidden(true)
                twoSegment([("IGNORE", "Ignore", octaves == .ignore), ("KEEP", "Keep", octaves == .keep)]) { i in
                    let v: MidiOctaves = i == 0 ? .ignore : .keep
                    if plan.midiOctavesR != v { var p = plan; p.midiOctaves = v; onSetPlan(p) }   // one undo step; the selected segment records nothing
                }
                .accessibilityElement(children: .contain).accessibilityLabel("Octaves")
            }
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .frame(width: L.midiStrip.width, height: L.midiStrip.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(h: 0x1F2126)))
        .offset(x: L.midiStrip.minX, y: L.midiStrip.minY)
        .accessibilityElement(children: .contain).accessibilitySortPriority(30)
    }

    // MARK: 5.9 / 5.11 popovers
    @ViewBuilder private func popoverView(_ L: EuclideousHarmonyLayout) -> some View {
        switch popover {
        case .none: EmptyView()
        case .pill(let set):
            let f = L.pillPopover(set: set)
            popoverSurface { pillPopoverContent(set, innerW: f.width - 2 * EuclideousHarmonyMetrics.popoverPad) }
                .frame(width: f.width, height: f.height, alignment: .topLeading)
                .offset(x: L.content.minX + f.minX, y: L.content.minY + f.minY)
                .accessibilityElement(children: .contain).accessibilityLabel("Grid \(set + 1) timing").accessibilitySortPriority(110)
                .accessibilityAction(.escape) { popover = .none }
        case .pick:
            let f = L.pickPopover
            popoverSurface { pickPopoverContent(innerW: f.width - 2 * EuclideousHarmonyMetrics.popoverPad) }
                .frame(width: f.width, height: f.height, alignment: .topLeading)
                .offset(x: L.content.minX + f.minX, y: L.content.minY + f.minY)
                .accessibilityElement(children: .contain).accessibilityLabel("Pick notes").accessibilitySortPriority(110)
                .accessibilityAction(.escape) { popover = .none }
        }
    }
    /// #24262C, radius 10, a 1 pt #3A3E47 inner border, shadow black 50 % (radius 28, y 14), padding 10; a 120 ms fade (none with Reduce Motion).
    private func popoverSurface<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(EuclideousHarmonyMetrics.popoverPad)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(h: 0x24262C)))
            .overlay(RoundedRectangle(cornerRadius: 10).inset(by: 0.5).stroke(Color(h: 0x3A3E47), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
            .transition(.opacity)
    }

    private func unitChip(_ label: String, spoken: String, selected: Bool, width: CGFloat, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Text(label).font(mono(8)).tracking(0.06 * 8).lineLimit(1)
            .foregroundColor(selected ? Color(h: 0x0D0F14) : Color(h: 0xAAB0BA))
            .frame(width: width, height: EuclideousHarmonyMetrics.popoverRowH).background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(h: 0xDFE3EA) : Color(h: 0x33363E)))
            .opacity(dim ? 0.42 : 1).contentShape(Rectangle()).onTapGesture(perform: act)
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func rateChip(_ label: String, selected: Bool, width: CGFloat, _ act: @escaping () -> Void) -> some View {
        Text(label).font(mono(7.5)).lineLimit(1)
            .foregroundColor(selected ? Color(h: 0x0D0F14) : Color(h: 0xAAB0BA))
            .frame(width: width, height: EuclideousHarmonyMetrics.popoverRowH).background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color(h: 0xDFE3EA) : Color(h: 0x33363E)))
            .contentShape(Rectangle()).onTapGesture(perform: act)
            .accessibilityElement(children: .ignore).accessibilityLabel("Rate \(label)").accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func laneSelect(_ i: Int, selected: Bool, dim: Bool, width: CGFloat, _ act: @escaping () -> Void) -> some View {
        ZStack {
            if selected { RoundedRectangle(cornerRadius: 2.5).fill(Color(h: laneHex[i])).frame(width: 12, height: 12) }
            else { RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color(h: laneHex[i]).opacity(0.55), lineWidth: 1.5).frame(width: 12, height: 12) }
        }
        .frame(width: width, height: EuclideousHarmonyMetrics.popoverRowH).opacity(dim ? 0.42 : 1).contentShape(Rectangle()).onTapGesture(perform: act)
        .accessibilityElement(children: .ignore).accessibilityLabel("Lane \(i + 1)").accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func everyChip(_ value: Int, spoken: String, dim: Bool, width: CGFloat, _ act: @escaping () -> Void) -> some View {
        Text("\(value)").font(mono(12)).foregroundColor(Color(h: 0x0D0F14))
            .frame(width: width, height: EuclideousHarmonyMetrics.popoverRowH).background(RoundedRectangle(cornerRadius: 6).fill(Color(h: 0xDFE3EA)))
            .opacity(dim ? 0.42 : 1).contentShape(Rectangle()).onTapGesture(perform: act)
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityHint("Double-tap for the next value").accessibilityAddTraits(.isButton)
    }
    private func restartSwitch(on: Bool, _ act: @escaping () -> Void) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 10).fill(Color(h: on ? 0xDFE3EA : 0x2A2D34)).frame(width: 34, height: 20)
            Circle().fill(Color(h: on ? 0x0D0F14 : 0x5C626C)).frame(width: 16, height: 16).padding(.horizontal, 2)
        }
        .frame(width: 34, height: 28).contentShape(Rectangle()).onTapGesture(perform: act)
        .accessibilityElement(children: .ignore).accessibilityLabel("Restart").accessibilityValue(on ? "on" : "off").accessibilityAddTraits(.isButton)
    }
    private func cycle(_ current: Int, _ values: [Int]) -> Int {
        guard let idx = values.firstIndex(of: current) else { return values.first ?? 1 }
        return values[(idx + 1) % values.count]
    }
    private func everySpoken(_ n: Int, _ unitWord: String) -> String { n == 1 ? "Every \(unitWord)" : "Every \(n) \(unitWord)s" }

    private func pillPopoverContent(_ set: Int, innerW: CGFloat) -> some View {
        let R = euclideousHarmonyPopoverRows(innerW: innerW)
        return VStack(alignment: .leading, spacing: EuclideousHarmonyMetrics.popoverRowGap) {
            advanceRow(set, R)
            restartRow(set, R)
        }
        .frame(width: innerW, alignment: .leading)
    }
    private func advanceRow(_ set: Int, _ R: EuclideousHarmonyPopoverRows) -> some View {
        let cfg = chordSets[min(set, max(0, chordSets.count - 1))]
        let unit = cfg.advanceUnitResolved
        return HStack(spacing: 0) {
            Text("ADVANCE").font(mono(7.5)).tracking(0.1 * 7.5).foregroundColor(Color(h: 0x8A909A)).lineLimit(1).frame(width: R.labelW, alignment: .leading)
            Spacer().frame(width: 4)
            HStack(spacing: 4) {
                unitChip("TIME", spoken: "Advance by time", selected: unit == .time, width: R.unitChipW) { onEditChordSet(set) { $0.advanceUnit = .time } }
                unitChip("LOOP", spoken: "Advance by loop", selected: unit == .loop, width: R.unitChipW) { onEditChordSet(set) { $0.advanceUnit = .loop } }
                unitChip("RIFF", spoken: "Advance by riff", selected: unit == .riff, width: R.unitChipW) { onEditChordSet(set) { $0.advanceUnit = .riff } }
            }
            Spacer().frame(width: 6)
            if unit == .time {
                HStack(spacing: 2) {
                    ForEach(StepRate.allCases, id: \.self) { r in
                        rateChip(r.rawValue, selected: cfg.chordsRateResolved == r, width: R.rateChipW) { onEditChordSet(set) { $0.chordsRate = r } }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in laneSelect(i, selected: cfg.advanceLaneResolved == i, dim: false, width: R.squareW) { onEditChordSet(set) { $0.advanceLane = i } } }
                }
                Spacer().frame(width: 4)
                everyChip(cfg.advanceEveryResolved, spoken: everySpoken(cfg.advanceEveryResolved, unit == .riff ? "riff" : "loop"), dim: false, width: R.everyW) {
                    onEditChordSet(set) { $0.advanceEvery = cycle(cfg.advanceEveryResolved, chordsAdvanceEveryValues) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: R.innerW, height: EuclideousHarmonyMetrics.popoverRowH, alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel("Advance")
    }
    private func restartRow(_ set: Int, _ R: EuclideousHarmonyPopoverRows) -> some View {
        let cfg = chordSets[min(set, max(0, chordSets.count - 1))]
        let on = cfg.restartOnResolved, unit = cfg.restartUnitResolved
        return HStack(spacing: 0) {
            Text("RESTART").font(mono(7.5)).tracking(0.1 * 7.5).foregroundColor(Color(h: 0x8A909A)).lineLimit(1).frame(width: R.labelW, alignment: .leading)
            Spacer().frame(width: 4)
            HStack(spacing: 4) {   // the values dim to 42 % while the switch is off, but stay live
                unitChip("BAR", spoken: "Restart by bar", selected: unit == .bar, width: R.unitChipW, dim: !on) { onEditChordSet(set) { $0.restartUnit = .bar } }
                unitChip("LOOP", spoken: "Restart by loop", selected: unit == .loop, width: R.unitChipW, dim: !on) { onEditChordSet(set) { $0.restartUnit = .loop } }
                unitChip("RIFF", spoken: "Restart by riff", selected: unit == .riff, width: R.unitChipW, dim: !on) { onEditChordSet(set) { $0.restartUnit = .riff } }
            }
            Spacer().frame(width: 6)
            if unit != .bar {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in laneSelect(i, selected: cfg.restartLaneResolved == i, dim: !on, width: R.squareW) { onEditChordSet(set) { $0.restartLane = i } } }
                }
            } else {
                Spacer().frame(width: 4 * R.squareW + 3 * 4)   // BAR keeps the lane squares' space empty, nothing moves
            }
            Spacer().frame(width: 4)
            everyChip(cfg.restartEveryResolved, spoken: everySpoken(cfg.restartEveryResolved, unit == .riff ? "riff" : (unit == .loop ? "loop" : "bar")), dim: !on, width: R.everyW) {
                onEditChordSet(set) { $0.restartEvery = cycle(cfg.restartEveryResolved, chordsRestartEveryValues) }
            }
            Spacer(minLength: 0)
            restartSwitch(on: on) { onEditChordSet(set) { $0.restartOn = !on } }
        }
        .frame(width: R.innerW, height: EuclideousHarmonyMetrics.popoverRowH, alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel("Restart")
    }

    // MARK: 5.11 the PICK editor (the sources panel's, re-hosted at the popover's width)
    private func pickPopoverContent(innerW: CGFloat) -> some View {
        let keyW = max(8, (innerW - EuclideousHarmonyMetrics.pickStepperW - 8 - 11 * 3) / 12)
        let octaveC = (pickOctave + 1) * 12
        let picks = Set(plan.pickNotesR)
        return HStack(spacing: 8) {
            octaveStepper
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { pc in
                    let note = octaveC + pc
                    pickKey(Self.noteNames[pc], picked: picks.contains(UInt8(max(0, min(127, note)))), sharp: Self.isSharp[pc], width: keyW, note: note)
                }
            }
        }
        .frame(width: innerW, alignment: .leading)
    }
    private var octaveStepper: some View {
        HStack(spacing: 0) {
            Button { pickOctave = max(1, pickOctave - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundColor(Color(h: 0xDFE3EA)).frame(width: 26, height: EuclideousHarmonyMetrics.pickKeyH).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Octave down")
            Text(euclideousNoteViewName(UInt8(max(0, min(127, (pickOctave + 1) * 12))), flatKey: false))
                .font(mono(12)).foregroundColor(Color(h: 0xF2F4F7)).frame(maxWidth: .infinity)
            Button { pickOctave = min(7, pickOctave + 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(Color(h: 0xDFE3EA)).frame(width: 26, height: EuclideousHarmonyMetrics.pickKeyH).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Octave up")
        }
        .frame(width: EuclideousHarmonyMetrics.pickStepperW, height: EuclideousHarmonyMetrics.pickKeyH)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(h: 0x1B1D23)))
    }
    private func pickKey(_ name: String, picked: Bool, sharp: Bool, width: CGFloat, note: Int) -> some View {
        let fill = picked ? Color(h: EuclideousSourceColour.pick.fill) : (sharp ? Color(h: 0x1B1D23) : Color(h: 0x2A2D34))
        let text = picked ? Color(h: EuclideousSourceColour.pick.ink) : (sharp ? Color(h: 0x8A909A) : Color(h: 0xDFE3EA))
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 5).fill(fill)
                .overlay((picked || sharp) ? RoundedRectangle(cornerRadius: 5).strokeBorder(picked ? Color(h: EuclideousSourceColour.pick.fill) : Color(h: 0x2A2D34), lineWidth: 1) : nil)
            Text(name).font(mono(8)).foregroundColor(text).lineLimit(1).padding(.leading, 3).padding(.bottom, 6)
        }
        .frame(width: width, height: EuclideousHarmonyMetrics.pickKeyH).contentShape(Rectangle())
        .onTapGesture {
            var p = plan
            p.pickNotes = euclideousPickToggle(plan.pickNotesR, UInt8(max(0, min(127, note))))   // add / remove, ascending, ≤ 16 — one undo step
            onSetPlan(p)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(name).accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - the header button (6): four pips, the key label, a chevron; a tap toggles the page

/// The 192 × 32 button the SOURCES panel used to open, now toggling HARMONY. The pips come from the per-source status across the four lanes (`euclideousSourceStatusAcrossLanes`, the status feed's per-lane contributions and the lanes' own
/// SOURCES chips): playing — fill and border in the source colour; waiting — border only; unused — border #3A3E47. Observes the status model itself, so the page does not re-run for it.
struct EuclideousHarmonyHeaderButton: View {
    let keyRoot: Int
    let keyType: ScaleType
    let laneChips: [UInt8]
    let open: Bool
    let width: CGFloat
    let onTap: () -> Void
    @ObservedObject var live: AnswerLiveModel

    var body: some View {
        let contrib = (0..<4).map { live.pool(lane: $0).contrib }
        let st = euclideousSourceStatusAcrossLanes(laneContrib: contrib, laneChips: laneChips)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                pip(st.midi, EuclideousSourceColour.midi.fill); pip(st.chords, EuclideousSourceColour.chords.fill)
                pip(st.pick, EuclideousSourceColour.pick.fill); pip(st.key, EuclideousSourceColour.key.fill)
            }
            Spacer().frame(width: 8)
            Text(euclideousKeyLabel(root: keyRoot, type: keyType)).font(mono(10)).tracking(0.06 * 10)
                .foregroundColor(Color(h: 0xF2F4F7)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(Color(h: 0xAAB0BA)).rotationEffect(.degrees(open ? 180 : 0)).fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(h: 0x2A2D34)))
        .overlay(open ? RoundedRectangle(cornerRadius: 8).strokeBorder(Color(h: 0xDFE3EA), lineWidth: 1.5) : nil)
        .contentShape(Rectangle()).onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Harmony")
        .accessibilityValue(euclideousSourceButtonAccessibilityValue(keyLabel: euclideousKeySpokenName(root: keyRoot, type: keyType), midi: st.midi, chords: st.chords, pick: st.pick, key: st.key) + (open ? ", expanded" : ", collapsed"))
        .accessibilityAddTraits(.isButton)
    }
    private func pip(_ state: EuclideousSourceLight, _ colour: UInt32) -> some View {
        let c = Color(h: colour)
        return RoundedRectangle(cornerRadius: 3).fill(state == .playing ? c : Color.clear)
            .frame(width: 10, height: 10)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(state == .off ? Color(h: 0x3A3E47) : c, lineWidth: 1.5))
    }
}
