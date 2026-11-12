//  MixPanelViews.swift — MIX ROWS (2026-11-03): the views of the MIX panel. They only PAINT what `MixPanel.swift` computes (frames, looks, values, strings — one function for the draw code and the tests) and wire a finger to the page's
//  funnels. The panel is built to cost little: each lane band draws its strip, pool chips and two rolls in ONE Canvas under ONE 60 fps TimelineView (paused while nothing runs); the sliders, toggles and tiles are plain SwiftUI views
//  OUTSIDE any TimelineView, so a frame never re-runs them. The panel sits in an `EuclideousStackBreak` at its call site (the extension's 1 MB main stack).

import SwiftUI

private extension Color {
    init(_ c: HocketColor) { self = Color(hex: c.hex).opacity(c.alpha) }
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

// MARK: - what the page hands the panel

/// One lane's rhythm strip as the card's own plan describes it (`laneStripPlan`) plus what the live position needs (`EuclidCometBar`'s own inputs): the legs (one, or two for PING-PONG), the step count, the direction, the step length, the restart
/// chains and the lane's mute — so the strip's "current step" is the one the card's comet is on.
struct EuclideousMixStripFeed {
    var legs: [EuclideousStripLeg]
    var n: Int
    var dir: EuclidDir
    var sub: Double
    var chains: EuclideousLaneRestartChains?
    var lanePlaying: Bool
    var mutedAt: ((Double) -> Bool)?
    var rate: EuclideousRateMap? = nil   // RATE ferry (2026-11-12): the MIX strip comet sweeps at the lane's override speed during a run
}

struct EuclideousMixPanelInput {
    var size: CGSize
    var lines: [EuclidLine]
    var accents: [Color]
    var soloDim: [Bool]
    var strips: [EuclideousMixStripFeed]
    var pools: [[Int]]
    var poolName: (Int, [Int]) -> String
    var rolls: NoteRollLive
    var beatAt: (Date) -> Double
    var clock: EuclidLiveClock
    var live: Bool
    var stripMode: EuclideousMixStripMode
    var hocketRules: [HocketRule]
    var hocketLive: HocketLiveModel
}
struct EuclideousMixCallbacks {
    /// The card's own play / SOLO tiles at a frame (tile size, touch target) — same looks, same taps, same undo.
    var play: (Int, CGSize, CGSize) -> AnyView
    var solo: (Int, CGSize, CGSize) -> AnyView
    var lockBadge: (Int) -> AnyView?
    /// The page's burst funnel: (lane, newStep, mutate).
    var editStep: (Int, Bool, @escaping (inout EuclidLine) -> Void) -> Void
    var toggleOn: (Int, EuclideousCardPart) -> Void
    var toggleOut: (Int, EuclideousCardPart, Int) -> Void
}

// MARK: - the panel

struct EuclideousMixPanel: View {
    let input: EuclideousMixPanelInput
    let callbacks: EuclideousMixCallbacks

    var body: some View {
        let L = euclideousMixRowsLayout(size: input.size)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { lane in
                EuclideousMixBandView(lane: lane, layout: L, input: input, callbacks: callbacks)
                    .accessibilitySortPriority(Double(1000 - lane))
            }
            EuclideousMixLinesLayer(layout: L, input: input)
            EuclideousMixEmitterAX(layout: L, input: input)
        }
        .frame(width: input.size.width, height: input.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousMixAX.panel)
    }
}

// MARK: - one lane band

struct EuclideousMixBandView: View {
    let lane: Int
    let layout: EuclideousMixRowsLayout
    let input: EuclideousMixPanelInput
    let callbacks: EuclideousMixCallbacks

    private var band: EuclideousMixBandFrames { layout.bands[lane] }
    private var line: EuclidLine { lane < input.lines.count ? input.lines[lane] : EuclidLine(noteSel: .all) }
    private var accent: Color { input.accents[lane % input.accents.count] }
    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -band.frame.minX, dy: -band.frame.minY) }
    private var soloDim: Bool { lane < input.soloDim.count && input.soloDim[lane] }
    /// §A5: everything below the top row dims ONCE to 42 % — solo-silenced, no hits, or muted (PLAY off); it stays live.
    private var laneDim: Bool { euclideousMixLaneDimmed(soloSilenced: soloDim, noHits: euclideousMixLaneHasNoHits(legs: input.strips[lane].legs), muted: !input.strips[lane].lanePlaying) }
    private var locked: AnyView? { callbacks.lockBadge(lane) }

    var body: some View {
        let strip = locked == nil ? band.strip : band.stripWithBadge
        let hasHits = line.pulses > 0 || line.patternMissResolved
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.07))
            RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.33), lineWidth: 1)
            EuclideousMixBandCanvas(lane: lane, band: band, strip: strip, input: input, locked: locked != nil, laneDim: laneDim)
                .allowsHitTesting(false)
            // the top row: the card's own play and SOLO tiles at these frames, the badge between SOLO and the strip
            callbacks.play(lane, local(band.play).size, EuclideousMixRowsMetrics.playTarget)
                .frame(width: EuclideousMixRowsMetrics.playTarget.width, height: EuclideousMixRowsMetrics.playTarget.height, alignment: .top)
                .offset(x: local(band.play).minX, y: local(band.play).minY)
                .accessibilitySortPriority(100)
            Color.clear.frame(width: strip.width, height: strip.height).offset(x: local(strip).minX, y: local(strip).minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousMixStripSpokenView.label(for: input.strips[lane]))
                .accessibilitySortPriority(99)
            if let badge = locked {
                badge.frame(width: EuclideousLockBadge.size, height: EuclideousLockBadge.size).scaleEffect(EuclideousMixRowsMetrics.badge / EuclideousLockBadge.size)
                    .frame(width: EuclideousMixRowsMetrics.badge, height: EuclideousMixRowsMetrics.badge)
                    .offset(x: local(band.badge).minX, y: local(band.badge).minY)
                    .accessibilitySortPriority(98.5)
            }
            callbacks.solo(lane, local(band.solo).size, EuclideousMixRowsMetrics.soloTarget)
                .frame(width: EuclideousMixRowsMetrics.soloTarget.width, height: EuclideousMixRowsMetrics.soloTarget.height, alignment: .top)
                .offset(x: local(band.solo).minX, y: local(band.solo).minY)
                .accessibilitySortPriority(98)
            EuclideousMixPoolAX(lane: lane, area: local(band.pool), input: input).accessibilitySortPriority(97)
            // the part rows: everything below the top row dims to 42 % (§A5: one dim whatever the cause)
            Group {
                partRow(part: .riff, frames: band.riff, base: 96, hasHits: hasHits)
                partRow(part: .notes, frames: band.notes, base: 86, hasHits: hasHits)
            }
            .opacity(laneDim ? EuclideousLaneDimStyle.opacity : 1)
            .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: laneDim)
        }
        .frame(width: band.frame.width, height: band.frame.height, alignment: .topLeading)
        .offset(x: band.frame.minX, y: band.frame.minY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EuclideousMixAX.lane(lane))
    }

    private func partRow(part: EuclideousCardPart, frames f: EuclideousMixRowFrames, base: Double, hasHits: Bool) -> some View {
        let notes = part == .notes
        let on = !euclideousMixLayerIsOff(line, notes: notes)
        let mask = notes ? line.notesOutMaskResolved(lane: lane) : line.riffOutMaskResolved(lane: lane)
        return ZStack(alignment: .topLeading) {
            EuclideousMixPartToggle(lane: lane, part: part, on: on, accent: accent, size: f.toggle.size, rules: input.hocketRules, live: input.hocketLive) { callbacks.toggleOn(lane, part) }
                .offset(x: local(f.toggle).minX, y: local(f.toggle).minY)
                .accessibilitySortPriority(base)
            EuclideousMixRollAX(lane: lane, part: part, on: on && mask & 0x0F != 0 && hasHits, area: local(f.roll), input: input)
                .accessibilitySortPriority(base - 1)
            ForEach(EuclideousMixSliderKind.allCases, id: \.rawValue) { kind in
                EuclideousMixSliderTile(kind: kind, part: part, value: euclideousMixSliderValue(of: line, kind: kind, notes: notes), accent: accent, size: f.sliders[kind.rawValue].size, dimmed: euclideousMixOwnDimOpacity(laneDimmed: laneDim, partOff: !on, target: .slider) < 1,
                                        onEditStep: { newStep, mutate in callbacks.editStep(lane, newStep, mutate) })
                    .offset(x: local(f.sliders[kind.rawValue]).minX, y: local(f.sliders[kind.rawValue]).minY)
                    .accessibilitySortPriority(base - 2 - Double(kind.rawValue))
            }
            ForEach(0..<4, id: \.self) { o in
                EuclideousMixOutButton(output: o, on: euclideousJackIsPlugged(mask: mask, output: o), part: part, size: f.outButtons[o].size) { callbacks.toggleOut(lane, part, o) }
                    .offset(x: local(f.outButtons[o]).minX, y: local(f.outButtons[o]).minY)
                    .accessibilitySortPriority(base - 6 - Double(o) * 0.1)
            }
        }
    }
}

// MARK: - the band's live canvas: strip, pool chips, two rolls (one TimelineView, one Canvas)

struct EuclideousMixBandCanvas: View {
    let lane: Int
    let band: EuclideousMixBandFrames
    let strip: CGRect
    let input: EuclideousMixPanelInput
    let locked: Bool
    let laneDim: Bool

    private var accent: Color { input.accents[lane % input.accents.count] }

    var body: some View {
        let origin = band.frame.origin
        let feed = input.strips[lane]
        let line = lane < input.lines.count ? input.lines[lane] : EuclidLine(noteSel: .all)
        let pool = lane < input.pools.count ? input.pools[lane] : []
        let rows: [(notes: Bool, frames: EuclideousMixRowFrames)] = [(false, band.riff), (true, band.notes)]
        let partOn = rows.map { !euclideousMixLayerIsOff(line, notes: $0.notes) }
        let model = input.rolls
        let clock = input.clock, beatAt = input.beatAt, mode = input.stripMode, accent = self.accent, dim = laneDim
        let poolFrames = euclideousMixPoolFrames(area: band.pool)
        let cells = euclideousMixStripCells(strip: strip, steps: feed.n, mode: mode)
        let poolName = input.poolName
        let lane = self.lane
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !input.live)) { tl in
            Canvas { ctx, size in
                ctx.translateBy(x: -origin.x, y: -origin.y)
                let now = beatAt(tl.date)
                let notesA = model.model.parts[2 * lane], notesB = model.model.parts[2 * lane + 1]
                // ── the rhythm strip (the top row: never dimmed)
                let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
                let running = clock.playing && feed.lanePlaying && !(feed.mutedAt?(liveBeat) ?? false)
                let raw = (feed.rate?.active ?? false)   // RATE: the override's rate branch ignores chains, so route it through regardless of whether the lane has restart chains
                    ? euclideousLaneCometChainRaw(beat: liveBeat, n: feed.n, dir: feed.dir, sub: feed.sub, chains: feed.chains ?? .off, legacySpanBeats: 0, rate: feed.rate)
                    : (feed.chains.map { euclideousLaneCometChainRaw(beat: liveBeat, n: feed.n, dir: feed.dir, sub: feed.sub, chains: $0, legacySpanBeats: 0) }
                        ?? euclidCometRaw(mTickBeat: liveBeat, sub: feed.sub, spanBeats: 0, n: feed.n, dir: feed.dir))
                let legIdx = min(max(0, feed.legs.count - 1), euclideousStripLegIndex(raw: running ? raw : 0, n: feed.n, legCount: feed.legs.count))
                let steps = feed.legs.isEmpty ? [] : euclideousMixStripSteps(hits: feed.legs[legIdx].hits)
                let current = euclideousMixStripCurrent(raw: raw, steps: feed.n, dir: feed.dir, running: running)
                for (i, cell) in cells.enumerated() where i < steps.count {
                    let look = euclideousMixCellLook(isHit: steps[i].isHit, isCurrent: current == i)
                    let shape = Path(roundedRect: cell, cornerRadius: EuclideousMixStripMetrics.radius)
                    switch look.fill {
                    case .solid(let hex): ctx.fill(shape, with: .color(Color(hex: hex)))
                    case .lane(let a): ctx.fill(shape, with: .color(accent.opacity(a)))
                    }
                    if look.bottomLine {
                        var c = ctx; c.clip(to: shape)
                        c.fill(Path(CGRect(x: cell.minX, y: cell.maxY - EuclideousMixStripMetrics.bottomLine, width: cell.width, height: EuclideousMixStripMetrics.bottomLine)), with: .color(accent))
                    }
                }
                // ── below the top row: ONE dim to 42 % (§A5: solo-silenced, no hits or muted)
                var below = ctx
                if dim { below.opacity = EuclideousLaneDimStyle.opacity }
                // the pool: eight rank chips, rank 8 at the top
                let lit = euclideousMixLitRanks(parts: [notesA, notesB], nowBeat: now)
                let chips = euclideousMixPoolChips(sortedPool: pool, lit: lit, name: { poolName($0, pool) })
                for (i, chip) in chips.enumerated() where i < poolFrames.count {
                    let f = poolFrames[i]
                    var c = below
                    if chip.faded { c.opacity = below.opacity * EuclideousMixPoolMetrics.fadedAlpha }
                    c.fill(Path(roundedRect: f, cornerRadius: EuclideousMixPoolMetrics.radius), with: .color(chip.lit ? accent : Color(hex: EuclideousMixPoolMetrics.idleHex)))
                    let ink = Color(hex: chip.lit ? EuclideousMixPoolMetrics.litTextHex : EuclideousMixPoolMetrics.idleTextHex)
                    euclideousMixDrawChipText(&c, chip: chip, frame: f, ink: ink)
                }
                // the two rolls
                for (k, row) in rows.enumerated() {
                    let rollFrame = row.frames.roll
                    guard rollFrame.width > 0 else { continue }
                    var c = below
                    c.opacity = below.opacity * euclideousMixOwnDimOpacity(laneDimmed: dim, partOff: !partOn[k], target: .roll)   // an OFF part: its roll draws at 42 % and stays live — never 42 % of 42 %
                    drawRoll(&c, frame: rollFrame, notes: k == 0 ? notesA : notesB, now: now, size: rollFrame.size)
                }
            }
            .frame(width: band.frame.width, height: band.frame.height)
        }
        .frame(width: band.frame.width, height: band.frame.height)
    }

    private func drawRoll(_ ctx: inout GraphicsContext, frame: CGRect, notes: [NoteRollNote], now: Double, size: CGSize) {
        typealias R = EuclideousMixRollMetrics
        let roll = euclideousMixRoll(notes: notes, nowBeat: now, barBeats: max(1, input.clock.beatsPerBar), size: size)
        var layer = ctx
        let shape = Path(roundedRect: frame, cornerRadius: R.radius)
        layer.fill(shape, with: .color(Color(hex: R.groundHex)))
        layer.clip(to: shape)
        for r in roll.soundingRows { layer.fill(Path(r.offsetBy(dx: frame.minX, dy: frame.minY)), with: .color(accent.opacity(R.soundingRowAlpha))) }   // §A4: under the rank lines and the notes
        for y in roll.rowLines { layer.fill(Path(CGRect(x: frame.minX, y: frame.minY + y - 0.5, width: frame.width, height: 1)), with: .color(Color(hex: R.lineHex))) }
        for n in roll.notes {
            let rect = n.rect.offsetBy(dx: frame.minX, dy: frame.minY)
            let path = Path(roundedRect: rect, cornerRadius: R.noteRadius)
            switch n.look {
            case .sounding: layer.fill(path, with: .color(accent))
            case .ended: layer.fill(path, with: .color(accent.opacity(R.endedAlpha)))
            case .silent: layer.stroke(path, with: .color(accent.opacity(R.silentBorderAlpha)), lineWidth: 1)
            }
        }
        layer.fill(Path(CGRect(x: frame.minX + roll.playheadX - R.playheadW / 2, y: frame.minY, width: R.playheadW, height: frame.height)), with: .color(Color(hex: R.playheadHex).opacity(R.playheadAlpha)))
    }
}

/// §A3: the riff grid label's styles at the chip's size (`EuclideousRankLabelStyle.mixChip`) — the rank (bold, 70 % of the name's colour, raised) then the name (the note part heavy, its octave bold, one baseline), left-aligned; text past the chip is clipped, never shrunk.
func euclideousMixDrawChipText(_ ctx: inout GraphicsContext, chip: EuclideousMixPoolChip, frame f: CGRect, ink: Color, radius: CGFloat = EuclideousMixPoolMetrics.radius) {
    let style = EuclideousRankLabelStyle.mixChip(chipHeight: f.height)
    var c = ctx
    c.clip(to: Path(roundedRect: f, cornerRadius: radius))
    let rank = c.resolve(Text("\(chip.rank)").font(rankLabelFont(EuclideousRankLabelStyle.rankWeight, style.rankSize)).foregroundColor(ink.opacity(EuclideousRankLabelStyle.rankAlphaFactor)))
    let rankSize = rank.measure(in: CGSize(width: 200, height: 200))
    let at = euclideousMixChipTextLayout(frame: f, rankWidth: rankSize.width, style: style)
    guard let name = chip.name else {
        // an empty pool: the rank alone, in the same place (the chip already draws at 40 %)
        c.draw(rank, at: CGPoint(x: at.rankX, y: f.midY - rankSize.height / 2), anchor: .topLeading)
        return
    }
    let parts = style.parts(of: name)
    let note = c.resolve(Text(parts.note).font(rankLabelFont(EuclideousRankLabelStyle.noteWeight, style.noteSize)).foregroundColor(ink))
    let octave = c.resolve(Text(parts.octave).font(rankLabelFont(EuclideousRankLabelStyle.octaveWeight, style.octaveSize)).foregroundColor(ink))
    let noteSize = note.measure(in: CGSize(width: 200, height: 200))
    // one baseline: the name's line box centred on the chip, the octave and the (raised) rank hung from it
    let octaveSize = octave.measure(in: CGSize(width: 200, height: 200))
    let top = f.midY - noteSize.height / 2, baseline = top + note.firstBaseline(in: noteSize)
    c.draw(note, at: CGPoint(x: at.nameX, y: top), anchor: .topLeading)
    c.draw(octave, at: CGPoint(x: at.nameX + noteSize.width, y: baseline - octave.firstBaseline(in: octaveSize)), anchor: .topLeading)
    c.draw(rank, at: CGPoint(x: at.rankX, y: baseline - at.rankRaise - rank.firstBaseline(in: rankSize)), anchor: .topLeading)
}


// MARK: - VoiceOver leaves that read the live feed (4 Hz; paused when nothing runs)

enum EuclideousMixStripSpokenView {
    static func label(for feed: EuclideousMixStripFeed) -> String {
        guard let leg = feed.legs.first else { return euclideousMixStripSpoken(hits: 0, steps: feed.n) }
        return euclideousMixStripSpoken(hits: leg.hits.filter { $0.kind != .rhythmRest }.count, steps: feed.n)
    }
}
struct EuclideousMixPoolAX: View {
    let lane: Int
    let area: CGRect
    let input: EuclideousMixPanelInput
    var body: some View {
        let pool = lane < input.pools.count ? input.pools[lane] : []
        return TimelineView(.periodic(from: Date(), by: 0.25)) { tl in
            let now = input.beatAt(tl.date)
            let model = input.rolls.model
            let lit = euclideousMixLitRanks(parts: [model.parts[2 * lane], model.parts[2 * lane + 1]], nowBeat: now)
            let chips = euclideousMixPoolChips(sortedPool: pool, lit: lit, name: { input.poolName($0, pool) })
            let names = chips.reversed().filter { $0.lit }.compactMap { $0.name }
            Color.clear.frame(width: area.width, height: area.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(euclideousMixPoolSpoken(litNames: names))
        }
        .frame(width: area.width, height: area.height)
        .offset(x: area.minX, y: area.minY)
    }
}
struct EuclideousMixRollAX: View {
    let lane: Int
    let part: EuclideousCardPart
    let on: Bool
    let area: CGRect
    let input: EuclideousMixPanelInput
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.25)) { tl in
            let playing = on && euclideousMixRollPlaying(notes: input.rolls.model.parts[2 * lane + part.rawValue], nowBeat: input.beatAt(tl.date))
            Color.clear.frame(width: area.width, height: area.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EuclideousMixAX.roll(notes: part == .notes, playing: playing))
        }
        .frame(width: area.width, height: area.height)
        .offset(x: area.minX, y: area.minY)
    }
}

// MARK: - the part's on/off toggle

struct EuclideousMixPartToggle: View {
    let lane: Int
    let part: EuclideousCardPart
    let on: Bool
    let accent: Color
    let size: CGSize
    let rules: [HocketRule]
    @ObservedObject var live: HocketLiveModel
    let onTap: () -> Void

    var body: some View {
        let lit = rules.contains(where: { $0.isLit })
        let shape: EuclideousGlyphShape = part == .notes ? .bar : .square
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1F2127))
            Group {
                if lit {
                    HocketPartGlyph(shape: shape, on: on, fill: accent, lane: lane, rules: rules, live: live, ground: Color(hex: 0x1F2127))
                } else {
                    EuclideousTabGlyphView(shape: shape, on: on, fill: accent)
                }
            }
            .offset(x: 8, y: 9)
            Text(part.label).font(heavyMono(8)).tracking(0.08 * 8).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundColor(Color(hex: on ? 0xF2F4F7 : 0x8A909A))
                .offset(x: 8, y: 9 + 12 + 5)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .hocketPartAX(base: EuclideousMixAX.toggle(notes: part == .notes, on: on), lane: lane, notes: part == .notes, partOff: !on, rules: rules, live: live)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - the A–D toggles

struct EuclideousMixOutButton: View {
    let output: Int
    let on: Bool
    let part: EuclideousCardPart
    let size: CGSize
    let onTap: () -> Void
    var body: some View {
        let colour = Color(euclideousMixOutputColour(output))
        let letter = euclideousJackLetters[max(0, min(3, output))]
        return ZStack {
            if on { Circle().fill(colour) } else { Circle().strokeBorder(Color(hex: 0x4A4E57), lineWidth: 2) }
            Text(letter).font(heavyMono(9)).foregroundColor(on ? Color(hex: 0x0D0F14) : Color(hex: 0x8A909A))
        }
        .frame(width: 24, height: 24)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousMixAX.out(notes: part == .notes, output: output, on: on))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - the sliders

struct EuclideousMixSliderTile: View {
    let kind: EuclideousMixSliderKind
    let part: EuclideousCardPart
    let value: Int
    let accent: Color
    let size: CGSize
    /// The part is off: the tile draws at 42 % and stays live (it writes; it never switches the part on).
    let dimmed: Bool
    let onEditStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void

    private enum Axis { case horizontal, vertical }
    @State private var burst = EuclideousPadUndoBurst()
    @State private var axis: Axis? = nil
    @State private var startValue = 0
    @State private var lastWritten: Int? = nil
    @GestureState private var gestureLive = false
    private func now() -> Double { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        typealias S = EuclideousMixSliderMetrics
        let tile = CGRect(origin: .zero, size: size)
        let g = euclideousMixSliderGeometry(tile: tile, kind: kind, value: value)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: S.radius).fill(Color(hex: 0x1F2127))
            Text(kind.label).font(heavyMono(S.labelSize)).tracking(0.08 * S.labelSize).foregroundColor(Color(hex: 0x8A909A)).lineLimit(1)
                .offset(x: S.inset, y: S.inset).allowsHitTesting(false)
            Text(euclideousMixSliderText(kind: kind, value: value)).font(heavyMono(S.valueSize)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
                .frame(width: size.width - 2 * S.inset, alignment: .trailing).offset(x: S.inset, y: S.inset - 1).allowsHitTesting(false)
            RoundedRectangle(cornerRadius: S.trackH / 2).fill(Color(hex: 0x30333A)).frame(width: g.track.width, height: g.track.height).offset(x: g.track.minX, y: g.track.minY)
            if let tick = g.tick { Rectangle().fill(Color(hex: 0x4A4E57)).frame(width: tick.width, height: tick.height).offset(x: tick.minX, y: tick.minY) }
            Rectangle().fill(accent).frame(width: g.fill.width, height: g.fill.height).offset(x: g.fill.minX, y: g.fill.minY)
            Circle().fill(accent).overlay(Circle().strokeBorder(Color(hex: 0x1F2127), lineWidth: S.thumbRing)).frame(width: g.thumb.width, height: g.thumb.height).offset(x: g.thumb.minX, y: g.thumb.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
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
                let v = euclideousMixSliderDrag(kind: kind, startValue: startValue, translation: d.translation.width, trackWidth: g.track.width)
                if v == lastWritten { return }
                lastWritten = v
                write(v, newStepAlways: false)
            }
            .onEnded { _ in finish() })
        .onChange(of: gestureLive) { live in if !live { finish() } }   // the system cancelled the touch: close its burst so the next drag is a fresh undo step
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousMixAX.slider(kind: kind, notes: part == .notes, value: value))
        .accessibilityAdjustableAction { direction in write(euclideousMixSliderStep(kind: kind, value: value, up: direction == .increment), newStepAlways: true) }
        .accessibilityAction(named: EuclideousMixAX.reset) { reset() }
    }
    private func finish() {
        if axis == .horizontal { burst.touchEnd(at: now()) }
        axis = nil; lastWritten = nil
    }
    private func write(_ v: Int, newStepAlways: Bool) {
        let newStep = newStepAlways ? true : burst.nextWriteNeedsNewStep()
        let notes = part == .notes, k = kind
        onEditStep(newStep) { l in euclideousMixSliderWrite(&l, kind: k, notes: notes, value: v) }   // live while the part is off: the unguarded write — it never turns the layer on
    }
    private func reset() {
        let notes = part == .notes, k = kind
        onEditStep(true) { l in euclideousMixSliderReset(&l, kind: k, notes: notes) }
    }
}

// MARK: - the lines, the origin dots and the four emitters (one layer, no touches)

struct EuclideousMixLinesLayer: View {
    let layout: EuclideousMixRowsLayout
    let input: EuclideousMixPanelInput

    var body: some View {
        let masks: [UInt8] = (0..<8).map { p in
            let l = p / 2 < input.lines.count ? input.lines[p / 2] : EuclidLine(noteSel: .all)
            return p % 2 == 1 ? l.notesOutMaskResolved(lane: p / 2) : l.riffOutMaskResolved(lane: p / 2)
        }
        let on: [Bool] = (0..<8).map { p in
            let l = p / 2 < input.lines.count ? input.lines[p / 2] : EuclidLine(noteSel: .all)
            return !euclideousMixLayerIsOff(l, notes: p % 2 == 1)
        }
        let lines = euclideousMixLines(layout: layout, masks: masks, partOn: on)
        let dots = euclideousMixOriginDots(lines: lines)
        let accents = input.accents, beatAt = input.beatAt, model = input.rolls, tempo = input.clock.tempo, L = layout
        let noHits: [Bool] = (0..<4).map { $0 < input.strips.count ? euclideousMixLaneHasNoHits(legs: input.strips[$0].legs) : false }
        let left = layout.bandW - 8
        let canvasW = layout.size.width - left
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !input.live)) { tl in
            Canvas { ctx, size in
                ctx.translateBy(x: -left, y: 0)
                typealias M = EuclideousMixLineMetrics
                let now = beatAt(tl.date)
                let parts = model.model.parts
                let acts = lines.map { euclideousMixLineActivity(notes: parts[$0.part], output: $0.output, nowBeat: now, tempo: tempo) }
                for i in euclideousMixLineDrawOrder(activities: acts) {
                    let l = lines[i], look = euclideousMixLineLook(activity: acts[i], laneNoHits: noHits[l.lane])
                    var p = Path(); p.move(to: l.from); p.addCurve(to: l.to, control1: l.c1, control2: l.c2)
                    ctx.stroke(p, with: .color(accents[l.lane % accents.count].opacity(look.alpha)), style: StrokeStyle(lineWidth: look.width, lineCap: .round))
                }
                for d in dots {
                    ctx.fill(Path(ellipseIn: CGRect(x: d.at.x - M.originDot / 2, y: d.at.y - M.originDot / 2, width: M.originDot, height: M.originDot)), with: .color(accents[d.lane % accents.count].opacity(euclideousMixOriginDotAlpha(laneNoHits: noHits[d.lane]))))
                }
                for o in 0..<4 {
                    let f = L.emitters[o]
                    let a = euclideousMixEmitterActivity(parts: parts, output: o, nowBeat: now, tempo: tempo)
                    let look = euclideousMixEmitterLook(activity: a)
                    let colour = Color(euclideousMixOutputColour(o))
                    let ring = Path(ellipseIn: f.insetBy(dx: M.emitterRing / 2, dy: M.emitterRing / 2))
                    ctx.fill(Path(ellipseIn: f), with: .color(Color(hex: M.emitterIdleHex)))
                    if look.fill > 0 { ctx.fill(Path(ellipseIn: f), with: .color(colour.opacity(look.fill))) }
                    ctx.stroke(ring, with: .color(colour), lineWidth: M.emitterRing)
                    ctx.draw(Text(euclideousJackLetters[o]).font(heavyMono(M.emitterLetter)).foregroundColor(look.letterIsInk ? Color(hex: M.inkHex) : colour), at: CGPoint(x: f.midX, y: f.midY), anchor: .center)
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
struct EuclideousMixEmitterAX: View {
    let layout: EuclideousMixRowsLayout
    let input: EuclideousMixPanelInput
    var body: some View {
        ForEach(0..<4, id: \.self) { o in
            TimelineView(.periodic(from: Date(), by: 0.25)) { tl in
                let a = euclideousMixEmitterActivity(parts: input.rolls.model.parts, output: o, nowBeat: input.beatAt(tl.date), tempo: input.clock.tempo)
                Color.clear.frame(width: layout.emitters[o].width, height: layout.emitters[o].height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EuclideousMixAX.emitter(output: o, active: a > 0.5))
            }
            .frame(width: layout.emitters[o].width, height: layout.emitters[o].height)
            .offset(x: layout.emitters[o].minX, y: layout.emitters[o].minY)
            .accessibilitySortPriority(Double(500 - o))
        }
    }
}
