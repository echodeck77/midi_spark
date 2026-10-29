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
    var riffColumns: Int = 8   // POLY RIFF (2026-10-29): the riff grid's width — 8 (MONO) or 16 (POLY, `riffRanks` = the top rank starting on each column)
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
    // §4.4 / §3.6: the live clock, for the RHYTHM picture's own playhead ring and the waiting caption's
    // beat-progress dots — the SAME host-beat extrapolation every other live view on this page uses
    // (`clock` in EuclideousPage), never a second clock formula (CLAUDE.md's own named recurring bug).
    let clockPlaying: Bool
    let clockAnchor: Double
    let clockAnchorAt: Date
    let clockTempo: Double
    let clockBeatsPerBar: Double
    // This tab's own currently-queued roll landing beat, if any (nil when nothing's waiting).
    let landingBeat: Double?
    // STRIKE FEEDBACK (2026-10-24 review): the SAME PULSE feed the rest of the page reads, so the pictures
    // flash on a hit the way every other surface does (header rings, riff arrows, MIX, the comet strip) —
    // the review found random mode was the one place with no velocity-scaled strike feedback at all.
    // The card computes the two layers' glow once (riff / notes) and hands each picture a plain 0…1 value,
    // keeping "this file only paints": the pictures never touch the feed themselves.
    let pulseFeed: EuclideousPulseFeed
    let pulseScale: Double
    /// Stays true for 1.5 s after the transport stops (`EuclideousPage.pulseLive`) so the last strikes fade
    /// out rather than freezing — the card's own clock now rides this instead of a flat `clockPlaying` gate.
    let pulseLive: Bool
    /// LANE LOCK 9.1: a locked lane still shows its picture, selector and caption, but THROW and TWEAK draw at 40 % and take no input ("LOCKED · UNLOCK TO ROLL" replaces the idle caption).
    var laneLocked: Bool = false
    /// Lane-box buttons ferry (2026-10-22): the SAME play/SOLO controls the normal-mode lane card has, top
    /// left/right, matching normal mode's size and style exactly — `onToggleEnabled` reuses `EuclidLane
    /// Box`'s own callback shape; `soloButtonView` IS the exact `AnyView` the normal card builds (same
    /// `EuclideousSoloButton`/`EuclideousSoloPressable`, not a re-derived one).
    let onToggleEnabled: () -> Void
    let soloButtonView: AnyView


    private func currentBeat(at date: Date) -> Double {
        clockPlaying ? clockAnchor + date.timeIntervalSince(clockAnchorAt) * clockTempo / 60.0 : clockAnchor
    }

    /// The flash `f` (§1, τ0.16 — the main visible decay) of this lane's latest strike on a layer, scaled by
    /// its velocity, `now` seconds on; 0 when nothing's fading. The exact envelope every other PULSE surface
    /// reads (`euclideousFXFlashCells`, the MIX pads, the comet strip), never a second curve.
    private func strikeGlow(now: Double, riff: Bool) -> Double {
        guard let s = pulseFeed.latestHappened(lane: lane, now: now, riff: riff) else { return 0 }
        let vel = riff ? Int(s.riffVel) : Int(s.notesVel)
        return euclideousPulseEnvelopes(velocity: vel, seconds: now - s.onsetAt, scale: pulseScale).f
    }

    var body: some View {
        // §9.1's own idiom via `pulseLive`: stay live while running AND for the 1.5 s strike-settle window
        // after a stop, then idle — so a hit's glow fades out instead of freezing (the strike-feedback review,
        // 2026-10-24). The playhead itself still freezes correctly: `currentBeat` returns the frozen anchor when
        // stopped, so these extra settle-window frames only fade the glows, they don't move the playhead.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !pulseLive)) { tl in
            let beat = currentBeat(at: tl.date)
            let now = tl.date.timeIntervalSinceReferenceDate
            let riffGlow = strikeGlow(now: now, riff: true)
            let notesGlow = strikeGlow(now: now, riff: false)
            VStack(spacing: 0) {
                // Lane-box buttons ferry: PLAY top-left / SOLO top-right, the card's own 44pt row —
                // same height/style as the normal lane card's step row, so the two modes read as one family.
                HStack(spacing: 0) {
                    EuclidCompactPlayButton(on: line.enabledResolved, accent: accent, onToggle: onToggleEnabled)
                    Spacer(minLength: 0)
                    soloButtonView
                }
                .frame(height: 44)
                .padding(.top, 10)
                selectorRow.frame(height: 32).padding(.top, 6)
                Spacer(minLength: 2)
                picture(beat: beat, riffGlow: riffGlow, notesGlow: notesGlow).frame(height: max(1, height - 58 - 96 - 50))
                    .padding(.horizontal, 8)   // + the VStack's own outer 10pt below = a flat 18pt net inset
                    .contentShape(Rectangle())
                    // §5.6: only while the selected tab has an undecided roll — a decided tab's picture isn't a hold target.
                    .modifier(EuclideousRandomHoldModifier(enabled: state.isUndecided, onBegan: onHoldBegan, onEnded: onHoldEnded))
                    // §5.7/§5.8: VoiceOver can't long-press, so the hold becomes two explicit named actions.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(pictureAccessibilityLabel)
                    .modifier(EuclideousRandomHoldAction(undecided: state.isUndecided, holding: holding, onBegan: onHoldBegan, onEnded: onHoldEnded))
                caption.frame(height: 14).padding(.top, 6)
                HStack(spacing: 0) { hintRow; Spacer(minLength: 0); progressDots(beat: beat) }.frame(height: 10).padding(.top, 2)
                Spacer(minLength: 2)
                buttonRow.frame(height: 44).padding(.bottom, 10)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1B1D23)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(holding ? 0.9 : 0.45), lineWidth: 1))
        }
    }

    // MARK: §3.2 selector

    private var selectorRow: some View {
        HStack(spacing: 0) {
            Circle().fill(accent).frame(width: 24, height: 24)
                .overlay(Text("\(lane + 1)").font(.system(size: 12, weight: .heavy)).foregroundColor(Color(hex: 0x0D0F14)))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach([EuclideousRandomTab.rhythm, .riff, .notes], id: \.rawValue) { t in
                    segment(t).frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)   // §3.2: spans the row (x after the circle to width − 10), not just its content
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

    @ViewBuilder private func picture(beat: Double, riffGlow: Double, notesGlow: Double) -> some View {
        switch tab {
        case .rhythm: EuclideousRandomRhythmPicture(line: line, original: state.original, accent: accent, beat: beat, strikeGlow: riffGlow)
        case .riff: EuclideousRandomRiffPicture(line: line, original: state.original, accent: accent, riffRanks: riffRanks, strikeGlow: riffGlow, columns: riffColumns)
        case .notes: EuclideousRandomNotesPicture(line: line, original: state.original, accent: accent, riffRanks: riffRanks, lane: lane, strikeGlow: notesGlow)
        }
    }

    /// §5.7: what the picture shows, spoken — since VoiceOver can't read a diagram.
    private var pictureAccessibilityLabel: String {
        switch tab {
        case .rhythm:
            let steps = max(2, min(16, line.steps))
            let offset = euclideousRandomDisplayedOffset(rotate: line.rotate, steps: steps)
            return "\(line.pulses) of \(steps) steps" + (offset > 0 ? ", offset \(offset)" : "")
        case .riff:
            let dirName: String
            switch line.euclideousRiffDirResolved {
            case .forward: dirName = "forward"
            case .reverse: dirName = "reverse"
            case .pendulum: dirName = "pendulum"
            case .pingpong: dirName = "ping-pong"
            case .random, .drunk: dirName = "forward"   // coerced to FWD (RIFF WALK ferry, 2026-10-13) — never actually resolved
            }
            return "Riff walk, \(dirName), length \(line.riffLengthResolved)"
        case .notes:
            let order = line.litOrderResolved
            return order.count == 0 ? "No notes lit" : "\(order.count) notes lit"
        }
    }

    // MARK: §3.6 beat-progress dots — one per beat of the bar the queued roll lands on, filled up to now.

    @ViewBuilder private func progressDots(beat: Double) -> some View {
        if state.waiting != nil, let landingBeat, clockBeatsPerBar >= 1 {
            let bars = max(1, Int(clockBeatsPerBar.rounded()))
            let barStart = landingBeat - clockBeatsPerBar
            let filled = min(bars, max(0, Int((beat - barStart).rounded(.down)) + 1))
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    Circle().fill(i < filled ? accent : Color.clear)
                        .overlay(Circle().strokeBorder(accent, lineWidth: 1))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: §3.4 hint row — teaches the hold; only while the picture is actually a hold target.

    @ViewBuilder private var hintRow: some View {
        if state.isUndecided {
            Text(holding ? "PLAYING THE ORIGINAL · LET GO FOR THE NEW ONE" : "HOLD THE PICTURE TO HEAR THE ORIGINAL")
                .font(.system(size: 7.5, weight: .bold)).tracking(0.6)
                .foregroundColor(holding ? accent : Color(hex: 0x5C626C))
                .lineLimit(1).truncationMode(.tail)
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
        // §3.4's own hint row carries the held-state message now — the caption keeps showing the roll's
        // own tag underneath a hold, same as it does while not held.
        if state.isUndecided {
            var s = state.tag
            if state.goes >= 2 { s += "  ·  \(state.goes) GOES" }
            return s
        }
        if let decidedAt = state.decidedAt, Date().timeIntervalSince(decidedAt) < 8 {
            // §5.4: a throw/tweak that found nothing legal to change stamps `decidedAt` too (even on an
            // already-decided tab, the common case), so it shares this same short display window instead
            // of never showing at all. `euclideousRandomBack` clears `tag` to "" when it queues a BACK, so
            // an empty tag otherwise always means that's what landed; KEEP never touches `tag`.
            if state.tag == "NOTHING TO CHANGE" { return state.tag }
            return state.tag.isEmpty ? "BACK TO THE ORIGINAL" : "KEPT"
        }
        let layerOff: Bool
        switch tab { case .riff: layerOff = !line.riffOnResolved; case .notes: layerOff = !euclideousNotesLayerIsOn(line); case .rhythm: layerOff = false }
        if layerOff { return tab == .notes ? "THE NOTES LAYER IS OFF · YOU WON'T HEAR THIS" : "THE RIFF LAYER IS OFF · YOU WON'T HEAR THIS" }
        return euclideousLockRandomIdleCaption(laneLocked: laneLocked)
    }

    private var captionColor: Color {
        if state.waiting != nil { return accent }
        if state.isUndecided { return Color(hex: 0xF2F4F7) }
        if let decidedAt = state.decidedAt, Date().timeIntervalSince(decidedAt) < 8 {
            return state.tag == "NOTHING TO CHANGE" ? Color(hex: 0x8A909A) : accent
        }
        let layerOff: Bool
        switch tab { case .riff: layerOff = !line.riffOnResolved; case .notes: layerOff = !euclideousNotesLayerIsOn(line); case .rhythm: layerOff = false }
        return layerOff ? Color(hex: 0xFFB454) : Color(hex: 0x8A909A)
    }

    // MARK: §3.7 buttons

    private var buttonRow: some View {
        HStack(spacing: 6) {
            button("THROW", glyph: "die.face.4", tint: accent, action: onThrow, dashed: state.waiting == .throwing, rollLocked: laneLocked)
            button("TWEAK", glyph: "waveform.path", tint: accent, action: onTweak, dashed: state.waiting == .tweaking, rollLocked: laneLocked)
            if state.isUndecided {
                button("BACK", glyph: "arrow.uturn.backward", tint: Color(hex: 0xAAB0BA), action: onBack, dashed: state.waiting == .back)
                button("KEEP", glyph: "checkmark", tint: nil, action: onKeep, dashed: false, filled: true)
            }
        }
    }

    private func button(_ title: String, glyph: String, tint: Color?, action: @escaping () -> Void, dashed: Bool, filled: Bool = false, rollLocked: Bool = false) -> some View {
        let labelColor = filled ? Color(hex: 0x0D0F14) : Color(hex: 0xF2F4F7)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: state.isUndecided ? 16 : 18))
                    .foregroundColor(filled ? Color(hex: 0x0D0F14) : (tint ?? Color(hex: 0xF2F4F7)))
                Text(title).font(.system(size: 11, weight: .heavy)).tracking(0.9)
                    .foregroundColor(labelColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(filled ? accent : Color(hex: 0x2A2D34)))
            // The "waiting to land" border now MARCHES, matching the dice's own marching-ants ring (the
            // same "something is pending" signal) — `euclideousMarchingAntsPhase` with period 7 for this
            // [4,3] dash. Its own always-running TimelineView (never paused): the roll is still pending
            // even with the transport stopped, exactly as the dice ring keeps crawling then.
            .overlay(waitingBorder(dashed))
        }
        .buttonStyle(.plain)
        .disabled(rollLocked)
        .opacity(rollLocked ? 0.4 : 1)
        .accessibilityLabel(buttonAccessibilityLabel(title) + (rollLocked ? ", locked" : ""))
    }

    @ViewBuilder private func waitingBorder(_ dashed: Bool) -> some View {
        if dashed {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3], dashPhase: euclideousMarchingAntsPhase(tl.date, period: 7)))
                    .foregroundColor(accent)
                    .padding(1)
            }
        }
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

/// §5.6: hold the picture to hear the original (gated on `enabled`, an undecided roll). HOLD, not touch-down:
/// `onBegan` fires only after the finger has been down `EuclideousRingPress.holdSeconds` (0.3 s), matching the
/// output rings / SOLO / lock-capture convention everywhere else on this page — the review 2026-10-24 brought
/// this into line (it used to switch from touch-down itself, a disclosed divergence from that convention). The
/// 0.3 s hold-task + drag-gesture shape is the SAME one `EuclideousSoloPressable` uses, minus the tap branch
/// (the picture has no tap action — only the hold).
private struct EuclideousRandomHoldModifier: ViewModifier {
    let enabled: Bool
    let onBegan: () -> Void
    let onEnded: () -> Void
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var began = false
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($touching) { _, t, _ in t = true }
                        .onChanged { _ in
                            guard holdTask == nil, !began else { return }
                            holdTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(EuclideousRingPress.holdSeconds * 1_000_000_000))
                                guard !Task.isCancelled else { return }
                                began = true
                                onBegan()
                            }
                        }
                        .onEnded { _ in finish() }
                )
                // A cancelled touch (scrolled off, interrupted) never fires `onEnded`; end it here so the hold
                // can't stick on. Deferred one turn so it can't race ahead of `onEnded`.
                .onChange(of: touching) { t in
                    guard !t else { return }
                    Task { @MainActor in if holdTask != nil || began { finish() } }
                }
                .onDisappear { finish() }
        } else {
            content
        }
    }

    private func finish() {
        holdTask?.cancel(); holdTask = nil
        if began { began = false; onEnded() }
    }
}

// MARK: - §4.1 RHYTHM picture

struct EuclideousRandomRhythmPicture: View {
    let line: EuclidLine
    let original: EuclidLine?
    let accent: Color
    let beat: Double
    /// 0…1 flash of this lane's latest rhythm (riff-layer) strike — the playhead ring flares on a hit.
    var strikeGlow: Double = 0

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
                // §4.1/§4.4: the live playhead ring — a FREE-pattern phase (`floor(beat / stepBeats) mod
                // steps`), the same base-case formula `euclideousLanePhase` reduces to with no restart
                // chain/grid active. This picture carries no chain state at all (THROW/TWEAK never touch
                // the chains), so a chained lane's picture shows this simplified phase, not its real one —
                // an accepted, documented simplification, not a second "real" derivation.
                // The playhead ring flares on a strike: a soft lane-colour halo behind it (fading with the
                // flash f) and a brighter, thicker ring — the header output rings' own `euclideousPulseRing
                // Stroke` curve (2.5 + 2.5·f), so the two read as the same "a hit sounded" language.
                let pt = point(currentStep(steps: steps), steps: steps, cx: cx, cy: cy, r: r)
                if strikeGlow > 0.01 {
                    Circle().fill(accent.opacity(0.5 * strikeGlow))
                        .frame(width: 22 + 26 * strikeGlow, height: 22 + 26 * strikeGlow)
                        .blur(radius: 4)
                        .position(pt)
                }
                Circle().strokeBorder(Color(hex: 0xF2F4F7), lineWidth: euclideousPulseRingStroke(f: strikeGlow))
                    .frame(width: 22, height: 22)
                    .position(pt)
                VStack(spacing: 3) {
                    Text("\(hits) / \(steps)").font(.system(size: 22, weight: .heavy)).foregroundColor(Color(hex: 0xF2F4F7))
                    Text(offset > 0 ? "OFFSET \(offset)" : "NO OFFSET").font(.system(size: 8.5, weight: .heavy)).tracking(1)
                        .foregroundColor(Color(hex: 0x8A909A))
                }
                .position(x: cx, y: cy)
            }
        }
    }

    private func currentStep(steps: Int) -> Int {
        let stepBeats = line.rate?.beats ?? 0.5
        guard stepBeats > 0, steps > 0 else { return 0 }
        let raw = Int((beat / stepBeats).rounded(.down))
        return ((raw % steps) + steps) % steps
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
    /// 0…1 flash of this lane's latest riff strike — the walk path brightens on a hit.
    var strikeGlow: Double = 0
    /// POLY RIFF (2026-10-29): the riff grid's width — 8 (MONO) or 16 (POLY); `riffRanks` then holds the top rank starting on each of the sixteen columns.
    var columns: Int = 8

    private func lenOf(_ l: EuclidLine) -> Int { columns == 8 ? l.riffLengthResolved : l.riffLengthResolved(columns: columns) }
    private func shiftOf(_ l: EuclidLine) -> Int { columns == 8 ? l.riffRotateResolved : l.riffRotateResolved(columns: columns) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let length = lenOf(line)
            let colW = w / CGFloat(columns)
            ZStack(alignment: .topLeading) {
                ForEach(0..<columns, id: \.self) { c in
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
                // The walk path brightens + thickens on a strike (flash f), fading back to its resting look —
                // same velocity-scaled cue as the rhythm ring, on the riff's own path.
                path(for: line, h: h, colW: colW).stroke(accent.opacity(0.55 + 0.45 * strikeGlow), lineWidth: 2.5 + 2 * strikeGlow)
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
        let length = lenOf(l)
        let seed = UInt64(bitPattern: Int64(l.riffDirSeedResolved))
        return (0..<12).map { ord in
            let col = euclideousRiffColumn(ordinal: Int64(ord), every: l.riffAdvanceEveryResolved, direction: l.euclideousRiffDirResolved,
                                            length: length, stride: l.riffStrideResolved, shift: shiftOf(l), seed: seed, columns: columns)
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
    let lane: Int
    /// 0…1 flash of this lane's latest notes-layer strike — the lit keys brighten on a hit.
    var strikeGlow: Double = 0

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
                    // A lit key brightens on a notes strike (flash f): its fill and border lift toward full
                    // accent and fade back — the notes layer's own "a note sounded" cue, scaled by velocity.
                    RoundedRectangle(cornerRadius: 6).fill(lit ? accent.opacity(0.25 + 0.4 * strikeGlow) : Color(hex: 0x22252C))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lit ? accent.opacity(0.7 + 0.3 * strikeGlow) : Color.clear, lineWidth: 1 + strikeGlow))
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

    /// §4.3: THREE dot states (not two) — sounds (14pt, full accent), CHANCE-dropped (14pt, 35% accent —
    /// PLAY AS would sound it but the fixed-seed roll dropped this hit), or never in the pattern (4pt,
    /// dim). And ROLL/RUN spread their sounding dots within the column (3pt/6pt per strike-order place,
    /// centred) instead of stacking them all at the column centre — the engine's own strike-order, via
    /// `euclideousNotesWayPick` directly rather than the membership-only `Set` wrapper, which loses it.
    private func playPattern(order: EuclideousLitOrder, width: CGFloat, height: CGFloat) -> some View {
        let n = order.count
        let rows = min(8, max(1, n))
        let rowH = min(30, height / CGFloat(rows))
        let colW = width / 8
        let way = line.notesPlayAsResolved
        let chance = line.notesChanceResolved
        var list = EuclideousNotesList()
        for i in 0..<order.count { list.append(pitch: i, position: order[i], rank: 0) }
        return ZStack {
            ForEach(0..<8, id: \.self) { hitCol in
                let pick = euclideousNotesWayPick(list: list, way: way, k: hitCol)
                let strikeIndex: [Int: Int] = {
                    var m: [Int: Int] = [:]
                    for j in 0..<pick.count { m[pick[j]] = j }
                    return m
                }()
                ForEach(0..<n, id: \.self) { row in
                    let j = strikeIndex[row]
                    let picked = j != nil
                    let allowed = picked && euclideousNotesChanceAllows(chance: chance, lane: lane, h: Int64(hitCol))
                    let dropped = picked && !allowed
                    let dx: CGFloat = {
                        guard let j else { return 0 }
                        switch way {
                        case .roll: return (CGFloat(j) - CGFloat(pick.count - 1) / 2) * 3
                        case .run: return (CGFloat(j) - CGFloat(pick.count - 1) / 2) * 6
                        default: return 0
                        }
                    }()
                    Circle().fill(allowed ? accent : (dropped ? accent.opacity(0.35) : Color(hex: 0x2A2D34)))
                        .frame(width: picked ? 14 : 4, height: picked ? 14 : 4)
                        .position(x: CGFloat(hitCol) * colW + colW / 2 + dx, y: CGFloat(row) * rowH + rowH / 2)
                }
            }
        }
        .frame(height: CGFloat(rows) * rowH)
    }
}

/// §5.7/§5.8 for VoiceOver: the hold as ONE named action ("Play the original" / "Play the new one") while the tab has an undecided roll. `accessibilityActions { }` (the builder form) is iOS 16;
/// `accessibilityAction(named: Text)` is iOS 13, so the app can deploy to iOS 15.
private struct EuclideousRandomHoldAction: ViewModifier {
    let undecided: Bool, holding: Bool
    let onBegan: () -> Void, onEnded: () -> Void
    func body(content: Content) -> some View {
        if undecided {
            content.accessibilityAction(named: Text(holding ? "Play the new one" : "Play the original")) { if holding { onEnded() } else { onBegan() } }
        } else {
            content
        }
    }
}
