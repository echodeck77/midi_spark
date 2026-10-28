//  CardBackViews.swift
//  CARD BACKS ferry (2026-10-28): the views behind the lane cards' rear panel — the header's PATTERN | MIX switch, and the back itself: the MIX strip, and per part (riff, notes) the XY pad, the OCT stepper, the live piano roll, the label
//  pill / invitations and the four output jacks.
//
//  SwiftUI only, like `MixPadPainter.swift`. Every frame, colour, size and word comes from the pure functions in `CardBack.swift` (tested in `CardBackTests`); these views only paint them and report what was touched.
//  The roll and the jacks share ONE 60 fps `TimelineView` per part, paused whenever the transport has been stopped for more than the activity's settle window — the page's own rule for every strike effect.

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

// MARK: - the header's PATTERN | MIX switch (§3.1)

struct EuclideousCardSideSwitch: View {
    let side: EuclideousCardSide
    let rowH: CGFloat
    var enabled = true
    let onTap: (EuclideousCardSide) -> Void

    var body: some View {
        typealias M = EuclideousCardSwitchMetrics
        let f = euclideousCardSwitchFrames(x: 0, rowMidY: rowH / 2)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: M.containerRadius).fill(Color(M.container))
                .frame(width: f.container.width, height: f.container.height).offset(x: f.container.minX, y: f.container.minY)
            segment(.pattern, frame: f.pattern, target: f.patternTarget)
            segment(.mix, frame: f.mix, target: f.mixTarget)
        }
        .frame(width: M.width, height: rowH, alignment: .topLeading)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousCardBackAX.switchGroup)
    }
    private func segment(_ s: EuclideousCardSide, frame: CGRect, target: CGRect) -> some View {
        typealias M = EuclideousCardSwitchMetrics
        let selected = side == s
        return ZStack(alignment: .topLeading) {
            if selected {
                RoundedRectangle(cornerRadius: M.segmentRadius).fill(Color(M.selectedFill)).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
            }
            Text(s == .pattern ? "PATTERN" : "MIX").font(heavyMono(M.fontSize)).tracking(M.tracking * M.fontSize).lineLimit(1)
                .foregroundColor(Color(selected ? M.selectedText : M.unselectedText))
                .frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
            Color.clear.contentShape(Rectangle()).frame(width: target.width, height: target.height).offset(x: target.minX, y: target.minY)
                .onTapGesture { if enabled, let to = euclideousCardSwitchTapTarget(tapped: s, current: side) { onTap(to) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousCardBackAX.segment(s))
                .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
        }
    }
}

// MARK: - the back

/// What one part's row shows and edits. The values are the ones the MIX pad reads (`euclideousMixPadValues`, `euclideousMixOctave`).
struct EuclideousCardBackPartInput: Equatable {
    var on: Bool
    var gate: Double
    var velocity: Int
    var octave: Int
    var mask: UInt8
}

struct EuclideousCardBackCallbacks {
    /// The XY pad's write: `(part, newStep, mutate)` — the page's `editStep`, one undo step per touch burst.
    var xy: (EuclideousCardPart, Bool, @escaping (inout EuclidLine) -> Void) -> Void
    var oct: (EuclideousCardPart, Int) -> Void
    var toggleOn: (EuclideousCardPart) -> Void
    var jack: (EuclideousCardPart, Int) -> Void
    var invite: (EuclideousCardPart, EuclideousCardInvitation) -> Void
}

/// Everything below the card's top row (the page draws the play tile, strip and SOLO tile there, the same view the front uses). `topRow` is that view, `size` the card.
struct EuclideousCardBackView: View {
    let lane: Int
    let size: CGSize
    let accent: Color
    let topRow: AnyView
    let riff: EuclideousCardBackPartInput
    let notes: EuclideousCardBackPartInput
    let laneHasHits: Bool
    /// Is the lane audible at this instant (not LANES-muted, not solo-silenced)? Asked inside the frame clock, so a mute cell turning over shows on the beat.
    let laneAudibleAt: (Date) -> Bool
    let dimRows: Bool
    let rolls: NoteRollLive
    let beatAt: (Date) -> Double
    let beatsPerBar: Double
    let tempo: Double
    let live: Bool
    let hocketRules: [HocketRule]
    let hocketLive: HocketLiveModel
    let callbacks: EuclideousCardBackCallbacks

    var body: some View {
        let layout = euclideousCardBackLayout(card: size)
        return ZStack(alignment: .topLeading) {
            topRow
                .frame(width: layout.card.width - 2 * EuclideousCardBackMetrics.inset, height: EuclideousLaneCardMetrics.cometRowH, alignment: .topLeading)
                .offset(x: EuclideousCardBackMetrics.inset, y: EuclideousCardBackMetrics.inset)
            ZStack(alignment: .topLeading) {   // a solo-silenced lane dims everything but the top row, once (the page's 42 %)
                strip(layout.strip)
                EuclideousCardBackPartRow(lane: lane, part: .riff, frames: layout.riff, input: riff, accent: accent, laneHasHits: laneHasHits, laneAudibleAt: laneAudibleAt, rolls: rolls,
                                          beatAt: beatAt, beatsPerBar: beatsPerBar, tempo: tempo, live: live, hocketRules: hocketRules, hocketLive: hocketLive, callbacks: callbacks)
                EuclideousCardBackPartRow(lane: lane, part: .notes, frames: layout.notes, input: notes, accent: accent, laneHasHits: laneHasHits, laneAudibleAt: laneAudibleAt, rolls: rolls,
                                          beatAt: beatAt, beatsPerBar: beatsPerBar, tempo: tempo, live: live, hocketRules: hocketRules, hocketLive: hocketLive, callbacks: callbacks)
            }
            .opacity(dimRows ? EuclideousLaneDimStyle.opacity : 1)
            .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: dimRows)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousCardBackAX.group(lane: lane))
    }

    /// §4.2: the "MIX" strip — lane100 at 12 %, the word in lane100.
    private func strip(_ r: CGRect) -> some View {
        typealias M = EuclideousCardBackMetrics
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: M.stripRadius).fill(accent.opacity(M.stripAlpha))
            Text("MIX").font(heavyMono(M.stripFont)).tracking(M.stripTracking * M.stripFont).foregroundColor(accent).padding(.leading, M.stripPadX)
        }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
        .accessibilityHidden(true)
    }
}

// MARK: one part's row

struct EuclideousCardBackPartRow: View {
    let lane: Int
    let part: EuclideousCardPart
    let frames: EuclideousCardBackPartFrames
    let input: EuclideousCardBackPartInput
    let accent: Color
    let laneHasHits: Bool
    let laneAudibleAt: (Date) -> Bool
    let rolls: NoteRollLive
    let beatAt: (Date) -> Double
    let beatsPerBar: Double
    let tempo: Double
    let live: Bool
    let hocketRules: [HocketRule]
    @ObservedObject var hocketLive: HocketLiveModel
    let callbacks: EuclideousCardBackCallbacks

    @State private var span = RollSpanTracker()

    private var partIndex: Int { 2 * lane + part.rawValue }
    private var silent: Bool { input.mask & 0x0F == 0 }
    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -frames.row.minX, dy: -frames.row.minY) }

    var body: some View {
        let invitation = euclideousCardInvitation(part: part, partOn: input.on, laneHasHits: laneHasHits)
        return ZStack(alignment: .topLeading) {
            EuclideousCardXYPad(frame: local(frames.xy).size, lane: lane, part: part, accent: accent, gate: input.gate, velocity: input.velocity, enabled: input.on,
                                onEditStep: { newStep, mutate in callbacks.xy(part, newStep, mutate) })
                .offset(x: local(frames.xy).minX, y: local(frames.xy).minY)
            EuclideousCardOct(size: local(frames.oct).size, accent: accent, part: part, value: input.octave, dimmed: !input.on, onSet: { callbacks.oct(part, $0) })
                .offset(x: local(frames.oct).minX, y: local(frames.oct).minY)
            rollAndJacks()
                .offset(x: local(frames.rollPanel).minX, y: local(frames.rollPanel).minY)
            // §5.4: the label pill is the part's on/off switch; §5.6: the invitation, centred in the roll, at full strength over the dim
            labelPill
                .offset(x: local(frames.rollPanel).minX, y: local(frames.rollPanel).minY)
            if let invitation { invitationPill(invitation).offset(x: local(frames.rollPanel).minX, y: local(frames.rollPanel).minY) }
            jackTargets
        }
        .frame(width: frames.row.width, height: frames.row.height, alignment: .topLeading)
        .offset(x: frames.row.minX, y: frames.row.minY)
        .accessibilityElement(children: .contain)
    }

    // MARK: roll + jacks in one frame clock
    private func rollAndJacks() -> some View {
        let panel = frames.rollPanel
        let roll = CGRect(x: 0, y: 0, width: frames.roll.width, height: frames.roll.height)
        let strip = CGRect(x: 0, y: frames.jackStrip.minY - panel.minY, width: panel.width, height: frames.jackStrip.height)
        let cells = frames.jackCells.map { $0.offsetBy(dx: -panel.minX, dy: -panel.minY) }
        let lights = frames.jackLights.map { $0.offsetBy(dx: -panel.minX, dy: -panel.minY) }
        let sockets = frames.jackSockets.map { $0.offsetBy(dx: -panel.minX, dy: -panel.minY) }
        let letters = frames.jackLetters.map { $0.offsetBy(dx: -panel.minX, dy: -panel.minY) }
        let seam = CGRect(x: 0, y: frames.seam.minY - panel.minY, width: panel.width, height: frames.seam.height)
        let model = rolls
        let tracker = span
        let laneIdx = lane, p = partIndex, on = input.on, mask = input.mask, hasHits = laneHasHits, audibleAt = laneAudibleAt, tempoNow = tempo, bpb = beatsPerBar, beatOf = beatAt
        let dimmed = !on
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !live)) { tl in
            Canvas { ctx, sz in
                let now = beatOf(tl.date)
                let laneAud = audibleAt(tl.date)
                let audible = on && mask & 0x0F != 0 && laneAud && hasHits
                drawPanel(&ctx, size: sz, roll: roll, strip: strip, lane: laneIdx)
                drawRoll(&ctx, roll: roll, model: model.model, part: p, lane: laneIdx, now: now, bpb: bpb, date: tl.date, tracker: tracker, on: on, hasHits: hasHits, laneAudible: laneAud, silent: mask & 0x0F == 0)
                drawJacks(&ctx, seam: seam, cells: cells, lights: lights, sockets: sockets, letters: letters, lane: laneIdx, mask: mask, on: on, audible: audible, model: model.model, part: p, now: now, tempo: tempoNow)
            }
            .frame(width: panel.width, height: panel.height)
        }
        .frame(width: panel.width, height: panel.height)
        .opacity(dimmed ? 1 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousCardBackAX.roll(part, silent: silent || !on))
    }

    private func drawPanel(_ ctx: inout GraphicsContext, size: CGSize, roll: CGRect, strip: CGRect, lane: Int) {
        typealias M = EuclideousCardBackMetrics
        let r = EuclideousRollMetrics.topRadius
        let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
        ctx.fill(shape, with: .color(Color(M.fillColor)))
        ctx.stroke(shape, with: .color(accent.opacity(M.borderAlpha)), lineWidth: M.borderWidth)
    }

    private func drawRoll(_ ctx: inout GraphicsContext, roll: CGRect, model: NoteRollModel, part p: Int, lane: Int, now: Double, bpb: Double, date: Date, tracker: RollSpanTracker,
                          on: Bool, hasHits: Bool, laneAudible: Bool, silent: Bool) {
        typealias R = EuclideousRollMetrics
        var layer = ctx
        let clip = Path(roundedRect: roll, cornerRadius: R.topRadius)
        layer.clip(to: clip)
        let live = laneAudible && on && hasHits
        layer.opacity = on ? 1 : 0.42
        layer.fill(Path(roll), with: .color(Color(euclideousRollGround(lane: lane, laneAudible: laneAudible, partOn: on, laneHasHits: hasHits))))
        let window = Double(R.windowBars) * max(1, bpb)
        let notes = model.notes(part: p, from: now - window, to: now, now: now)
        let target = euclideousRollTargetSpan(pitches: notes.map { Int($0.pitch) })
        let spanNow = tracker.span(target: target, date: date)
        let rows = euclideousRollRows(span: spanNow, top: roll.minY, height: roll.height)
        for row in rows where row.isBlackKey { layer.fill(Path(CGRect(x: roll.minX, y: row.y, width: roll.width, height: row.height)), with: .color(Color(R.blackKeyRow))) }
        for line in euclideousRollGrid(nowBeat: now, beatsPerBar: bpb, left: roll.minX, width: roll.width) {
            layer.fill(Path(CGRect(x: line.x - 0.5, y: roll.minY, width: 1, height: roll.height)), with: .color(Color.white.opacity(line.alpha)))
        }
        for n in notes where n.onBeat <= now {
            guard let rect = euclideousRollNoteRect(pitch: Int(n.pitch), onBeat: n.onBeat, offBeat: n.endBeat, nowBeat: now, beatsPerBar: bpb, span: spanNow, roll: roll) else { continue }
            let sounding = n.endBeat.map { $0 > now } ?? true
            let state: EuclideousRollNoteState = n.outs == 0 ? .silent : (sounding ? .sounding : .ended)
            let look = euclideousRollNoteLook(lane: lane, velocity: Int(n.velocity), state: state)
            let path = Path(roundedRect: rect, cornerRadius: R.noteRadius)
            if let fill = look.fill {
                if look.glowRadius > 0 {
                    layer.drawLayer { g in
                        g.addFilter(.shadow(color: Color(HocketColor(HocketPalette.lane100(lane).hex, look.glowAlpha)), radius: look.glowRadius))
                        g.fill(path, with: .color(Color(fill)))
                    }
                } else { layer.fill(path, with: .color(Color(fill))) }
            } else if let border = look.border {
                layer.stroke(path, with: .color(Color(border)), lineWidth: look.borderWidth)
            }
        }
        let head = euclideousRollPlayhead(lane: lane, audible: live, roll: roll)
        layer.fill(Path(head.rect), with: .color(Color(head.colour)))
        ctx.stroke(Path(roundedRect: roll, cornerRadius: R.topRadius), with: .color(Color(R.border)), lineWidth: R.borderWidth)
        _ = silent
    }

    private func drawJacks(_ ctx: inout GraphicsContext, seam: CGRect, cells: [CGRect], lights: [CGRect], sockets: [CGRect], letters: [CGRect], lane: Int, mask: UInt8, on: Bool, audible: Bool,
                           model: NoteRollModel, part p: Int, now: Double, tempo: Double) {
        typealias J = EuclideousJackMetrics
        let lane100 = HocketPalette.lane100(lane)
        var seamSince = Double.infinity
        for o in 0..<4 {
            let plugged = euclideousJackIsPlugged(mask: mask, output: o)
            let look = euclideousJackLook(lane: lane, plugged: plugged, partOn: on)
            let last = model.lastOnBeatByOutput[p][o]
            let since = last.isFinite ? max(0, (now - last) * 60 / max(1, tempo)) : Double.infinity
            seamSince = min(seamSince, plugged && on ? since : Double.infinity)
            let act = euclideousJackActivity(sinceNoteOn: since.isFinite ? since : -1)
            let cell = cells[o]
            // the cell: its fill (a plugged, on part), warming toward the lane colour on a note-on
            ctx.fill(Path(cell), with: .color(Color(J.cellBase)))
            if look.cellFill != nil {
                ctx.fill(Path(cell), with: .color(Color(euclideousCardMix(J.cellBase, toward: lane100, act.cellMix))))
            }
            if o > 0 { ctx.fill(Path(CGRect(x: cell.minX - 0.5, y: cell.minY, width: 1, height: cell.height)), with: .color(Color(J.stripBorder))) }
            // the light
            let lightColour = act.amount > 0 && plugged && on ? euclideousCardMix(look.light, toward: HocketColor(lane100.hex, 1), act.lightMix) : look.light
            if act.glowRadius > 0 && plugged && on {
                ctx.drawLayer { g in
                    g.addFilter(.shadow(color: Color(HocketColor(lane100.hex, act.glowAlpha)), radius: act.glowRadius))
                    g.fill(Path(ellipseIn: lights[o]), with: .color(Color(lightColour)))
                }
            } else { ctx.fill(Path(ellipseIn: lights[o]), with: .color(Color(lightColour))) }
            // the socket and (when plugged) the plug
            let s = sockets[o]
            ctx.fill(Path(ellipseIn: CGRect(x: s.midX - J.socketRadius, y: s.midY - J.socketRadius, width: 2 * J.socketRadius, height: 2 * J.socketRadius)), with: .color(Color(J.socketDisc)))
            ctx.stroke(Path(ellipseIn: CGRect(x: s.midX - J.socketRadius, y: s.midY - J.socketRadius, width: 2 * J.socketRadius, height: 2 * J.socketRadius)), with: .color(Color(look.ring)), lineWidth: J.ringWidth)
            ctx.fill(Path(roundedRect: CGRect(x: s.midX - J.notch.width / 2, y: s.minY + 1.5, width: J.notch.width, height: J.notch.height), cornerRadius: J.notchRadius), with: .color(Color(J.notchColor)))
            for pin in J.pins { ctx.fill(Path(ellipseIn: CGRect(x: s.minX + pin.x - J.pinSize / 2, y: s.minY + pin.y - J.pinSize / 2, width: J.pinSize, height: J.pinSize)), with: .color(Color(J.pinColor))) }
            if let plug = look.plug {
                ctx.fill(Path(ellipseIn: CGRect(x: s.midX - J.plugRadius, y: s.midY - J.plugRadius, width: 2 * J.plugRadius, height: 2 * J.plugRadius)), with: .color(Color(plug)))
                if let cap = look.plugCap { ctx.fill(Path(ellipseIn: CGRect(x: s.midX - J.capRadius, y: s.midY - J.capRadius, width: 2 * J.capRadius, height: 2 * J.capRadius)), with: .color(Color(cap))) }
            }
            // the letter
            ctx.draw(Text(euclideousJackLetters[o]).font(heavyMono(EuclideousCardBackMetrics.letterFont)).foregroundColor(Color(look.letter)), at: CGPoint(x: letters[o].minX, y: letters[o].midY), anchor: .leading)
        }
        // §7.6: the seam between the roll and the jack strip
        let seamLook = euclideousSeamLook(lane: lane, audible: audible, sinceNoteOn: seamSince.isFinite ? seamSince : -1)
        if seamLook.glowRadius > 0 {
            ctx.drawLayer { g in
                g.addFilter(.shadow(color: Color(HocketColor(lane100.hex, seamLook.glowAlpha)), radius: seamLook.glowRadius))
                g.fill(Path(seam), with: .color(Color(seamLook.colour)))
            }
        } else { ctx.fill(Path(seam), with: .color(Color(seamLook.colour))) }
    }

    // MARK: the label pill (§5.4) and the invitation (§5.6)
    private var labelPill: some View {
        typealias L = EuclideousCardLabelMetrics
        let roll = CGRect(x: 0, y: 0, width: frames.roll.width, height: frames.roll.height)
        let f = euclideousCardLabelFrames(roll: roll, part: part)
        let lit = hocketRules.contains(where: { $0.isLit })
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: L.radius).fill(Color(L.fill)).frame(width: f.pill.width, height: f.pill.height).offset(x: f.pill.minX, y: f.pill.minY)
            ZStack {
                if lit {
                    HocketPartGlyph(shape: part == .notes ? .bar : .square, on: input.on, fill: accent, lane: lane, rules: hocketRules, live: hocketLive, ground: Color(hex: 0x131519))
                } else {
                    EuclideousTabGlyphView(shape: part == .notes ? .bar : .square, on: input.on, fill: accent)
                }
            }
            .frame(width: f.glyph.width, height: f.glyph.height).offset(x: f.glyph.minX, y: f.glyph.minY)
            Text(part.label).font(heavyMono(L.font)).tracking(L.tracking * L.font).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundColor(Color(hex: input.on ? 0xF2F4F7 : 0xAAB0BA))
                .frame(width: f.text.width, height: f.text.height, alignment: .leading).offset(x: f.text.minX, y: f.text.minY)
                .allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).frame(width: f.target.width, height: f.target.height).offset(x: f.target.minX, y: f.target.minY)
                .onTapGesture { callbacks.toggleOn(part) }
                .accessibilityElement(children: .ignore)
                .hocketPartAX(base: EuclideousCardBackAX.partToggle(part, on: input.on), lane: lane, notes: part == .notes, partOff: !input.on, rules: hocketRules, live: hocketLive)
                .accessibilityAddTraits(.isButton)
        }
        .opacity(input.on ? 1 : L.offAlpha)
        .frame(width: frames.rollPanel.width, height: frames.rollPanel.height, alignment: .topLeading)
    }
    private func invitationPill(_ kind: EuclideousCardInvitation) -> some View {
        typealias I = EuclideousCardInvitationMetrics
        let roll = CGRect(x: 0, y: 0, width: frames.roll.width, height: frames.roll.height)
        let f = euclideousCardInvitationFrames(roll: roll, kind)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: I.radius).fill(accent.opacity(I.fillAlpha)).frame(width: f.pill.width, height: f.pill.height).offset(x: f.pill.minX, y: f.pill.minY)
            RoundedRectangle(cornerRadius: I.radius).strokeBorder(accent, lineWidth: I.borderWidth).frame(width: f.pill.width, height: f.pill.height).offset(x: f.pill.minX, y: f.pill.minY)
            Path { p in
                p.move(to: CGPoint(x: f.plus.minX, y: f.plus.midY)); p.addLine(to: CGPoint(x: f.plus.maxX, y: f.plus.midY))
                p.move(to: CGPoint(x: f.plus.midX, y: f.plus.minY)); p.addLine(to: CGPoint(x: f.plus.midX, y: f.plus.maxY))
            }.stroke(accent, style: StrokeStyle(lineWidth: I.plusStroke, lineCap: .round))
            Text(kind.label).font(heavyMono(I.font)).tracking(I.tracking * I.font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundColor(Color(hex: 0xF2F4F7))
                .frame(width: f.text.width, height: f.text.height, alignment: .leading).offset(x: f.text.minX, y: f.text.minY)
            Color.clear.contentShape(Rectangle()).frame(width: f.target.width, height: f.target.height).offset(x: f.target.minX, y: f.target.minY)
                .onTapGesture { callbacks.invite(part, kind) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousCardBackAX.invitation(kind))
                .accessibilityAddTraits(.isButton)
        }
        .frame(width: frames.rollPanel.width, height: frames.rollPanel.height, alignment: .topLeading)
    }

    // MARK: the jacks' touch cells (§7.4)
    private var jackTargets: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { o in
                let cell = local(frames.jackCells[o])
                let plugged = euclideousJackIsPlugged(mask: input.mask, output: o)
                Color.clear.contentShape(Rectangle()).frame(width: cell.width, height: cell.height).offset(x: cell.minX, y: cell.minY)
                    .onTapGesture { callbacks.jack(part, o) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EuclideousCardBackAX.jack(part, output: o, plugged: plugged))
                    .accessibilityAddTraits(.isButton)
                    .ringToggleTrait()
            }
        }
    }
}

/// The roll's drawn pitch span: it grows at once to take in a note outside it and shrinks over 300 ms after the notes have left (`euclideousRollDisplaySpan`). A class held in @State, mutated while drawing — the roll's own state, nothing else reads it.
final class RollSpanTracker {
    private var drawn: EuclideousRollSpan? = nil
    private var shrinkStart: Date? = nil
    private var lastTarget: EuclideousRollSpan? = nil
    func span(target: EuclideousRollSpan, date: Date) -> EuclideousRollSpan {
        guard let current = drawn else { drawn = target; lastTarget = target; return target }
        let narrower = target.lo > current.lo || target.hi < current.hi
        if narrower { if shrinkStart == nil || lastTarget != target { shrinkStart = date } } else { shrinkStart = nil }
        lastTarget = target
        let elapsed = shrinkStart.map { date.timeIntervalSince($0) } ?? 0
        let next = euclideousRollDisplaySpan(target: target, drawn: current, shrinkElapsed: narrower ? elapsed : 0)
        drawn = narrower && elapsed >= EuclideousRollMetrics.shrinkSeconds ? target : next
        return drawn ?? next
    }
}

// MARK: - the XY pad (§6)

struct EuclideousCardXYPad: View {
    let frame: CGSize
    let lane: Int
    let part: EuclideousCardPart
    let accent: Color
    let gate: Double
    let velocity: Int
    let enabled: Bool
    let onEditStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void

    @State private var burst = EuclideousPadUndoBurst()
    @State private var touching = false
    @State private var startLocation: CGPoint? = nil
    @State private var lastWritten: (gate: Double, velocity: Int)? = nil
    @State private var lastShortTapAt: Double? = nil
    private func now() -> Double { Date().timeIntervalSinceReferenceDate }
    private var pad: CGRect { CGRect(origin: .zero, size: frame) }

    var body: some View {
        typealias X = EuclideousCardXYMetrics
        let dot = euclideousCardXYDot(gate: gate, velocity: velocity, in: pad)
        let texts = euclideousCardXYTexts(gate: gate, velocity: velocity)
        let cross = euclideousCardXYCrosshair(dot: dot, in: pad)
        let fill = euclideousCardXYFillRect(dot: dot, in: pad)
        let d = X.dot + (touching ? 4 : 0)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: X.radius).fill(Color(X.well))
            RoundedRectangle(cornerRadius: X.radius).strokeBorder(Color(X.border), lineWidth: 1)
            Group {
                Path(fill).fill(accent.opacity(X.fillAlpha))
                Path(cross.horizontal).fill(accent.opacity(X.crosshairAlpha)); Path(cross.vertical).fill(accent.opacity(X.crosshairAlpha))
            }
            .clipShape(RoundedRectangle(cornerRadius: X.radius))
            Text(texts.vel).font(heavyMono(X.textFont)).tracking(X.textTracking * X.textFont).foregroundColor(Color(X.text)).lineLimit(1)
                .padding(.leading, X.textInset).padding(.top, X.textInset).allowsHitTesting(false)
            Text(texts.gate).font(heavyMono(X.textFont)).tracking(X.textTracking * X.textFont).foregroundColor(Color(X.text)).lineLimit(1)
                .frame(width: frame.width, height: frame.height, alignment: .bottomTrailing).padding(.trailing, 0)
                .offset(x: -X.textInset, y: -X.textInset).allowsHitTesting(false)
            ZStack {
                Circle().fill(EuclideousMixPalette.puckRing).frame(width: d + 2 * X.dotRing, height: d + 2 * X.dotRing)
                Circle().fill(accent).frame(width: d, height: d)
            }
            .position(dot).allowsHitTesting(false)
        }
        .frame(width: frame.width, height: frame.height)
        .opacity(enabled ? 1 : 0.42)
        .contentShape(Rectangle())
        .allowsHitTesting(enabled)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !touching { touching = true; startLocation = drag.location; lastWritten = nil; burst.touchDown(at: now()) }
                apply(drag.location)
            }
            .onEnded { drag in
                let start = startLocation ?? drag.location
                let moved = hypot(drag.location.x - start.x, drag.location.y - start.y)
                touching = false; startLocation = nil
                burst.touchEnd(at: now())
                if moved <= 4 {
                    if let last = lastShortTapAt, now() - last <= EuclideousPadUndoBurst.continueWithin { lastShortTapAt = nil; reset() } else { lastShortTapAt = now() }
                } else { lastShortTapAt = nil }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousCardBackAX.xy(part, velocity: velocity, gate: gate))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            write(gate: gate, velocity: euclideousMixVelocityStep(velocity, up: direction == .increment), newStepAlways: true)
        }
        .accessibilityAction(named: "Longer gate") { if enabled { write(gate: euclideousMixGateStep(gate, longer: true), velocity: velocity, newStepAlways: true) } }
        .accessibilityAction(named: "Shorter gate") { if enabled { write(gate: euclideousMixGateStep(gate, longer: false), velocity: velocity, newStepAlways: true) } }
        .accessibilityAction(named: "Reset") { if enabled { resetAlways() } }
    }
    private func apply(_ p: CGPoint) {
        let v = euclideousCardXYValues(at: p, in: pad)
        if let last = lastWritten, abs(last.gate - v.gate) < 1e-9, last.velocity == v.velocity { return }
        lastWritten = v
        if abs(v.gate - gate) < 1e-9, v.velocity == velocity { return }
        write(gate: v.gate, velocity: v.velocity, newStepAlways: false)
    }
    private func write(gate g: Double, velocity v: Int, newStepAlways: Bool) {
        let newStep = newStepAlways ? true : burst.nextWriteNeedsNewStep()
        let notes = part == .notes
        onEditStep(newStep) { l in _ = euclideousMixPadWriteIfEnabled(&l, notes: notes, gate: g, velocity: v) }
    }
    private func reset() {
        if abs(gate - 0.9) < 1e-9, velocity == 100 { return }
        let newStep = burst.nextWriteNeedsNewStep()
        let notes = part == .notes
        onEditStep(newStep) { l in _ = euclideousMixPadResetIfEnabled(&l, notes: notes) }
    }
    private func resetAlways() {
        let notes = part == .notes
        onEditStep(true) { l in _ = euclideousMixPadResetIfEnabled(&l, notes: notes) }
    }
}

// MARK: - OCT (§6.3)

struct EuclideousCardOct: View {
    let size: CGSize
    let accent: Color
    let part: EuclideousCardPart
    let value: Int
    let dimmed: Bool
    let onSet: (Int) -> Void

    var body: some View {
        typealias O = EuclideousCardOctMetrics
        let f = euclideousCardOctFrames(oct: CGRect(origin: .zero, size: size), valueChars: euclideousCardOctValueText(value).count)
        let minus = euclideousMixOctaveNext(value, up: false), plus = euclideousMixOctaveNext(value, up: true)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: O.radius).fill(Color(O.fill)).frame(width: size.width, height: size.height)
            glyph("minus", f.minusGlyph, enabled: minus != nil)
            glyph("plus", f.plusGlyph, enabled: plus != nil)
            Text("OCT").font(heavyMono(O.captionFont)).tracking(O.captionTracking * O.captionFont).foregroundColor(Color(O.captionColor)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: f.caption.width, height: f.caption.height, alignment: .leading).offset(x: f.caption.minX, y: f.caption.minY)
            Text(euclideousCardOctValueText(value)).font(heavyMono(O.valueFont)).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundColor(euclideousCardOctValueIsLaneColour(value) ? accent : Color(O.zeroColor))
                .frame(width: f.value.width, height: f.value.height, alignment: .leading).offset(x: f.value.minX, y: f.value.minY)
            Color.clear.contentShape(Rectangle()).frame(width: f.minusZone.width, height: f.minusZone.height).offset(x: f.minusZone.minX, y: f.minusZone.minY)
                .onTapGesture { if let m = minus { onSet(m) } }
            Color.clear.contentShape(Rectangle()).frame(width: f.plusZone.width, height: f.plusZone.height).offset(x: f.plusZone.minX, y: f.plusZone.minY)
                .onTapGesture { if let p = plus { onSet(p) } }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousCardBackAX.oct(part, value: value))
        .accessibilityValue(euclideousMixOctaveSpoken(value))
        .accessibilityAdjustableAction { direction in
            if let n = euclideousMixOctaveNext(value, up: direction == .increment) { onSet(n) }
        }
    }
    private func glyph(_ name: String, _ r: CGRect, enabled: Bool) -> some View {
        Image(systemName: name).font(.system(size: EuclideousCardOctMetrics.glyph, weight: .heavy))
            .foregroundColor(enabled ? Color(EuclideousCardOctMetrics.glyphColor) : EuclideousMixPalette.glyphDisabled)
            .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
    }
}
