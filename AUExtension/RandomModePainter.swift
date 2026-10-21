//  RandomModePainter.swift
//  RANDOM MODE ferry (§3-§4): the lane card's picture-mode view — the selector, the three pictures
//  (RHYTHM circle, RIFF path, NOTES pattern), the caption and the THROW/TWEAK/BACK/KEEP buttons. Pulls its
//  data from EuclideousRandom.swift's pure functions (the engine's own pattern/riff-column/play-list
//  functions, never a second derivation) and EuclideousPage's own random-mode session state; this file only
//  paints. Sizes are built from the card's own frame (passed in), not hardcoded screen assumptions.

import SwiftUI

/// §3: the full picture-mode card. `line`/`original` are resolved EuclidLine snapshots (the original is the
/// tab's pre-roll state while a roll is undecided, nil when decided); `holding` is true while this card's
/// picture is actively held (§5.6 — the hold ferry step wires this; it always reads false until then).
struct EuclideousRandomCardView: View {
    let lane: Int
    let width: CGFloat
    let height: CGFloat
    let accent: Color
    let line: EuclidLine   // the CURRENT state as heard (already merged with any still-queued roll)
    let riffRanks: [Int]
    let tab: EuclideousRandomTab
    let state: EuclideousRandomRollState
    let holding: Bool

    let onSelectTab: (EuclideousRandomTab) -> Void
    let onThrow: () -> Void
    let onTweak: () -> Void
    let onBack: () -> Void
    let onKeep: () -> Void
    let onHoldBegan: () -> Void
    let onHoldEnded: () -> Void

    private let inset: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            selectorRow.frame(height: 32).padding(.top, 10)
            Spacer(minLength: 2)
            picture.frame(height: max(1, height - 58 - 84))
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
                // §5.6: only while the selected tab has an undecided roll — a decided tab's picture isn't a hold target.
                .modifier(EuclideousRandomHoldModifier(enabled: state.isUndecided, onBegan: onHoldBegan, onEnded: onHoldEnded))
            caption.frame(height: 14).padding(.top, 6)
            Spacer(minLength: 2)
            buttonRow.frame(height: 44).padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1B1D23)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(holding ? 0.9 : 0.45), lineWidth: 1))
    }

    // MARK: §3.2 selector

    private var selectorRow: some View {
        HStack(spacing: 0) {
            Circle().fill(accent).frame(width: 24, height: 24)
                .overlay(Text("\(lane + 1)").font(.system(size: 12, weight: .heavy)).foregroundColor(Color(hex: 0x0D0F14)))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach([EuclideousRandomTab.rhythm, .riff, .notes], id: \.rawValue) { t in
                    segment(t)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        }
    }

    private func segment(_ t: EuclideousRandomTab) -> some View {
        let selected = t == tab
        let dotted = t != tab && state.isUndecidedFor(t)
        return ZStack(alignment: .topTrailing) {
            Text(label(t)).font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundColor(selected ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .frame(height: 24).padding(.horizontal, 10)
                .background(selected ? RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xDFE3EA)) : nil)
            if dotted {
                Circle().fill(accent).frame(width: 6, height: 6).offset(x: -5, y: 5)
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        .onTapGesture { onSelectTab(t) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roll lane \(lane + 1) \(label(t).lowercased())" + (dotted ? ", not decided yet" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ t: EuclideousRandomTab) -> String {
        switch t { case .rhythm: return "RHYTHM"; case .riff: return "RIFF"; case .notes: return "NOTES" }
    }

    // MARK: §4 the picture

    @ViewBuilder private var picture: some View {
        switch tab {
        case .rhythm: EuclideousRandomRhythmPicture(line: line, original: state.original, accent: accent)
        case .riff: EuclideousRandomRiffPicture(line: line, original: state.original, accent: accent, riffRanks: riffRanks)
        case .notes: EuclideousRandomNotesPicture(line: line, original: state.original, accent: accent, riffRanks: riffRanks)
        }
    }

    // MARK: §3.6 caption

    private var caption: some View {
        Text(captionText).font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
            .foregroundColor(captionColor).lineLimit(1).truncationMode(.tail)
    }

    private var captionText: String {
        if let w = state.waiting {
            switch w { case .throwing: return "THROWING · NEXT BAR"; case .tweaking: return "TWEAKING · NEXT BAR"; case .back: return "GOING BACK · NEXT BAR" }
        }
        if holding { return "PLAYING THE ORIGINAL · LET GO FOR THE NEW ONE" }
        if state.isUndecided {
            var s = state.tag
            if state.goes >= 2 { s += "  ·  \(state.goes) GOES" }
            return s
        }
        if let decidedAt = state.decidedAt, Date().timeIntervalSince(decidedAt) < 8 {
            return state.tag.isEmpty ? "KEPT" : "KEPT"
        }
        let layerOff: Bool
        switch tab { case .riff: layerOff = !line.riffOnResolved; case .notes: layerOff = !euclideousNotesLayerIsOn(line); case .rhythm: layerOff = false }
        if layerOff { return tab == .notes ? "THE NOTES LAYER IS OFF · YOU WON'T HEAR THIS" : "RIFF IS OFF · YOU WON'T HEAR THIS" }
        return "THROW A NEW ONE · TWEAK WHAT'S PLAYING"
    }

    private var captionColor: Color {
        if state.waiting != nil || holding { return accent }
        if state.isUndecided { return Color(hex: 0xF2F4F7) }
        if let decidedAt = state.decidedAt, Date().timeIntervalSince(decidedAt) < 8 { return accent }
        let layerOff: Bool
        switch tab { case .riff: layerOff = !line.riffOnResolved; case .notes: layerOff = !euclideousNotesLayerIsOn(line); case .rhythm: layerOff = false }
        return layerOff ? Color(hex: 0xFFB454) : Color(hex: 0x8A909A)
    }

    // MARK: §3.7 buttons

    private var buttonRow: some View {
        HStack(spacing: 6) {
            button("THROW", glyph: "die.face.4", tint: accent, action: onThrow, dashed: state.waiting == .throwing)
            button("TWEAK", glyph: "waveform.path", tint: accent, action: onTweak, dashed: state.waiting == .tweaking)
            if state.isUndecided {
                button("BACK", glyph: "arrow.uturn.backward", tint: Color(hex: 0xAAB0BA), action: onBack, dashed: state.waiting == .back)
                button("KEEP", glyph: "checkmark", tint: nil, action: onKeep, dashed: false, filled: true)
            }
        }
    }

    private func button(_ title: String, glyph: String, tint: Color?, action: @escaping () -> Void, dashed: Bool, filled: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: state.isUndecided ? 16 : 18))
                Text(title).font(.system(size: 11, weight: .heavy)).tracking(0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(filled ? Color(hex: 0x0D0F14) : (tint ?? Color(hex: 0xF2F4F7)))
            .background(RoundedRectangle(cornerRadius: 10).fill(filled ? accent : Color(hex: 0x2A2D34)))
            .overlay(dashed ? RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundColor(accent).padding(1) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(buttonAccessibilityLabel(title))
    }

    private func buttonAccessibilityLabel(_ title: String) -> String {
        let suffix = {
            switch title {
            case "THROW": return "Throw a new \(tabName)"
            case "TWEAK": return "Tweak the \(tabName)"
            case "BACK": return "Back to the original \(tabName)"
            case "KEEP": return "Keep · \(state.tag)"
            default: return title
            }
        }()
        let waitingSuffix = (title == "THROW" && state.waiting == .throwing) || (title == "TWEAK" && state.waiting == .tweaking) || (title == "BACK" && state.waiting == .back)
            ? ", on the next bar" : ""
        return suffix + waitingSuffix
    }

    private var tabName: String {
        switch tab { case .rhythm: return "rhythm"; case .riff: return "riff walk"; case .notes: return "notes" }
    }
}

private extension EuclideousRandomRollState {
    func isUndecidedFor(_ t: EuclideousRandomTab) -> Bool { original != nil }
}

/// §5.6: touch-down/touch-up on the picture, gated on `enabled` (an undecided roll). No minimum-duration
/// threshold — read literally, the spec's hold switches from touch-down itself, unlike the 0.3 s hold this
/// codebase uses elsewhere for the output rings/SOLO buttons (flagged in the ferry report).
private struct EuclideousRandomHoldModifier: ViewModifier {
    let enabled: Bool
    let onBegan: () -> Void
    let onEnded: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: 0.0001, maximumDistance: 1000,
                                        pressing: { down in down ? onBegan() : onEnded() }, perform: {})
        } else {
            content
        }
    }
}

// MARK: - §4.1 RHYTHM picture

struct EuclideousRandomRhythmPicture: View {
    let line: EuclidLine
    let original: EuclidLine?
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r = min(w, h) / 2 - 12
            let cx = w / 2, cy = h / 2
            let steps = max(2, min(16, line.steps))
            let hits = line.pulses
            let offset = euclideousRandomDisplayedOffset(rotate: line.rotate, steps: steps)
            let pattern = euclideousRandomPattern(hits: hits, steps: steps, offset: offset, tilt: line.tiltResolved)
            ZStack {
                if let o = original {
                    let oSteps = max(2, min(16, o.steps))
                    let oPattern = euclideousRandomPattern(hits: o.pulses, steps: oSteps,
                                                            offset: euclideousRandomDisplayedOffset(rotate: o.rotate, steps: oSteps), tilt: o.tiltResolved)
                    ringPath(oPattern, steps: oSteps, cx: cx, cy: cy, r: r)
                        .stroke(Color(hex: 0x4A4E57).opacity(0.7), lineWidth: 1.5)
                }
                ringPath(pattern, steps: steps, cx: cx, cy: cy, r: r)
                    .stroke(accent.opacity(0.55), lineWidth: 2.5)
                ForEach(0..<steps, id: \.self) { i in
                    let p = point(i, steps: steps, cx: cx, cy: cy, r: r)
                    Circle().fill(pattern[i] ? accent : Color(hex: 0x3A3E47))
                        .frame(width: pattern[i] ? 14 : 6, height: pattern[i] ? 14 : 6)
                        .position(p)
                }
                VStack(spacing: 3) {
                    Text("\(hits) / \(steps)").font(.system(size: 22, weight: .heavy)).foregroundColor(Color(hex: 0xF2F4F7))
                    Text(offset > 0 ? "OFFSET \(offset)" : "NO OFFSET").font(.system(size: 8.5, weight: .heavy)).tracking(1)
                        .foregroundColor(Color(hex: 0x8A909A))
                }
                .position(x: cx, y: cy)
            }
        }
    }

    private func point(_ i: Int, steps: Int, cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPoint {
        let a = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(steps) * 2 * .pi
        return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
    }

    private func ringPath(_ pattern: [Bool], steps: Int, cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        var path = Path()
        let hitPoints = (0..<steps).filter { pattern[$0] }.map { point($0, steps: steps, cx: cx, cy: cy, r: r) }
        guard hitPoints.count > 1 else { return path }
        path.move(to: hitPoints[0])
        for p in hitPoints.dropFirst() { path.addLine(to: p) }
        path.addLine(to: hitPoints[0])
        return path
    }
}

// MARK: - §4.2 RIFF picture (the walk)

struct EuclideousRandomRiffPicture: View {
    let line: EuclidLine
    let original: EuclidLine?
    let accent: Color
    let riffRanks: [Int]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let length = line.riffLengthResolved
            let colW = w / 8
            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { c in
                    let within = c < length
                    let sounds = c < riffRanks.count && riffRanks[c] >= 1
                    Rectangle().fill(within ? (sounds ? Color(hex: 0x22252C) : Color(hex: 0x1F2127)) : Color.clear)
                        .frame(width: colW - 1, height: h)
                        .position(x: CGFloat(c) * colW + colW / 2, y: h / 2)
                    Text("\(c + 1)").font(.system(size: 9, weight: .heavy))
                        .foregroundColor(within ? Color(hex: 0xAAB0BA) : Color(hex: 0x3A3E47))
                        .position(x: CGFloat(c) * colW + colW / 2, y: 8)
                }
                if let o = original {
                    path(for: o, h: h, colW: colW)
                        .stroke(Color(hex: 0x4A4E57).opacity(0.7), lineWidth: 1.5)
                }
                let pts = points(for: line, h: h, colW: colW)
                path(for: line, h: h, colW: colW).stroke(accent.opacity(0.55), lineWidth: 2.5)
                ForEach(0..<pts.count, id: \.self) { i in
                    let sounds = pts[i].1
                    Circle()
                        .fill(sounds ? accent : Color.clear)
                        .overlay(sounds ? nil : Circle().strokeBorder(accent, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .position(pts[i].0)
                }
            }
        }
    }

    /// The first 12 hits from the melody origin (ordinal 0...11), each at the column the engine's own walk
    /// reads — `euclideousRiffColumn`, never a second derivation — placed evenly top-to-bottom.
    private func points(for l: EuclidLine, h: CGFloat, colW: CGFloat) -> [(CGPoint, Bool)] {
        let length = l.riffLengthResolved
        let seed = UInt64(bitPattern: Int64(l.riffDirSeedResolved))
        return (0..<12).map { ord in
            let col = euclideousRiffColumn(ordinal: Int64(ord), every: l.riffAdvanceEveryResolved, direction: l.euclideousRiffDirResolved,
                                            length: length, stride: l.riffStrideResolved, shift: l.riffRotateResolved, seed: seed)
            let y = 22 + CGFloat(ord) / 11 * (h - 30)
            let sounds = col < riffRanks.count && riffRanks[col] >= 1
            return (CGPoint(x: CGFloat(col) * colW + colW / 2, y: y), sounds)
        }
    }

    private func path(for l: EuclidLine, h: CGFloat, colW: CGFloat) -> Path {
        var path = Path()
        let pts = points(for: l, h: h, colW: colW).map { $0.0 }
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}

// MARK: - §4.3 NOTES picture

struct EuclideousRandomNotesPicture: View {
    let line: EuclidLine
    let original: EuclidLine?
    let accent: Color
    let riffRanks: [Int]

    private let keyLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "T2", "T"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let order = line.litOrderResolved
            let keyW = (w - 33) / 10
            VStack(spacing: 12) {
                if order.count == 0 {
                    Spacer()
                    Text("NO NOTES LIT").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundColor(Color(hex: 0x8A909A))
                    Spacer()
                } else {
                    playPattern(order: order, width: w, height: max(1, h - 40))
                }
                keyRow(order: order, keyW: keyW)
            }
            .frame(width: w, height: h)
        }
    }

    private func keyRow(order: EuclideousLitOrder, keyW: CGFloat) -> some View {
        let originalSet = original.map { o -> Set<Int> in Set((0..<o.litOrderResolved.count).map { o.litOrderResolved[$0] }) } ?? []
        let currentSet = Set((0..<order.count).map { order[$0] })
        return HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { pos in
                let lit = currentSet.contains(pos)
                let changed = original != nil && (currentSet.contains(pos) != originalSet.contains(pos))
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(lit ? accent.opacity(0.25) : Color(hex: 0x22252C))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lit ? accent : Color.clear, lineWidth: 1))
                        .overlay(changed ? RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xF2F4F7), lineWidth: 2) : nil)
                    VStack(spacing: 2) {
                        Text(keyLabels[pos]).font(.system(size: 10, weight: .heavy)).foregroundColor(lit ? Color(hex: 0xF2F4F7) : Color(hex: 0x5C626C))
                        if lit, let i = order.index(of: pos) {
                            Text("·\(i + 1)").font(.system(size: 8.5, weight: .bold)).foregroundColor(accent)
                        }
                    }
                }
                .frame(width: keyW, height: 40)
            }
        }
    }

    private func playPattern(order: EuclideousLitOrder, width: CGFloat, height: CGFloat) -> some View {
        let n = order.count
        let rows = min(8, max(1, n))
        let rowH = min(30, height / CGFloat(rows))
        let colW = width / 8
        return ZStack {
            ForEach(0..<8, id: \.self) { hitCol in
                let k = hitCol
                let list = euclideousRandomNotesPickListIndices(order: order, way: line.notesPlayAsResolved, k: k)
                ForEach(0..<n, id: \.self) { row in
                    let sounds = list.contains(row)
                    Circle().fill(sounds ? accent : Color(hex: 0x2A2D34))
                        .frame(width: sounds ? 14 : 4, height: sounds ? 14 : 4)
                        .position(x: CGFloat(hitCol) * colW + colW / 2, y: CGFloat(row) * rowH + rowH / 2)
                }
            }
        }
        .frame(height: CGFloat(rows) * rowH)
    }
}

/// §4.3's play-pattern dots: which lit-order ROWS (not pitches — the picture has no pool to resolve against)
/// a hit `k` sounds, via the engine's own `euclideousNotesWayPick` over a synthetic one-row-per-position list.
func euclideousRandomNotesPickListIndices(order: EuclideousLitOrder, way: EuclidNotesPlayAs, k: Int) -> Set<Int> {
    var list = EuclideousNotesList()
    for i in 0..<order.count { list.append(pitch: i, position: order[i], rank: 0) }
    let pick = euclideousNotesWayPick(list: list, way: way, k: k)
    var out = Set<Int>()
    for i in 0..<pick.count { out.insert(pick[i]) }
    return out
}
