//  MixPanelV2Views.swift — MIX v2 (2026-11-05): the views of the redesigned MIX panel. They only PAINT what `MixPanelV2.swift` computes (frames, looks, values, strings — one function for the draw code and the tests) and wire a finger to the
//  page's funnels. Cost: each lane band draws its strip, pool, fork, plates and stacks in ONE Canvas under ONE 60 fps TimelineView (paused while nothing runs); the controls (S, toggle, VEL, GATE, OCT, A–D) are plain SwiftUI views
//  OUTSIDE any TimelineView, so a frame never re-runs them. The panel sits in an `EuclideousStackBreak` at its call site (the extension's 1 MB main stack). The MIX rows build's views (`MixPanelViews.swift`) stay compiled, unmounted.

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }
private func now() -> Double { Date().timeIntervalSinceReferenceDate }

// MARK: - what the page hands the panel

struct EuclideousMixV2Input {
    var size: CGSize
    var lines: [EuclidLine]
    var accents: [Color]
    /// A lane that NEITHER of its parts may sound through (lane or part solo) — dims its band (§2.1).
    var laneSoloSilenced: [Bool]
    /// Eight: a part solo silences while its sister may still sound — dims that row's stack, VEL, GATE, OCT (§4.2).
    var partSoloSilenced: [Bool]
    /// The latched part-solo mask (bit 2n riff, 2n+1 notes of lane n).
    var partSoloLatched: UInt8
    var strips: [EuclideousMixStripFeed]
    var hitsText: [String]
    var stepsText: [String]
    var pools: [[Int]]
    var poolName: (Int, [Int]) -> String
    var riffGlyphs: [EuclideousRiffGlyph]
    var rolls: NoteRollLive
    var beatAt: (Date) -> Double
    var clock: EuclidLiveClock
    var live: Bool
    var stripMode: EuclideousMixStripMode
    var toggleMode: EuclideousMixToggleMode
    var hocketRules: [HocketRule]
    var hocketLive: HocketLiveModel
    /// EMITTER TOKEN ferry (2026-11-07): is output A–D muted (its MUTE-tab gate has any cell cleared, `hasMute`)? Drives the emitter's muted look (§3.4), the wires' dashed/clipped look (§4.2) and the routing circles' routed-muted look (§2.3).
    var outputMuted: [Bool] = [false, false, false, false]
}
struct EuclideousMixV2Callbacks {
    /// The card's own play tile at a frame (tile size, touch target).
    var play: (Int, CGSize, CGSize) -> AnyView
    var lockBadge: (Int) -> AnyView?
    /// The page's burst funnel: (lane, newStep, mutate).
    var editStep: (Int, Bool, @escaping (inout EuclidLine) -> Void) -> Void
    var toggleOn: (Int, EuclideousCardPart) -> Void
    var toggleOut: (Int, EuclideousCardPart, Int) -> Void
    /// Per-part solo, by part index 0…7 — the same touch machine as the lane SOLO button.
    var partSoloDown: (Int) -> Void
    var partSoloUp: (Int, Bool) -> Void
    /// EMITTER TOKEN §5.1: a MIX-emitter tap full-toggles output A–D's mute (one undo step, through the MUTE tab's funnel).
    var toggleOutputMute: (Int) -> Void
}

// MARK: - the panel

struct EuclideousMixV2Panel: View {
    let input: EuclideousMixV2Input
    let callbacks: EuclideousMixV2Callbacks
    /// EMITTER TOKEN §5.2: the set of outputs currently HELD (tracing). UI state only; the gesture layer fills it.
    @State private var heldOutputs: Set<Int> = []

    var body: some View {
        let L = euclideousMixV2Layout(size: input.size)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { lane in
                EuclideousMixV2BandView(lane: lane, layout: L, input: input, callbacks: callbacks, heldOutputs: heldOutputs)
                    .accessibilitySortPriority(Double(1000 - lane))
            }
            EuclideousMixV2LinesLayer(layout: L, input: input, heldOutputs: heldOutputs)
            EuclideousMixV2EmitterGestures(layout: L, callbacks: callbacks, heldOutputs: $heldOutputs)
            EuclideousMixV2EmitterAX(layout: L, input: input, callbacks: callbacks)
        }
        .frame(width: input.size.width, height: input.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousMixAX.panel)
    }
}

// MARK: - one lane band

struct EuclideousMixV2BandView: View {
    let lane: Int
    let layout: EuclideousMixV2Layout
    let input: EuclideousMixV2Input
    let callbacks: EuclideousMixV2Callbacks
    /// EMITTER TOKEN §5.2: outputs being held (traced). A part row whose mask does NOT hold a held output dims its plate's contents to 42 %. Empty until the hold gesture (slice 4) fills it.
    var heldOutputs: Set<Int> = []

    private var band: EuclideousMixV2BandFrames { layout.bands[lane] }
    private var line: EuclidLine { lane < input.lines.count ? input.lines[lane] : EuclidLine(noteSel: .all) }
    private var accent: Color { input.accents[lane % input.accents.count] }
    private var soloDim: Bool { lane < input.laneSoloSilenced.count && input.laneSoloSilenced[lane] }
    /// §2.1: everything below the strip frame dims ONCE to 42 % — solo-silenced (neither part audible), no hits, or muted (PLAY off); it stays live.
    private var laneDim: Bool { euclideousMixLaneDimmed(soloSilenced: soloDim, noHits: euclideousMixLaneHasNoHits(legs: input.strips[lane].legs), muted: !input.strips[lane].lanePlaying) }
    private var locked: AnyView? { callbacks.lockBadge(lane) }
    private func partSoloDim(_ notes: Bool) -> Bool { let i = 2 * lane + (notes ? 1 : 0); return i < input.partSoloSilenced.count && input.partSoloSilenced[i] }

    var body: some View {
        let hasLock = locked != nil
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: EuclideousMixV2StripMetrics.bandRadius).fill(Color(hex: EuclideousMixV2StripMetrics.bandFillHex))
            RoundedRectangle(cornerRadius: EuclideousMixV2StripMetrics.bandRadius).strokeBorder(Color(hex: EuclideousMixV2StripMetrics.bandBorderHex), lineWidth: 1)
            ZStack(alignment: .topLeading) {
                EuclideousMixV2BandCanvas(lane: lane, band: band, layout: layout, input: input, hasLock: hasLock, laneDim: laneDim, partDim: [partSoloDim(false), partSoloDim(true)])
                    .allowsHitTesting(false)
                // the top line: the card's own play tile over the pool's column
                callbacks.play(lane, band.play.size, EuclideousMixV2Metrics.playTarget)
                    .frame(width: EuclideousMixV2Metrics.playTarget.width, height: EuclideousMixV2Metrics.playTarget.height, alignment: .top)
                    .offset(x: band.play.minX, y: band.play.minY)
                    .accessibilitySortPriority(100)
                Color.clear.frame(width: band.stripFrame.width, height: band.stripFrame.height).offset(x: band.stripFrame.minX, y: band.stripFrame.minY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EuclideousMixStripSpokenView.label(for: input.strips[lane]))
                    .accessibilitySortPriority(99)
                if let badge = locked {
                    badge.frame(width: EuclideousLockBadge.size, height: EuclideousLockBadge.size).scaleEffect(EuclideousMixV2Metrics.badge / EuclideousLockBadge.size)
                        .frame(width: EuclideousMixV2Metrics.badge, height: EuclideousMixV2Metrics.badge)
                        .offset(x: band.badge.minX, y: band.badge.minY)
                        .accessibilitySortPriority(98.5)
                }
                EuclideousMixV2PoolAX(area: band.pool, pool: lane < input.pools.count ? input.pools[lane] : [], poolName: input.poolName).accessibilitySortPriority(97)
                // the part rows: below the strip frame, so a dimmed lane dims them as one group (§2.1: one 42 %, never stacked)
                Group {
                    partRow(notes: false, f: band.riff, base: 96)
                    partRow(notes: true, f: band.notes, base: 86)
                }
                .opacity(laneDim ? EuclideousLaneDimStyle.opacity : 1)
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: laneDim)
            }
            .frame(width: band.inner.width, height: band.inner.height, alignment: .topLeading)
            .offset(x: band.inner.minX - band.frame.minX, y: band.inner.minY - band.frame.minY)
        }
        .frame(width: band.frame.width, height: band.frame.height, alignment: .topLeading)
        .offset(x: band.frame.minX, y: band.frame.minY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousMixAX.lane(lane))
    }

    private func partRow(notes: Bool, f: EuclideousMixV2RowFrames, base: Double) -> some View {
        let part = notes ? EuclideousCardPart.notes : EuclideousCardPart.riff
        let partIndex = 2 * lane + (notes ? 1 : 0)
        let on = !euclideousMixLayerIsOff(line, notes: notes)
        let partDim = !on || partSoloDim(notes)
        let mask = notes ? line.notesOutMaskResolved(lane: lane) : line.riffOutMaskResolved(lane: lane)
        let laneDim = self.laneDim
        // §5.2: while an emitter is held, a part row whose mask holds NONE of the held outputs dims its whole plate (S, toggle and A–D included) to 42 %; the union of several holds counts.
        let holdDim = !heldOutputs.isEmpty && !heldOutputs.contains { o in mask & (UInt8(1) << UInt8(o)) != 0 }
        func own(_ e: EuclideousMixV2Element) -> Double { euclideousMixV2OwnOpacity(laneDimmed: laneDim, partDimmed: partDim, element: e) }
        return ZStack(alignment: .topLeading) {
            // S — never dims
            EuclideousMixV2SoloButton(lane: lane, part: partIndex, notes: notes, latched: (input.partSoloLatched >> UInt8(partIndex)) & 1 != 0, frames: f,
                                      onDown: { callbacks.partSoloDown(partIndex) }, onUp: { callbacks.partSoloUp(partIndex, $0) })
                .offset(x: f.soloTarget.minX, y: f.soloTarget.minY)
                .accessibilitySortPriority(base)
            EuclideousMixV2Toggle(lane: lane, part: part, on: on, accent: accent, size: f.toggle.size, mode: input.toggleMode,
                                  glyph: lane < input.riffGlyphs.count ? input.riffGlyphs[lane] : nil, litMask: line.litNotesResolved, rules: input.hocketRules, live: input.hocketLive) { callbacks.toggleOn(lane, part) }
                .offset(x: f.toggle.minX, y: f.toggle.minY)
                .accessibilitySortPriority(base - 1)
            EuclideousMixV2StackAX(lane: lane, notes: notes, area: f.stack, input: input).accessibilitySortPriority(base - 2)
            EuclideousMixV2FieldTile(kind: .velocity, notes: notes, value: euclideousMixSliderValue(of: line, kind: .velocity, notes: notes), accent: accent, size: f.vel.size, dimmed: own(.vel) < 1,
                                     onEditStep: { newStep, mutate in callbacks.editStep(lane, newStep, mutate) })
                .offset(x: f.vel.minX, y: f.vel.minY).accessibilitySortPriority(base - 3)
            EuclideousMixV2FieldTile(kind: .gate, notes: notes, value: euclideousMixSliderValue(of: line, kind: .gate, notes: notes), accent: accent, size: f.gate.size, dimmed: own(.gate) < 1,
                                     onEditStep: { newStep, mutate in callbacks.editStep(lane, newStep, mutate) })
                .offset(x: f.gate.minX, y: f.gate.minY).accessibilitySortPriority(base - 4)
            octave(notes: notes, f: f, dimmed: own(.oct) < 1).accessibilitySortPriority(base - 5)
            ForEach(0..<4, id: \.self) { o in
                EuclideousMixV2OutButton(output: o, on: euclideousJackIsPlugged(mask: mask, output: o), notes: notes, accent: accent, target: f.outTargets[o].size, circle: f.outCircles[o].size,
                                         outputMuted: o < input.outputMuted.count && input.outputMuted[o]) { callbacks.toggleOut(lane, part, o) }
                    .offset(x: f.outTargets[o].minX, y: f.outTargets[o].minY)
                    .accessibilitySortPriority(base - 6 - Double(o) * 0.1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: notes ? 0x131418 : 0x1E2025)).frame(width: f.plate.width, height: f.plate.height)
                .offset(x: f.plate.minX, y: f.plate.minY), alignment: .topLeading)
        .opacity(holdDim ? EuclideousLaneDimStyle.opacity : 1)   // §5.2 the hold trace dims rows that don't reach the held output; restored at once on release
    }

    /// OCT (§4.8): "OCT" centred in the top 9, then the five boxes in the remaining height less 2; the touch frame is each box's width by the row.
    private func octave(notes: Bool, f: EuclideousMixV2RowFrames, dimmed: Bool) -> some View {
        let value = euclideousMixSliderValue(of: line, kind: .octave, notes: notes)
        let boxes = f.octBoxes.first ?? .zero
        let lane = self.lane
        return ZStack(alignment: .topLeading) {
            Text("OCT").font(heavyMono(6)).tracking(0.2 * 6).foregroundColor(Color(hex: 0xAAB0BA))
                .frame(width: f.octLabel.width, height: f.octLabel.height, alignment: .center)
                .offset(x: f.octLabel.minX, y: f.octLabel.minY)
                .accessibilityHidden(true)
            EuclideousOctaveBoxes(value: value, size: CGSize(width: f.oct.width, height: boxes.height), targetHeight: f.octTargets.first?.height ?? boxes.height, visualTop: boxes.minY - (f.octTargets.first?.minY ?? boxes.minY),
                                  label: EuclideousMixV2AX.octave(notes: notes, value: value),
                                  onSelect: { v, newStep in callbacks.editStep(lane, newStep) { l in euclideousMixSliderWrite(&l, kind: .octave, notes: notes, value: v) } })
                .offset(x: f.oct.minX, y: (f.octTargets.first?.minY ?? boxes.minY))
        }
        .opacity(dimmed ? EuclideousLaneDimStyle.opacity : 1)
    }
}

// MARK: - the band's live canvas: strip frame, pool, fork, plates' stacks (one TimelineView, one Canvas)

struct EuclideousMixV2BandCanvas: View {
    let lane: Int
    let band: EuclideousMixV2BandFrames
    let layout: EuclideousMixV2Layout
    let input: EuclideousMixV2Input
    let hasLock: Bool
    let laneDim: Bool
    /// riff, notes: a solo-silenced part (dims its stack with the off-part dim)
    let partDim: [Bool]

    var body: some View {
        typealias S = EuclideousMixV2StripMetrics
        let feed = input.strips[lane]
        let line = lane < input.lines.count ? input.lines[lane] : EuclidLine(noteSel: .all)
        let pool = lane < input.pools.count ? input.pools[lane] : []
        let partOn = [!euclideousMixLayerIsOff(line, notes: false), !euclideousMixLayerIsOff(line, notes: true)]
        let model = input.rolls
        let clock = input.clock, beatAt = input.beatAt, mode = input.stripMode
        let accent = input.accents[lane % input.accents.count], dim = laneDim, partDim = self.partDim
        let stepsFrame = hasLock ? band.stripStepsWithBadge : band.stripSteps
        let cells = euclideousMixStripCells(strip: stepsFrame, steps: feed.n, mode: mode)
        let poolName = input.poolName
        let hits = lane < input.hitsText.count ? input.hitsText[lane] : "0", steps = lane < input.stepsText.count ? input.stepsText[lane] : "0"
        let band = self.band, lane = self.lane
        let forkRiff = euclideousMixV2ForkCurve(from: band.forkStart, to: band.forkRiffEnd)
        let forkNotes = euclideousMixV2ForkCurve(from: band.forkStart, to: band.forkNotesEnd)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !input.live)) { tl in
            Canvas { ctx, size in
                let nowBeat = beatAt(tl.date)
                // ── the top line: never dimmed
                let frame = Path(roundedRect: band.stripFrame, cornerRadius: S.frameRadius)
                ctx.fill(frame, with: .color(Color(hex: S.frameFillHex)))
                ctx.stroke(Path(roundedRect: band.stripFrame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: S.frameRadius - 0.5), with: .color(accent.opacity(S.frameBorderAlpha)), lineWidth: 1)
                let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
                let running = clock.playing && feed.lanePlaying && !(feed.mutedAt?(liveBeat) ?? false)
                let raw = feed.chains.map { euclideousLaneCometChainRaw(beat: liveBeat, n: feed.n, dir: feed.dir, sub: feed.sub, chains: $0, legacySpanBeats: 0) }
                    ?? euclidCometRaw(mTickBeat: liveBeat, sub: feed.sub, spanBeats: 0, n: feed.n, dir: feed.dir)
                let legIdx = min(max(0, feed.legs.count - 1), euclideousStripLegIndex(raw: running ? raw : 0, n: feed.n, legCount: feed.legs.count))
                let stepList = feed.legs.isEmpty ? [] : euclideousMixStripSteps(hits: feed.legs[legIdx].hits)
                let current = euclideousMixStripCurrent(raw: raw, steps: feed.n, dir: feed.dir, running: running)
                for (i, cell) in cells.enumerated() where i < stepList.count {
                    let look = euclideousMixV2CellLook(isHit: stepList[i].isHit, isCurrent: current == i)
                    let shape = Path(roundedRect: cell, cornerRadius: S.radius)
                    switch look.fill {
                    case .solid(let hex): ctx.fill(shape, with: .color(Color(hex: hex)))
                    case .lane(let a): ctx.fill(shape, with: .color(accent.opacity(a)))
                    }
                    if look.glow {
                        var g = ctx
                        g.addFilter(.shadow(color: accent, radius: S.glow, x: 0, y: 0))
                        g.fill(shape, with: .color(accent))
                    }
                    if look.bottomLine {
                        var c = ctx; c.clip(to: shape)
                        c.fill(Path(CGRect(x: cell.minX, y: cell.maxY - S.bottomLine, width: cell.width, height: S.bottomLine)), with: .color(accent))
                    }
                }
                // HITS and STEPS: two boxes over the A–D column, no touches
                for (box, number, label) in [(band.hitsBox, hits, euclideousMixV2HitsLabel), (band.stepsBox, steps, euclideousMixV2StepsLabel)] {
                    ctx.fill(Path(roundedRect: box, cornerRadius: S.boxRadius), with: .color(Color(hex: S.boxFillHex)))
                    let n = ctx.resolve(Text(number).font(heavyMono(S.numberSize)).foregroundColor(Color(hex: 0xF2F4F7)))
                    let l = ctx.resolve(Text(label).font(heavyMono(S.labelSize)).tracking(0.15 * S.labelSize).foregroundColor(Color(hex: 0x8A909A)))
                    let ns = n.measure(in: CGSize(width: 200, height: 200)), ls = l.measure(in: CGSize(width: 200, height: 200))
                    let total = ns.height + S.numberGap + ls.height, top = box.midY - total / 2
                    ctx.draw(n, at: CGPoint(x: box.midX, y: top), anchor: .top)
                    ctx.draw(l, at: CGPoint(x: box.midX, y: top + ns.height + S.numberGap), anchor: .top)
                }
                // ── below the strip frame: ONE dim to 42 %
                var below = ctx
                if dim { below.opacity = EuclideousLaneDimStyle.opacity }
                // the pool: eight chips, rank 8 on top — never lit
                let chips = euclideousMixV2PoolChips(sortedPool: pool, name: { poolName($0, pool) })
                for (i, chip) in chips.enumerated() where i < band.chips.count {
                    let f = band.chips[i]
                    var c = below
                    if chip.faded { c.opacity = below.opacity * EuclideousMixPoolMetrics.fadedAlpha }
                    c.fill(Path(roundedRect: f, cornerRadius: 4), with: .color(Color(hex: EuclideousMixPoolMetrics.idleHex)))
                    euclideousMixDrawChipText(&c, chip: chip, frame: f, ink: Color(hex: 0x8A909A), radius: 4)
                }
                // the fork: two curves from the pool's mid-height to the rows' centres
                for (curve, on) in [(forkRiff, partOn[0]), (forkNotes, partOn[1])] {
                    var p = Path(); p.move(to: curve.start); p.addCurve(to: curve.end, control1: curve.c1, control2: curve.c2)
                    below.stroke(p, with: .color(accent.opacity(euclideousMixV2ForkAlpha(partOn: on))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                // the plates' stacks
                for k in 0..<2 {
                    let row = k == 0 ? band.riff : band.notes
                    let notes = model.model.parts[2 * lane + k]
                    let cellsNow = euclideousMixV2StackCells(notes: notes, nowBeat: nowBeat)
                    let frames = euclideousMixV2StackFrames(tile: row.stack)
                    var c = below
                    c.opacity = below.opacity * euclideousMixV2OwnOpacity(laneDimmed: dim, partDimmed: !partOn[k] || partDim[k], element: .stack)
                    typealias K = EuclideousMixV2StackMetrics
                    for (i, f) in frames.enumerated() {
                        let shape = Path(roundedRect: f, cornerRadius: K.radius)
                        switch cellsNow[i] {
                        case .unlit: c.fill(shape, with: .color(Color(hex: partOn[k] ? K.unlitOnHex : K.unlitOffHex)))
                        case .silent:
                            c.fill(shape, with: .color(Color(hex: partOn[k] ? K.unlitOnHex : K.unlitOffHex)))
                            c.stroke(Path(roundedRect: f.insetBy(dx: K.silentLine / 2, dy: K.silentLine / 2), cornerRadius: max(0, K.radius - 0.5)), with: .color(accent), lineWidth: K.silentLine)
                        case .lit:
                            var g = c
                            g.addFilter(.shadow(color: accent, radius: K.glow, x: 0, y: 0))
                            g.fill(shape, with: .color(accent))
                        }
                    }
                }
            }
            .frame(width: band.inner.width, height: band.inner.height)
        }
        .frame(width: band.inner.width, height: band.inner.height)
    }
}

// MARK: - VoiceOver leaves

struct EuclideousMixV2PoolAX: View {
    let area: CGRect
    let pool: [Int]
    let poolName: (Int, [Int]) -> String
    var body: some View {
        let sorted = pool.sorted()
        let label = EuclideousMixV2AX.pool(lowest: sorted.first.map { poolName($0, sorted) }, highest: sorted.last.map { poolName($0, sorted) })
        return Color.clear.frame(width: area.width, height: area.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .offset(x: area.minX, y: area.minY)
    }
}
struct EuclideousMixV2StackAX: View {
    let lane: Int
    let notes: Bool
    let area: CGRect
    let input: EuclideousMixV2Input
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.25)) { tl in
            let ranks = euclideousMixV2PlayingRanks(notes: input.rolls.model.parts[2 * lane + (notes ? 1 : 0)], nowBeat: input.beatAt(tl.date))
            Color.clear.frame(width: area.width, height: area.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousMixV2AX.stack(notes: notes, ranks: ranks))
        }
        .frame(width: area.width, height: area.height)
        .offset(x: area.minX, y: area.minY)
    }
}

// MARK: - S: the part's solo

struct EuclideousMixV2SoloButton: View {
    let lane: Int
    let part: Int
    let notes: Bool
    let latched: Bool
    let frames: EuclideousMixV2RowFrames
    let onDown: () -> Void
    let onUp: (Bool) -> Void

    var body: some View {
        let target = frames.soloTarget.size, tileH = frames.tileH
        return EuclideousSoloPressable(lane: lane, accent: .clear, latched: latched, tile: target, target: target,
                                       look: { latched, held in
                                           let look = euclideousMixV2SoloLook(latched: latched, heldLook: held)
                                           typealias S = EuclideousMixV2SoloMetrics
                                           return AnyView(
                                               ZStack(alignment: .topLeading) {
                                                   ZStack {
                                                       RoundedRectangle(cornerRadius: S.radius).fill(Color(hex: look.fillHex ?? S.offFillHex))
                                                       if look.border { RoundedRectangle(cornerRadius: S.radius).inset(by: S.border / 2).stroke(Color(hex: S.borderHex), lineWidth: S.border) }
                                                       Text("S").font(heavyMono(S.size)).foregroundColor(Color(hex: look.inkHex))
                                                   }
                                                   .frame(width: EuclideousMixV2Metrics.soloW, height: tileH)
                                                   .offset(x: EuclideousMixV2Metrics.plateInset, y: EuclideousMixV2Metrics.plateInset)
                                               }
                                               .frame(width: target.width, height: target.height, alignment: .topLeading)
                                               .transaction { $0.animation = nil })
                                       },
                                       axLabel: EuclideousMixV2AX.solo(notes: notes, lane: lane), onDown: onDown, onUp: onUp)
    }
}

// MARK: - the part toggle

struct EuclideousMixV2Toggle: View {
    let lane: Int
    let part: EuclideousCardPart
    let on: Bool
    let accent: Color
    let size: CGSize
    let mode: EuclideousMixToggleMode
    let glyph: EuclideousRiffGlyph?
    let litMask: UInt8
    let rules: [HocketRule]
    @ObservedObject var live: HocketLiveModel
    let onTap: () -> Void

    var body: some View {
        let look = euclideousMixV2ToggleLook(on: on, mode: mode)
        let notes = part == .notes
        let hocketLit = rules.contains(where: { $0.isLit })
        let shape: EuclideousGlyphShape = notes ? .bar : .square
        let ground = look.fillIsLane ? accent : Color(hex: look.fillHex ?? 0x1F2127)
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, sz in
                let plate = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 8)
                if look.fillIsLane { ctx.fill(plate, with: .color(accent)) } else if let hex = look.fillHex { ctx.fill(plate, with: .color(Color(hex: hex))) }
                if look.borderWidth > 0 {
                    ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: sz).insetBy(dx: look.borderWidth / 2, dy: look.borderWidth / 2), cornerRadius: 8 - look.borderWidth / 2),
                               with: .color((look.borderIsLane ? accent : Color(hex: look.borderHex)).opacity(look.borderAlpha)), lineWidth: look.borderWidth)
                }
                let g = euclideousMixV2ToggleGlyphFrame(tile: sz)
                let lit = look.glyphIsLane ? accent : Color(hex: look.glyphHex)
                let back = Color(hex: look.backdropHex).opacity(look.backdropAlpha)
                if notes {
                    for (i, f) in euclideousMixV2NotesBarFrames(glyph: g).enumerated() {
                        let isLit = (litMask & (1 << UInt8(7 - i))) != 0
                        ctx.fill(Path(roundedRect: f, cornerRadius: min(1, f.height / 2)), with: .color(lit.opacity(isLit ? 1 : 0.25)))
                    }
                } else if let glyph {
                    let frames = euclideousMixV2RiffCellFrames(glyph: g, columns: glyph.columns)
                    let r = min(glyph.columns > 8 ? 0.75 : 1.5, (frames.first?.first?.width ?? 1) / 3)
                    for col in 0..<glyph.columns {
                        for row in 0..<8 {
                            let rank = 8 - row
                            let hit = glyph.isHit(col: col, rank: rank)
                            let isCur = col == glyph.current
                            let colour: Color = hit ? (isCur ? Color(hex: on ? 0xF2F4F7 : 0xAAB0BA) : lit) : back
                            ctx.fill(Path(roundedRect: frames[col][row], cornerRadius: r), with: .color(colour.opacity(glyph.opacity(col: col))))
                        }
                    }
                }
            }
            if hocketLit {
                HocketPartGlyph(shape: shape, on: on, fill: accent, lane: lane, rules: rules, live: live, ground: ground)
                    .offset(x: size.width - EuclideousTabGlyphView.size(shape).width - 4, y: 4)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .hocketPartAX(base: EuclideousMixAX.toggle(notes: notes, on: on), lane: lane, notes: notes, partOff: !on, rules: rules, live: live)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - VEL / GATE: the OFFSET tile's looks at the part row's frame

struct EuclideousMixV2FieldTile: View {
    let kind: EuclideousMixSliderKind     // .velocity or .gate
    let notes: Bool
    let value: Int
    let accent: Color
    let size: CGSize
    let dimmed: Bool
    let onEditStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void

    private enum Axis { case horizontal, vertical }
    @State private var burst = EuclideousPadUndoBurst()
    @State private var axis: Axis? = nil
    @State private var startValue = 0
    @State private var lastWritten: Int? = nil
    @GestureState private var gestureLive = false

    var body: some View {
        typealias F = EuclideousMixV2FieldLook
        let text = euclideousMixSliderText(kind: kind, value: value)
        let sizes = euclideousMixV2FieldTextSizes(tileWidth: size.width, labelChars: kind.label.count, valueChars: text.count)
        let frac = Double(euclideousMixSliderFraction(kind: kind, value: value))
        let g = euclideousMixV2FieldGeometry(size: size, frac: frac)
        let accent = self.accent
        return ZStack {
            Canvas { ctx, sz in
                let shape = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: F.radius)
                ctx.fill(shape, with: .color(Color(hex: F.groundHex)))
                var c = ctx; c.clip(to: shape)
                c.fill(Path(g.fill), with: .color(Color(hex: F.fillHex).opacity(F.fillAlpha)))
                for tf in euclideousMixV2FieldTickFracs {
                    let x = F.inset + CGFloat(tf) * g.travel
                    c.fill(Path(CGRect(x: x - F.tickW / 2, y: sz.height - F.tickH, width: F.tickW, height: F.tickH)), with: .color(Color(hex: F.tickHex)))
                }
                c.fill(Path(g.edge), with: .color(accent))
            }
            HStack(spacing: 4) {
                Text(kind.label).font(.system(size: sizes.label, weight: .semibold, design: .monospaced)).tracking(sizes.label >= 10 ? 0.8 : 1.4)
                    .foregroundColor(Color(hex: F.labelHex)).lineLimit(1)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: F.groundHex).opacity(sizes.label >= 10 ? 1 : 0.72)))
                Spacer(minLength: 0)
                Text(text).font(.system(size: sizes.value, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: F.valueHex)).lineLimit(1)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: F.valueBackingRadius).fill(Color(hex: F.valueBackingHex).opacity(F.valueBackingAlpha)))
            }
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .opacity(dimmed ? EuclideousLaneDimStyle.opacity : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .updating($gestureLive) { _, live, _ in live = true }
            .onChanged { d in
                if axis == nil {
                    axis = abs(d.translation.width) >= abs(d.translation.height) ? .horizontal : .vertical
                    if axis == .horizontal { startValue = value; lastWritten = nil; burst.touchDown(at: now()) }
                }
                guard axis == .horizontal else { return }   // a vertical drag that starts on a tile never moves the value
                let v = euclideousMixSliderDrag(kind: kind, startValue: startValue, translation: d.translation.width, trackWidth: g.travel)
                if v == lastWritten { return }
                lastWritten = v
                write(v, newStepAlways: false)
            }
            .onEnded { _ in finish() })
        .onChange(of: gestureLive) { live in if !live { finish() } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousMixAX.slider(kind: kind, notes: notes, value: value))
        .accessibilityAdjustableAction { direction in write(euclideousMixSliderStep(kind: kind, value: value, up: direction == .increment), newStepAlways: true) }
        .accessibilityAction(named: EuclideousMixAX.reset) { reset() }
    }
    private func finish() {
        if axis == .horizontal { burst.touchEnd(at: now()) }
        axis = nil; lastWritten = nil
    }
    private func write(_ v: Int, newStepAlways: Bool) {
        let newStep = newStepAlways ? true : burst.nextWriteNeedsNewStep()
        let n = notes, k = kind
        onEditStep(newStep) { l in euclideousMixSliderWrite(&l, kind: k, notes: n, value: v) }   // live while the part is off: it never turns the layer on
    }
    private func reset() {
        let n = notes, k = kind
        onEditStep(true) { l in euclideousMixSliderReset(&l, kind: k, notes: n) }
    }
}

// MARK: - OCT: five linked boxes (one view for every surface)

struct EuclideousOctaveBoxes: View {
    let value: Int
    /// The boxes' own frame (the container).
    let size: CGSize
    /// The touch frame's height (each box's width by this, never less than 44 — the caller passes the surface's row height) and where the boxes sit in it (from its top).
    let targetHeight: CGFloat
    let visualTop: CGFloat
    let label: String
    /// (value, startsNewUndoStep)
    let onSelect: (Int, Bool) -> Void

    @State private var touch = EuclideousOctaveTouch()
    @GestureState private var gestureLive = false

    var body: some View {
        let selected = euclideousOctSelectedIndex(value: value)
        let boxW = size.width / 5
        let fontSize = euclideousOctLabelSize(boxHeight: size.height)
        let target = max(44, targetHeight)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    Text(euclideousOctLabels[i]).font(heavyMono(fontSize)).foregroundColor(Color(hex: i == selected ? 0x0D0F14 : 0xAAB0BA)).lineLimit(1)
                        .frame(width: boxW, height: size.height)
                        .background(i == selected ? Color(hex: 0xDFE3EA) : Color.clear)
                        .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Color(hex: 0x30333A)).frame(width: 1) } }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x30333A), lineWidth: 1))
            .offset(y: visualTop)
        }
        .frame(width: size.width, height: target, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($gestureLive) { _, live, _ in live = true }
            .onChanged { d in
                let i = euclideousOctIndex(x: d.location.x, width: size.width)
                if let w = touch.move(to: i, current: value) { onSelect(w.value, w.newStep) }
            }
            .onEnded { _ in touch.end() })
        .onChange(of: gestureLive) { live in if !live { touch.end() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAdjustableAction { direction in
            let n = euclideousOctStep(euclideousOctSelectedValue(value), up: direction == .increment)
            if n != euclideousOctSelectedValue(value) { onSelect(n, true) }
        }
    }
}

// MARK: - A–D

/// EMITTER TOKEN ferry (2026-11-07) §2.3 / §6.2–6.3: the MIX A–D (22) and RIFF / NOTES OUT (28) routing circle IS the token — a part's choice of output keeps its lane colour (routed = lane ring + lane@20 % disc; not routed = #3A3E47 ring;
/// routed to a MUTED output = lane ring @ 45 % dashed). `outputMuted` is that output's MUTE-tab state; it only shows while the circle is routed (§2.3). The old by-hand drawing is replaced by the shared token.
struct EuclideousPartOutDiscArt: View {
    let letter: String
    let on: Bool
    let accent: Color
    var diameter: CGFloat = 28
    var outputMuted: Bool = false
    var body: some View {
        EuclideousEmitterTokenView(size: diameter <= 24 ? .d22 : .d28, letter: letter,
                                   state: euclideousEmitterTokenRoutingState(routed: on, outputMuted: outputMuted), lane: accent)
    }
}
struct EuclideousMixV2OutButton: View {
    let output: Int
    let on: Bool
    let notes: Bool
    let accent: Color
    let target: CGSize
    let circle: CGSize
    var outputMuted: Bool = false
    let onTap: () -> Void
    var body: some View {
        EuclideousPartOutDiscArt(letter: euclideousJackLetters[max(0, min(3, output))], on: on, accent: accent, diameter: circle.width, outputMuted: outputMuted)
            .frame(width: target.width, height: target.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EuclideousMixAX.out(notes: notes, output: output, on: on))
            .accessibilityValue(on && outputMuted ? "output muted" : "")   // §8.2: routed to a muted output
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - the lines, the origin dots and the four emitters (one layer, no touches)

struct EuclideousMixV2LinesLayer: View {
    let layout: EuclideousMixV2Layout
    let input: EuclideousMixV2Input
    /// EMITTER TOKEN §4.4 / §5.2: outputs being held. A line not ending at a held output draws at 15 %; the non-held emitters' contents (token + inlet) draw at 42 %.
    var heldOutputs: Set<Int> = []

    var body: some View {
        let masks: [UInt8] = (0..<8).map { p in
            let l = p / 2 < input.lines.count ? input.lines[p / 2] : EuclidLine(noteSel: .all)
            return p % 2 == 1 ? l.notesOutMaskResolved(lane: p / 2) : l.riffOutMaskResolved(lane: p / 2)
        }
        let on: [Bool] = (0..<8).map { p in
            let l = p / 2 < input.lines.count ? input.lines[p / 2] : EuclidLine(noteSel: .all)
            return !euclideousMixLayerIsOff(l, notes: p % 2 == 1)
        }
        let lines = euclideousMixV2Lines(layout: layout, masks: masks, partOn: on)
        let dots = euclideousMixOriginDots(lines: lines)
        let accents = input.accents, beatAt = input.beatAt, model = input.rolls, tempo = input.clock.tempo, L = layout
        let noHits: [Bool] = (0..<4).map { $0 < input.strips.count ? euclideousMixLaneHasNoHits(legs: input.strips[$0].legs) : false }
        let muted: [Bool] = (0..<4).map { $0 < input.outputMuted.count ? input.outputMuted[$0] : false }
        let anyRouted: [Bool] = (0..<4).map { o in (0..<8).contains { p in on[p] && masks[p] & (UInt8(1) << UInt8(o)) != 0 } }
        let held = heldOutputs, anyHeld = !heldOutputs.isEmpty
        let left = layout.bandW - 8
        let canvasW = layout.size.width - left
        let clipLocalMaxX = (layout.bandW + 32) - left   // §4.2: a muted line stops 8 pt short of the inlet at bandW + 40
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !input.live)) { tl in
            Canvas { ctx, size in
                ctx.translateBy(x: -left, y: 0)
                typealias M = EuclideousMixLineMetrics
                typealias V = EuclideousMixV2Metrics
                let now = beatAt(tl.date)
                let parts = model.model.parts
                // §3.2 the cards (behind the wires; §3.6 they never dim or change colour)
                for o in 0..<4 {
                    let card = L.emitterCards[o]
                    ctx.fill(Path(roundedRect: card, cornerRadius: V.emitterCardRadius), with: .color(Color(hex: V.emitterCardFillHex)))
                    ctx.stroke(Path(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), cornerRadius: V.emitterCardRadius - 0.5), with: .color(Color(hex: V.emitterCardBorderHex)), lineWidth: 1)
                }
                // the wires: §4.2 muted lines (dashed, clipped short) under the live ones; §4.4 a non-held line at 15 %
                let acts = lines.map { euclideousMixLineActivity(notes: parts[$0.part], output: $0.output, nowBeat: now, tempo: tempo) }
                func strokeLine(_ i: Int) {
                    let l = lines[i]
                    let ap = euclideousMixV2LineAppearance(activity: acts[i], laneNoHits: noHits[l.lane], outputMuted: muted[l.output], holdDim: anyHeld && !held.contains(l.output))
                    var p = Path(); p.move(to: l.from); p.addCurve(to: l.to, control1: l.c1, control2: l.c2)
                    let style = StrokeStyle(lineWidth: ap.width, lineCap: ap.dashed ? .butt : .round, dash: ap.dashed ? [3, 3] : [])
                    let colour = accents[l.lane % accents.count].opacity(ap.alpha)
                    if muted[l.output] {
                        ctx.drawLayer { layer in layer.clip(to: Path(CGRect(x: 0, y: 0, width: clipLocalMaxX, height: size.height))); layer.stroke(p, with: .color(colour), style: style) }
                    } else {
                        ctx.stroke(p, with: .color(colour), style: style)
                    }
                }
                for i in lines.indices where muted[lines[i].output] { strokeLine(i) }
                for i in euclideousMixLineDrawOrder(activities: acts) where !muted[lines[i].output] { strokeLine(i) }
                // the origin dots
                for d in dots {
                    ctx.fill(Path(ellipseIn: CGRect(x: d.at.x - M.originDot / 2, y: d.at.y - M.originDot / 2, width: M.originDot, height: M.originDot)), with: .color(accents[d.lane % accents.count].opacity(euclideousMixOriginDotAlpha(laneNoHits: noHits[d.lane]))))
                }
                // §3.3–3.5 the four emitter tokens (36) in their cards, each with its inlet — neutral, a lane-coloured flare while a lane plays through
                for o in 0..<4 {
                    let flare = euclideousMixEmitterFlare(parts: parts, output: o, nowBeat: now, tempo: tempo)
                    let laneColor = flare.lane >= 0 && flare.lane < accents.count ? accents[flare.lane] : Color.clear
                    let state = euclideousEmitterTokenEmitterState(muted: muted[o], activity: flare.activity, anyRouted: anyRouted[o])
                    let dim = anyHeld && !held.contains(o) ? EuclideousLaneDimStyle.opacity : 1   // §5.2 the other cards' contents at 42 %
                    ctx.drawLayer { layer in
                        layer.opacity = dim
                        drawEuclideousEmitterToken(layer, rect: L.emitters[o], size: .d36, letter: euclideousJackLetters[o],
                                                   paint: euclideousEmitterTokenPaint(state, size: .d36), lane: laneColor, held: held.contains(o))
                        drawEuclideousMixInlet(layer, at: L.inlets[o], state: state, lane: laneColor)
                    }
                }
            }
            .frame(width: canvasW, height: layout.size.height)
        }
        .frame(width: canvasW, height: layout.size.height)
        .offset(x: left, y: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// §3.5 the inlet dot on a card's left edge, its look following the emitter's state: live #4A4E57, playing the lane (fading with the token), unused #2A2D34, muted a 1.5 pt #5C626C ring with no fill.
func drawEuclideousMixInlet(_ ctx: GraphicsContext, at: CGPoint, state: EuclideousEmitterTokenState, lane: Color) {
    let r = EuclideousMixV2Metrics.inletDot
    let rect = CGRect(x: at.x - r / 2, y: at.y - r / 2, width: r, height: r)
    switch state {
    case .muted:
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(Color(hex: 0x5C626C)), lineWidth: 1.5)
    case .unused:
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x2A2D34)))
    case .live:
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x4A4E57)))
    case .playing(let a):
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x4A4E57)))
        ctx.fill(Path(ellipseIn: rect), with: .color(lane.opacity(a)))
    default: break   // routing states never reach an emitter inlet
    }
}

// MARK: - §5 the emitter touches: tap to mute, hold to trace

/// The four invisible touch targets over the emitter cards (§5.3: the whole card, 52 × (2·rowH+6)). Each owns its own press machine; a tap (< 300 ms) full-toggles the output's mute (§5.1), a hold (≥ 300 ms) adds the output to `heldOutputs` until release (§5.2). Invisible to VoiceOver — the AX layer carries the button.
struct EuclideousMixV2EmitterGestures: View {
    let layout: EuclideousMixV2Layout
    let callbacks: EuclideousMixV2Callbacks
    @Binding var heldOutputs: Set<Int>
    var body: some View {
        ForEach(0..<4, id: \.self) { o in
            EuclideousMixV2EmitterTouch(card: layout.emitterCards[o],
                                        onTapMute: { callbacks.toggleOutputMute(o) },
                                        onHold: { held in if held { heldOutputs.insert(o) } else { heldOutputs.remove(o) } })
                .offset(x: layout.emitterCards[o].minX, y: layout.emitterCards[o].minY)
        }
    }
}
struct EuclideousMixV2EmitterTouch: View {
    let card: CGRect
    let onTapMute: () -> Void
    let onHold: (Bool) -> Void
    @State private var press = EuclideousRingPress()
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var touching = false
    var body: some View {
        Color.clear
            .frame(width: card.width, height: card.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { _ in
                        guard !press.down else { return }   // §5.3: no drag-cancel — a slide-off still counts by its duration
                        press.touchDown()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(EuclideousRingPress.holdSeconds * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            if case .holdBegan = press.holdTimerFired() { onHold(true) }
                        }
                    }
                    .onEnded { _ in finish(ended: true) }
            )
            .onChange(of: touching) { t in
                guard !t else { return }   // a cancelled touch (no onEnded) ends as a hold would (§5.3)
                Task { @MainActor in if press.down { finish(ended: false) } }
            }
            .onDisappear { if press.down { finish(ended: false) } }
            .accessibilityHidden(true)
    }
    private func finish(ended: Bool) {
        holdTask?.cancel(); holdTask = nil
        switch ended ? press.touchEnded() : press.touchCancelled() {
        case .tap: onTapMute()
        case .holdEnded, .holdBegan: onHold(false)
        case .none: break
        }
    }
}

/// §8.1 the MIX emitters for VoiceOver: a toggle button over each card, "Output A, live/unused/muted" (playing is not announced), value "muted"/"not muted", hint "Tap to mute; hold to show its parts", and a double-tap that toggles the mute (§10). The sighted tap/hold is the gesture layer; this carries the a11y and the action.
struct EuclideousMixV2EmitterAX: View {
    let layout: EuclideousMixV2Layout
    let input: EuclideousMixV2Input
    let callbacks: EuclideousMixV2Callbacks
    var body: some View {
        ForEach(0..<4, id: \.self) { o in
            let muted = o < input.outputMuted.count && input.outputMuted[o]
            let anyRouted = (0..<8).contains { p -> Bool in
                let l = p / 2 < input.lines.count ? input.lines[p / 2] : EuclidLine(noteSel: .all)
                let mask = p % 2 == 1 ? l.notesOutMaskResolved(lane: p / 2) : l.riffOutMaskResolved(lane: p / 2)
                return !euclideousMixLayerIsOff(l, notes: p % 2 == 1) && mask & (UInt8(1) << UInt8(o)) != 0
            }
            Color.clear.frame(width: layout.emitterCards[o].width, height: layout.emitterCards[o].height)
                .offset(x: layout.emitterCards[o].minX, y: layout.emitterCards[o].minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousMixAX.emitterState(output: o, muted: muted, anyRouted: anyRouted))
                .accessibilityValue(EuclideousMixAX.emitterStateValue(muted: muted))
                .accessibilityHint(EuclideousMixAX.emitterHint)
                .accessibilityAddTraits(.isButton)
                .ringToggleTrait()
                .accessibilityAction { callbacks.toggleOutputMute(o) }
                .accessibilitySortPriority(Double(500 - o))
        }
    }
}
