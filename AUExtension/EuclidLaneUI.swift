//  EuclidLaneUI.swift
//  MidiSpark — the shared EUCLID lane visual/gesture components, extracted (Paul 2026-10-05,
//  EUCLIDEOUS) out of `ProcessorBox` (GridUI.swift) so a brand-new standalone page can reuse
//  the SAME lane box / comet bar / gesture pad / beacon the BUILD-page EUCLID processor editor
//  already uses, instead of a second, drift-prone copy — this codebase's own repeatedly-stated
//  discipline ("share the engine's own formula, never re-derive it") applied to UI, not engine,
//  code. `ProcessorBox`'s own `case .euclid:` now calls these too; its behaviour is unchanged.
//  Foundation/SwiftUI/UIKit-only, same seam as GridUI.swift itself (standalone-plan.md rule 1).

import SwiftUI
import UIKit

/// The 6 "live clock" scalars `EuclidCometBar`/`EuclidBeacon` need to extrapolate their own
/// sweep (a `TimelineView` reads real wall-clock time, so it needs a beat ANCHOR to project
/// from) — bundled into one value so two components' parameter lists don't each separately
/// duplicate the same 6 names. Mirrors exactly what `ProcessorBox` already carries as 6 flat
/// stored properties (`gridStepBeats`/`gridCols`/`beatAnchor`/`beatAnchorAt`/`tempo`/
/// `clockPlaying`) — this struct is just those 6, bundled for a caller that isn't `ProcessorBox`.
struct EuclidLiveClock {
    var stepBeats: Double     // the DEFAULT grid-column clock for SPAN-ladder resolution
    var cols: Int             // the real row/part width SPAN measures against
    var anchor: Double        // beat position at `anchorAt` — a TimelineView extrapolates forward from here
    var anchorAt: Date
    var tempo: Double
    var playing: Bool         // the HOST transport (a lane's OWN play/stop is a separate, caller-supplied flag)
    var swing: Double = 50    // swing %, 50…75 — only the riff-grid walk tags read it (a hit's real onset is swing-warped)
    var beatsPerBar: Double = 4   // the host's real bar length (quarter notes) — only the walk tags read it (the LANES step / per-lane RESET are measured in real bars)
}

/// The play-button triangle (2026-10-13 "lane card, exact dimensions" ferry, literal: "14 wide × 18 tall,
/// sitting 4pt right of centre") — a plain custom `Shape` rather than an SF Symbol, since the ferry's own
/// pixel dimensions don't correspond to any system glyph's natural metrics. Points left-to-right (the
/// conventional play-triangle orientation).
struct EuclidPlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// ~18pt per step, vertical (hits) axis — a first-pass sensitivity (tunable): deliberately coarser than
/// NumPair's own 14pt/step scrub, since this bar is small and a finger resting on it covers a fair chunk of
/// it. The HORIZONTAL (rotate/offset) axis instead uses `euclidBoxGeometry`'s own pitch (below) — Paul
/// 2026-10-06: "the distance the finger moves should line up with the number of spaces a hit moves."
let euclidDragStepPt: CGFloat = 18

// (The step-box geometry — `euclidBoxGeometry`, `EuclidStepGroupGeometry`, `euclidGroupedBoxGeometry`, `euclidStepGroupSize` — moved to Derivations.swift unchanged in the LANE STRIP ferry, 2026-10-21, so the strip's layout
// tests reach the real frames. Same names, same bodies.)

/// Builds the floating drag-HUD payload for a lane's gesture — a free function (not baked into
/// `EuclidLaneBox` itself) so every caller constructs the SAME "ALL LANES" vs "LANE N" label the
/// same way, without duplicating the logic at each call site.
func euclidLaneDragHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
    EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                       primary: "\(line.pulses) HITS OUT OF \(line.steps)", secondary: "OFFSET BY \(line.rotate)", point: point)
}

/// One EUCLID lane: a PLAY/STOP icon beside the comet-bar step track. Explicitly parameterized
/// (no implicit `self` reads into some enclosing giant view type) so it's callable from
/// `ProcessorBox` (today's BUILD-page EUCLID editor) AND from Euclideous (Paul 2026-10-05)
/// alike. `selected`/`touched` are CALLER-COMPUTED booleans, not internal `@State` — only the
/// caller sees all 4 sibling lanes at once, so cross-lane state (which lane is selected, which
/// lanes currently have a finger down) can only live there. `height` is an explicit parameter —
/// NOT a hardcoded constant like the original private `euclidLaneH` — specifically so Euclideous
/// can render its lanes dramatically larger than BuildPage's cramped inline processor-panel
/// version ("four Euclid lanes in the centre of the screen... a playable, grabbable instrument").
/// The PLAY/STOP button itself stays a fixed 44×44 (a sane minimum touch target) regardless of
/// `height` — only the comet bar stretches to fill the rest.
struct EuclidLaneBox: View {
    let idx: Int
    let line: EuclidLine
    let width: CGFloat
    let height: CGFloat
    let accent: Color
    let selected: Bool
    let touched: Bool
    let clock: EuclidLiveClock
    let rate: ArpRate
    let spanN: Int
    let onRotateDelta: (Int) -> Void
    let onHitsDelta: (Int) -> Void
    let onStepsDelta: (Int) -> Void
    let onAllRotateDelta: (Int) -> Void
    let onAllHitsDelta: (Int) -> Void
    let onDragState: (CGPoint?, Bool) -> Void
    let onSelect: () -> Void
    let onToggleEnabled: () -> Void
    // THE STRIP (LANE STRIP ferry, 2026-10-21 — replaces the footer bands, the NOTES-tab pips and the comet's pulse layers): the lane's riff contour over its notes keys, planned per body by the caller
    // (`EuclideousStripPlan`, built from the footers' own per-hit functions) and painted by `drawEuclideousStrip`. nil (every other caller — the regular BUILD-page EUCLID editor) ⇒ the bar draws
    // exactly as before. `stripCurrent` answers, per display frame, which step's chip is the lane's current one (the chip of the hit its riff arrow shows): it takes the UI beat and the frame's
    // date and returns the leg and buffer step of that chip, or nil.
    var strip: EuclideousStripPlan? = nil
    var stripCurrent: ((_ liveBeat: Double, _ date: Date) -> EuclideousStripCurrent?)? = nil
    // PULSE ferry (2026-10-20): the strike feed the strip's chips and keys flash from. `pulseFeed` nil (the BUILD-page editor) ⇒ no strikes. `pulseScale` is P (0 OFF / 0.6 SUBTLE / 1 FULL),
    // `pulseLive` is "the page is playing or settling after a stop" (the TimelineView's un-paused condition) and `pulseLane` is the lane's index in the feed.
    var pulseFeed: EuclideousPulseFeed? = nil
    var pulseLane: Int = 0
    var pulseScale: Double = 0
    var pulseLive: Bool = false
    // STEP-COUNT BADGE (EUCLIDEOUS PAGE REWORK, Paul 2026-10-07: "a step count shown as a number" beside the
    // comet bar, permanently) — an optional trailing sibling in the SAME play+comet HStack, same additive-
    // nil-default shape as `trailingContent` above. nil (every existing BUILD-page call site) ⇒ byte-identical.
    var stepCountBadge: AnyView? = nil
    // ITS REAL WIDTH (Euclideous "output chips + source badge" ferry, 2026-10-10) — a bug found while widening
    // this badge for that ferry: the comet bar's own `width:` below was computed as a hardcoded `width − 64`
    // (padding + play button + ONE inter-item gap), which never actually accounted for the badge's own width
    // or the SECOND gap between the comet bar and the badge — so the comet bar's internal Canvas has always
    // been told it has MORE width than the HStack genuinely gives it whenever a non-nil badge is present,
    // risking the Canvas drawing its rightmost boxes past where the badge actually starts. Default 0 (every
    // existing caller, including Euclideous's own OLD 36pt-wide badge before this fix) is still an
    // approximation for any caller that doesn't pass the real figure, but at least no longer silently wrong
    // for the one caller that now does.
    var stepCountBadgeWidth: CGFloat = 0
    // LANE SOLO (2026-10-21): the SOLO button takes the step-count box's slot (the Euclideous page passes this INSTEAD of `stepCountBadge`, whose code stays — §1.3): same frame, so the comet strip
    // doesn't move. `soloDim` is "this lane is solo-silenced": the play button and the comet composite draw at the page's 42 % (the comet's own mute dim stands down so it is 42 % once, never 42 % × 42 %);
    // the button never dims. nil / false (every other caller, incl. the regular BUILD-page EUCLID editor) ⇒ byte-identical.
    var soloButton: AnyView? = nil
    var soloButtonWidth: CGFloat = 0
    var soloDim: Bool = false
    /// Is this lane solo-silenced (for the strip's VoiceOver value: ", silenced by solo")? Not the same flag as `soloDim` when an output-ring trace already dims the card.
    var soloSilenced: Bool = false
    // EXACT DIMENSIONS (2026-10-13, "lane card, exact dimensions" ferry) — Euclideous's own styling: zero
    // self-padding (the card itself now supplies the inset), 6pt inter-item spacing (was 8), a CHIP-filled
    // triangle play button (was an SF Symbol on a translucent fill), and no own background/border (the card
    // draws both now — `selected` is always `false` at Euclideous's call site anyway). `false` (every other
    // caller, incl. the regular BUILD-page EUCLID editor) ⇒ byte-identical to before this ferry.
    var compact: Bool = false
    // STEP GROUPS (2026-10-14 ferry) — passthrough to `EuclidCometBar`'s own `grouped`; `false` (every
    // other caller, incl. the regular BUILD-page EUCLID editor) ⇒ byte-identical to before this ferry.
    var grouped: Bool = false
    // LISTEN TAB (ferry 2026-10-14 §8) — nil/defaults (every existing caller) ⇒ byte-identical. FOLLOW used to be a translucent
    // wash over the whole bar (a disclosed simplification of the ferry's "partner's colour on the lit cells"); it is now the
    // real thing: the lit cells are drawn in the PARTNER's colour (`cellTint`), faded by `cellFade`, and the comet sweeps at the
    // rate the engine really ticks (`rateBeatsOverride`). The comet itself stays the lane's own colour.
    var listenShadowTint: Color? = nil   // SHADOW: a footer-height band at the bottom, no text
    /// The FINISHED pattern to draw (count = the step count) when this lane's own pulses/steps are NOT what plays — a FOLLOW
    /// lane plays its partner's pattern, so its cells (and the footer drawn inside them) must come from that, not from
    /// `line`. nil (every other lane, every other caller) ⇒ the bar draws from `line` exactly as before.
    var patternOverride: [Bool]? = nil
    /// The partner's colour for the LIT cells (and their flash/glow); nil ⇒ the lane's own `accent`.
    var cellTint: Color? = nil
    /// 1 = full strength; < 1 fades the lit cells' fill (FOLLOW: `euclideousListenCellFade`).
    var cellFade: Double = 1
    /// The step length (beats) the comet sweeps at when it is NOT `rate.beats` — a FOLLOW lane ticks at the partner's rate ×
    /// the multiplier, which is not always an `ArpRate`. `rate` still decides the step GROUPING (4, or 3 under triplet feel).
    var rateBeatsOverride: Double? = nil
    // RESTART CHAINS (ferry 2026-10-19, was the LANES GRID's `restartGrid`): the lane's resolved restart chains, so the comet and hit
    // flashes follow the rhythm origin the engine really phases the pattern from (nil = both chains FREE ⇒ byte-identical), and the mute
    // predicate (true = muted at that beat), so a lane the grid has muted dims and stops its comet / flashes at that point (nil = never
    // muted ⇒ byte-identical).
    var restartChains: EuclideousLaneRestartChains? = nil
    var mutedAt: ((Double) -> Bool)? = nil
    /// LANE LOCK 5.3: the comet bar's dashed "will snap back" outline (a gesture on the bar wrote a lock field that differs from L). false (every other caller) ⇒ byte-identical.
    var lockOutline: Bool = false

    var body: some View {
        let on = line.enabledResolved
        HStack(spacing: compact ? 6 : 8) {
            playButton(on: on)
                .opacity(soloDim ? EuclideousLaneDimStyle.opacity : 1)
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: soloDim)
            // WIDTH: the comet bar's own real rendered width, derived exactly from this box's layout —
            // compact: 0pt self-padding + the 44pt play button + 6pt spacing = 50pt before the comet bar,
            // PLUS — if a badge is present — its own width and the matching 6pt gap before it; non-compact
            // (the regular BUILD-page editor, unchanged): 6pt padding ×2 + 44pt play + 8pt spacing = 64,
            // badge gap 8pt. NOT measured via GeometryReader — so `EuclidCometBar` can compute its box pitch
            // (for the rotate-drag sensitivity) from the SAME width it will actually render at, no approximation.
            let gap: CGFloat = compact ? 6 : 8
            let badgeReserve: CGFloat = soloButton != nil ? (gap + soloButtonWidth) : (stepCountBadge == nil ? 0 : (gap + stepCountBadgeWidth))
            let leadReserve: CGFloat = compact ? 50 : 64
            // `patternOverride` is already FINISHED (partner's pattern, this lane's own OFFSET + INV baked in), so it goes in as a
            // hand-edited pattern with nothing left to rotate, tilt or invert — the bar's own customHits path replaces generation.
            EuclidCometBar(pulses: patternOverride.map { $0.filter { $0 }.count } ?? line.pulses,
                           steps: patternOverride?.count ?? line.steps,
                           rotate: patternOverride != nil ? 0 : line.rotate,
                           invert: patternOverride != nil ? false : line.invert, dir: line.directionResolved,
                           rate: rate, spanN: spanN, tilt: patternOverride != nil ? 0 : line.tiltResolved,
                           missStyle: patternOverride != nil ? false : line.patternMissResolved,
                           customHits: patternOverride ?? line.customHitsResolved(max(2, min(16, line.steps))),
                           strip: strip, stripCurrent: stripCurrent, pulseFeed: pulseFeed, pulseLane: pulseLane, pulseScale: pulseScale, pulseLive: pulseLive, exactStyle: compact, grouped: grouped,
                           subBeatsOverride: rateBeatsOverride, cellTint: cellTint, cellFade: cellFade,
                           restartChains: restartChains, mutedAt: mutedAt, suppressMuteDim: soloDim, soloSilencedWords: soloSilenced,
                           tint: accent, lanePlaying: on, clock: clock, width: max(1, width - leadReserve - badgeReserve),
                           onRotateDelta: onRotateDelta, onHitsDelta: onHitsDelta, onStepsDelta: onStepsDelta,
                           onAllRotateDelta: onAllRotateDelta, onAllHitsDelta: onAllHitsDelta, onDragState: onDragState)
                // THE STEP ROW IS 44pt TALL (2026-10-13 ferry): compact has zero self-padding, so the comet
                // bar gets the FULL `height` directly; non-compact keeps its original 6pt top+bottom padding
                // derivation (56−12=44, unchanged for the regular BUILD-page editor).
                .frame(height: compact ? max(20, height) : max(20, height - 12))
                .lockOutline(lockOutline, accent: accent, radius: 8)
                .overlay(alignment: .bottom) { if let t = listenShadowTint { Rectangle().fill(t).frame(height: 14).allowsHitTesting(false) } }
                .opacity(soloDim ? EuclideousLaneDimStyle.opacity : 1)   // LANE SOLO §6.1: the whole strip (cells, riff track, key row, playhead, the SHADOW band) once at 42 %
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: soloDim)
            if let soloButton { soloButton } else if let stepCountBadge { stepCountBadge }
        }
        .padding(compact ? 0 : 6)
        .frame(width: width, height: height)   // EXPLICIT width/height — the stroke/background below can never bleed past it
        // CARD DRAWS ITS OWN BACKGROUND/BORDER NOW (compact only) — `selected` is always `false` at
        // Euclideous's call site, so suppressing this wash here changes nothing for that caller except
        // removing a redundant, barely-visible 4% white tint; the regular BUILD-page editor is unaffected.
        .background(compact ? AnyView(Color.clear) : AnyView(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.07 : 0.04))))
        .overlay(compact ? AnyView(EmptyView()) : AnyView(RoundedRectangle(cornerRadius: 7).stroke(selected ? accent.opacity(0.5) : Color.clear, lineWidth: 1.5)))
        // "IN USE" SCALE-UP: `.scaleEffect` is a pure RENDER transform — it never changes what SwiftUI's layout
        // system thinks this view's size is, so neighbours in a grid of lanes never shift; the grown box simply
        // draws slightly over its own margin. `.zIndex` keeps a touched lane drawing OVER its neighbours so the
        // overlap (if any, at this modest scale) never reads as clipped.
        .scaleEffect(touched ? 1.07 : 1.0)
        .zIndex(touched ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: touched)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }   // a plain tap anywhere on the cell selects it
    }

    /// PLAY/STOP button (2026-10-13 ferry, compact only, literal): "CHIP fill, 9pt radius. The triangle is
    /// LANE-100, 14 wide × 18 tall, sitting 4pt right of centre." The STOP/disabled glyph isn't specified by
    /// the ferry (which only describes the play state) — a plain square is the conventional complement,
    /// sized/offset the same way, dimmed to match the existing on/off colour convention; a disclosed judgment
    /// call, not literal spec. Non-compact keeps the original SF-Symbol-on-translucent-fill button verbatim.
    @ViewBuilder private func playButton(on: Bool) -> some View {
        if compact {
            ZStack {
                if on {
                    EuclidPlayTriangle().fill(accent).frame(width: 14, height: 18).offset(x: 4)
                } else {
                    Rectangle().fill(accent.opacity(0.4)).frame(width: 13, height: 13).offset(x: 4)
                }
            }
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x2A2D34)))
            .contentShape(Rectangle())
            .onTapGesture { onToggleEnabled() }
        } else {
            Image(systemName: on ? "play.fill" : "stop.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(on ? accent : .white.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { onToggleEnabled() }   // its own tap wins over the cell's outer select-tap below, at this exact spot — standard SwiftUI nested-gesture precedence
        }
    }
}

/// The comet-bar step track + its gesture pad — Canvas drawing + UIKit pan/pinch bridge,
/// extracted verbatim from `ProcessorBox`'s own `euclidCometBar`/`EuclidGesturePad` (Paul
/// 2026-10-05) with its 6 implicit "live clock" reads promoted to the explicit `clock` param.
/// Every comment on the drawing logic itself is carried over unchanged — nothing about WHAT
/// gets drawn or WHY changed, only where the 6 scalars it reads come from.
struct EuclidCometBar: View {
    let pulses: Int
    let steps: Int
    let rotate: Int
    let invert: Bool
    let dir: EuclidDir
    let rate: ArpRate
    let spanN: Int
    // TILT (Paul 2026-10-09, ferry §3.4): "lane 2 shows TILT −32% but its hits look evenly spaced — check
    // that tilt is applied to the pattern and the step bar shows the result." It wasn't: Router.swift's real
    // emission DOES apply `euclidTiltPattern` to its own pattern buffer (added when TILT shipped), but this
    // bar's own Canvas drawing built its buffer from `euclidPatternInto` alone and never called the tilt warp
    // — so the step bar always showed the UN-tilted shape regardless of the control's actual value, even
    // though the audio was correct. Defaults to 0 (an exact no-op per `euclidTiltPattern`'s own design) so
    // every OTHER caller of this shared component (the regular BUILD-page EUCLID editor, which has no TILT
    // control) is byte-identical.
    var tilt: Double = 0
    // MISS STYLE (Paul 2026-10-10, "rhythm cards cleared of melody" ferry §3.2) — mirrors the `tilt` precedent
    // exactly: an independently-defaulted param so every OTHER caller of this shared component (the regular
    // BUILD-page EUCLID editor, Euclideous's own MASK-tab comet bar) is byte-identical. When true, the box this
    // loop treats as "hit" is the INVERTED pattern (the now-sounding steps, drawn with the existing rich hit
    // treatment unchanged) and the REST branch below draws the OLD, now-silent Euclid hits as a lane-coloured
    // outline instead of today's flat dim fill.
    var missStyle: Bool = false
    // HAND-EDITED PATTERN (found 2026-10-12, building the riff-grid-markers/footers ferry on top of this
    // component): this bar never had a `customHits` parameter at all — a lane with a hand-edited pattern
    // (the six-sliders ferry, same day) still drew the GENERATED Euclid shape here, not the actual edited
    // one, directly contradicting what the new per-lane footer strip (drawn immediately below this bar)
    // now correctly shows. nil (every existing caller) ⇒ byte-identical generated-pattern behaviour.
    var customHits: [Bool]? = nil
    // THE STRIP (LANE STRIP ferry, 2026-10-21): see `EuclidLaneBox`. nil (the regular BUILD-page EUCLID editor) ⇒ the lane-filled tiles and the comet draw exactly as they did.
    var strip: EuclideousStripPlan? = nil
    var stripCurrent: ((_ liveBeat: Double, _ date: Date) -> EuclideousStripCurrent?)? = nil
    // PULSE ferry (2026-10-20): the strike feed (nil ⇒ no strikes), P, whether the page is playing or settling after a stop, and the lane's index in the feed.
    var pulseFeed: EuclideousPulseFeed? = nil
    var pulseLane: Int = 0
    var pulseScale: Double = 0
    var pulseLive: Bool = false
    // EXACT DIMENSIONS (2026-10-13 "lane card, exact dimensions" ferry) — Euclideous's own cell styling: zero
    // side insets (the ferry's own cell-width table — 25.63/16.08/12.25 at 8/12/16 steps — only reconciles
    // with `euclidBoxGeometry`'s formula when the FULL steps-area width is used, hand-verified), flat LANE-
    // 100/`#2c2f36` resting hit/miss fills (replacing the previous 0.55-opacity tint / dim-fill-plus-border),
    // and the hand-placed notch marker on a hand-edited pattern. `false` (every other caller — the regular
    // BUILD-page EUCLID editor, Euclideous's own MASK-tab bar) ⇒ byte-identical to before this ferry.
    var exactStyle: Bool = false
    // STEP GROUPS (2026-10-14 ferry, "Step groups on the lane step row") — groups of `euclidStepGroupSize
    // (forRate: rate)` steps (4 normally, 3 under triplet feel), 2pt gaps within a group / 7pt between, with
    // a leftover-group rule. `false` (every other caller — the regular BUILD-page EUCLID editor) ⇒ byte-
    // identical to before this ferry; it was never asked to regroup, so it keeps `euclidBoxGeometry`'s own
    // count-dependent gap tiers entirely untouched.
    var grouped: Bool = false
    // LISTEN/FOLLOW (2026-10-16): a FOLLOW lane plays its partner's pattern at the partner's rate, in the partner's colour.
    // `subBeatsOverride` replaces `rate.beats` as the comet's step length (`rate` still decides the step grouping);
    // `cellTint` colours the LIT cells (and their flash/glow/outlines — the comet head stays `tint`, the lane's own colour);
    // `cellFade` (< 1) softens the lit cells' FILL only, so a strike's flash still reads. nil/nil/1 (every other caller) ⇒
    // byte-identical.
    var subBeatsOverride: Double? = nil
    var cellTint: Color? = nil
    var cellFade: Double = 1
    // RESTART CHAINS (ferry 2026-10-19) — see `EuclidLaneBox`. nil/nil (every other caller) ⇒ byte-identical.
    var restartChains: EuclideousLaneRestartChains? = nil
    var mutedAt: ((Double) -> Bool)? = nil
    /// LANE SOLO: the box already dims this whole bar (the lane is solo-silenced), so the bar's own LANES-mute dim stands down — one 42 %, never two multiplied.
    var suppressMuteDim: Bool = false
    var soloSilencedWords: Bool = false   // the strip's VoiceOver value adds ", silenced by solo"
    let tint: Color
    let lanePlaying: Bool
    let clock: EuclidLiveClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion   // PULSE §7.3: followed live
    // WIDTH (Paul 2026-10-06): this bar's own real rendered width, as computed by its caller (`EuclidLaneBox`)
    // — needed OUTSIDE the Canvas so the rotate-drag's step distance can be derived from the SAME box pitch
    // the Canvas will draw, via the shared `euclidBoxGeometry`. Not optional/defaulted: every current caller
    // (just `EuclidLaneBox`) already knows its own layout precisely enough to supply it.
    let width: CGFloat
    let onRotateDelta: (Int) -> Void
    let onHitsDelta: (Int) -> Void
    let onStepsDelta: (Int) -> Void
    let onAllRotateDelta: (Int) -> Void
    let onAllHitsDelta: (Int) -> Void
    let onDragState: (CGPoint?, Bool) -> Void

    var body: some View {
        let k = pulses
        let n = max(2, min(16, steps))
        let sub = max(0.03125, subBeatsOverride ?? rate.beats)
        let spanBeats = spanN > 0 ? spanLadderBeats(spanN, S: clock.stepBeats, row: Double(clock.cols) * clock.stepBeats) : 0
        // PER-LANE PLAY/STOP: a SECOND, independent gate alongside `clock.playing` (the HOST transport). `running`
        // is true only when BOTH the transport is playing AND this specific lane's own PLAY/STOP is engaged; a
        // stopped lane freezes/hides its comet exactly like a stopped transport does, regardless of whether OTHER
        // lanes (or the transport itself) are still running.
        let running = clock.playing && lanePlaying
        // ROTATE-DRAG SENSITIVITY (Paul 2026-10-06): "the distance the finger moves should line up with the
        // number of spaces a hit moves" — one finger-pitch of travel = one step, matching what's actually on
        // screen for THIS lane's own step count, instead of a fixed point distance regardless of N/width.
        let insetL: CGFloat = exactStyle ? 0 : 6, insetR: CGFloat = exactStyle ? 0 : 6
        // SAME FORMULA the Canvas below independently recomputes from `size.width` (which `.frame(width:
        // width)` at the very end of this body pins to this SAME `width` — the two can't disagree) — reused
        // here, at body scope, only for the gesture's rotate-sensitivity below, which has no access to the Canvas's own local `size`.
        let usableOuter = max(1, width - insetL - insetR)
        let groupSize = euclidStepGroupSize(forRate: rate)
        let groupGeo = grouped ? euclidGroupedBoxGeometry(n: n, g: groupSize, usableWidth: usableOuter) : nil
        let boxGeo = euclidBoxGeometry(n: n, usableWidth: usableOuter)
        // STEP-GROUPS (2026-10-14 ferry): one shared step-position list for both the gesture's rotate-
        // sensitivity — `groupGeo` when grouped, else the plain
        // uniform-pitch list, which reduces `rotateStepPt` below to EXACTLY `boxGeo.pitch` (byte-identical
        // for every ungrouped caller, not a special case: with xs[i] = i×pitch, (xs[n-1]-xs[0])/(n-1) = pitch).
        let stepXs: [CGFloat] = groupGeo?.xs ?? (0..<n).map { CGFloat($0) * boxGeo.pitch }
        let rotateStepPt: CGFloat = n > 1 ? (stepXs[n - 1] - stepXs[0]) / CGFloat(n - 1) : boxGeo.pitch
        // the lane's position in its pass at a UI beat: with an active restart chain it is measured from the RHYTHM origin (the engine's own core); with both chains FREE it is the legacy span formula
        let cometRawAt: (Double) -> Double = { b in
            restartChains.map { euclideousLaneCometChainRaw(beat: b, n: n, dir: dir, sub: sub, chains: $0, legacySpanBeats: spanBeats) }
                ?? euclidCometRaw(mTickBeat: b, sub: sub, spanBeats: spanBeats, n: n, dir: dir)
        }
        ZStack {
        TimelineView(.animation(minimumInterval: strip != nil && (running || pulseScale > 0) ? 1.0 / 60.0 : 1.0 / 30.0, paused: !(running || (pulseFeed != nil && pulseLive)))) { tl in   // the strip's playhead glides: 60 fps while it runs (LANE STRIP §2)
            let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            // DIRECTION-AWARE SWEEP: `cometRaw` is the raw tick count mod the direction's real cycle length (n, or
            // 2n under PING-PONG); `cometPos` is its continuous screen position, reversing/bouncing per
            // `euclidCometPos`'s own doc comment. The per-box HIT/REST content (`euclidReadIndex` below) is
            // untouched — only the comet's own visual sweep motion varies by direction.
            // RESTART CHAINS: with an active chain the comet measures from the RHYTHM origin (`euclideousLaneCometChainRaw` — the engine's
            // own core), so it and every flash below agree with the pattern across a restart; with both chains FREE it is the legacy span
            // formula, unchanged.
            let cometRaw = cometRawAt(liveBeat)
            // A lane the grid has MUTED at this beat reads as stopped: no comet, no flashes, the cells dimmed to the page's 42%.
            let mutedNow = mutedAt?(liveBeat) ?? false
            let runningNow = running && !mutedNow
            let cometPos = euclidCometPos(cometRaw, n: n, dir: dir)
            let nD = Double(n)
            // PULSE (ferry 2026-10-20): every strike effect comes from the feed's strikes and the pure functions in Derivations.swift. A strike's tile is the step the engine read at its onset tick (the comet raw
            // at the MUSICAL onset beat, the same function the dot uses); its age is wall time since the onset stamped on the display clock when the event arrived (1.2).
            let pulseOn = pulseFeed != nil
            let nowRef = tl.date.timeIntervalSinceReferenceDate
            let swingA = min(75, max(50, clock.swing)) / 50.0
            let pulseKey = euclideousPulseGeometryKey(n: n, dir: dir, sub: sub, spanBeats: spanBeats, swing: swingA, stepBeats: clock.stepBeats, chains: restartChains)
            let pulseStrikes = pulseFeed?.resolveTiles(lane: pulseLane, key: pulseKey, tileOf: { onset in
                let mb = swingA == 1 ? onset : musicalOf(onset, stepBeats: max(0.03125, clock.stepBeats), a: swingA)
                let raw = restartChains.map { euclideousLaneCometChainRaw(beat: mb, n: n, dir: dir, sub: sub, chains: $0, legacySpanBeats: spanBeats) }
                    ?? euclidCometRaw(mTickBeat: mb, sub: sub, spanBeats: spanBeats, n: n, dir: dir)
                return euclideousPulseTileForOnset(rawAtOnset: raw, n: n, dir: dir)
            }) ?? []
            // LANE STRIP (ferry 2026-10-21): each layer's latest strike per step (the riff's for the chip, the notes' for the key), and the lane's current chip (the hit its riff arrow shows). A muted lane makes no strikes.
            let stripStrikes = (strip != nil && pulseOn && !mutedNow) ? euclideousStripTileStrikes(pulseStrikes, tiles: n, now: nowRef)
                : (riff: [EuclideousStripTileStrike?](repeating: nil, count: n), notes: [EuclideousStripTileStrike?](repeating: nil, count: n))
            // PING-PONG visits each step twice with different notes: the strip shows the sweep the lane is on (the first while it is stopped)
            let stripLeg = strip.map { $0.legIndex(raw: running ? cometRaw : 0) } ?? 0
            let stripCurrentNow: EuclideousStripCurrent? = (strip?.riffPlays == true && running) ? stripCurrent?(liveBeat, tl.date) : nil
            let stripCurrentStep: Int? = stripCurrentNow.flatMap { $0.leg == stripLeg ? $0.step : nil }
            Canvas { ctx, size in
                var buf = [Bool](repeating: false, count: n)
                let cellColour = cellTint ?? tint   // the LIT cells' colour (the comet head below keeps `tint`)
                // HAND-EDITED PATTERN (found 2026-10-12) — mirrors Router.swift's own `runEuclidLine`
                // exactly: a non-nil `customHits` replaces generation entirely (TILT never consulted);
                // ROTATE still applies on top regardless, matching the engine's own unconditional call.
                if let custom = customHits, !custom.isEmpty {
                    for i in 0..<n { buf[i] = i < custom.count ? custom[i] : false }
                } else {
                    // REORDERED 2026-10-11 alongside the real engine (see `euclidTiltPattern`'s own doc
                    // comment): tilt now runs on the UNROTATED pattern, rotation applied to the already-
                    // tilted result — ferry §3.4's own "match the real engine's own emission exactly" still
                    // holds, just against the engine's new (decoupled) order instead of the old one.
                    _ = euclidPatternInto(&buf, pulses: k, steps: n, rotation: 0)
                    if tilt != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: tilt) }
                }
                euclidRotateBuffer(&buf, steps: n, rotation: rotate)
                let w = size.width, midY = size.height / 2
                let insetL: CGFloat = exactStyle ? 0 : 6, insetR: CGFloat = exactStyle ? 0 : 6
                let usable = max(1, w - insetL - insetR)
                func xFor(_ pos: Double) -> CGFloat { insetL + usable * CGFloat(pos / Double(n)) }   // the comet still rides this CONTINUOUS position — independent of the discrete boxes below
                // STEP BOXES: N bounded, gap-separated rounded-rect slots read the step COUNT at a glance — the
                // boxes themselves ARE the grid, with or without anything lit. Gap narrows as N grows so a dense
                // 16-step lane doesn't crush its boxes into nothing — UNLESS `grouped` (2026-10-14 ferry), which
                // uses `euclidGroupedBoxGeometry`'s own fixed 2pt-within/7pt-between gaps instead, the SAME
                // formula the outer rotate-drag sensitivity/footer-accessibility overlay independently recompute
                // from `width` (pinned equal to this Canvas's own `size.width` by the `.frame(width: width)` at
                // the very end of this body) — can't drift apart.
                let localGroupGeo = grouped ? euclidGroupedBoxGeometry(n: n, g: euclidStepGroupSize(forRate: rate), usableWidth: usable) : nil
                let (boxW, boxXs): (CGFloat, [CGFloat]) = {
                    if let g = localGroupGeo { return (g.stepW, g.xs) }
                    let (bw, gp, _) = euclidBoxGeometry(n: n, usableWidth: usable)
                    return (bw, (0..<n).map { CGFloat($0) * (bw + gp) })
                }()
                // "Each step cell is one 44pt-tall rounded rectangle (6pt radius), the same height as the play
                // button and the count box" (2026-10-13 ferry §1, literal) — the cell now fills this bar's
                // whole rendered height (was capped at 30pt with margin above/below) and the corner radius is
                // a flat, un-tapered 6pt (was `min(5, boxW/2.2)`, which shrank at narrow widths). The OLD
                // bottom-corner-only tapering (`hasFooter`) is gone entire — there's no separate footer row
                // below to seam with anymore; the footer BAND (below) is drawn and clipped INSIDE this same
                // cell shape instead.
                let boxH = size.height
                let corner: CGFloat = 6
                func boxRect(_ i: Int) -> CGRect {
                    CGRect(x: insetL + boxXs[i], y: midY - boxH / 2, width: boxW, height: boxH)
                }
                func boxPath(_ rect: CGRect) -> Path {
                    RoundedRectangle(cornerRadius: corner).path(in: rect)
                }
                // LANE STRIP (ferry 2026-10-21): the Euclideous lane card's strip — a riff track over a key row on these same step columns, the playhead in place of the comet. Everything it draws is a
                // pure function of the plan the page built (`EuclideousStripPlan`) and the clock; see `drawEuclideousStrip`.
                if let strip, stripLeg < strip.legs.count {
                    let xs: [CGFloat] = (0..<n).map { insetL + boxXs[$0] }
                    let playhead: EuclideousStripPlayhead? = running ? euclideousStripPlayhead(raw: cometRaw, n: n, dir: dir, xs: xs, columnW: boxW) : nil
                    drawEuclideousStrip(&ctx, EuclideousStripFrameInput(hits: strip.legs[stripLeg].hits, shadowed: strip.shadowed, frames: euclideousStripLayout(xs: xs, columnW: boxW), tint: tint, playhead: playhead,
                                                                         areaMinX: insetL, areaMaxX: insetL + usable, current: stripCurrentStep,
                                                                         riffStrikes: stripStrikes.riff, noteStrikes: stripStrikes.notes, scale: pulseScale, reduceMotion: reduceMotion))
                    return
                }
                // BOX CONTENT IS DIRECTION-INDEPENDENT — box `i` always shows `buf[i]`, the raw pattern buffer at
                // that screen position, full stop. The age/flare timing below is keyed on screen position `i`
                // directly; only the comet's own motion (via `cometRaw`/`cometPos`, already direction-aware)
                // varies by DIRECTION.
                for i in 0..<n {
                    let rawHit = invert ? !buf[i] : buf[i]
                    // MISS STYLE (ferry §3.2): draw as if "hit" means "sounding" — the inverted steps get the
                    // existing rich hit treatment below unchanged; the raw Euclid hits (now silent) fall to the
                    // rest branch, which draws them outlined instead of dim when `missStyle` is set.
                    let hit = missStyle ? !rawHit : rawHit
                    let rect = boxRect(i)
                    let box = boxPath(rect)
                    if hit {
                        // STOPPED: `running` false (either the HOST transport, or THIS LANE's own PLAY/STOP) means
                        // the TimelineView above is PAUSED, so `phase` is frozen at whatever it was the instant
                        // playback stopped, not a meaningful "time since the comet passed." Drawing the age/
                        // recede/burst flare off a frozen age would leave some hit box stuck mid-flash forever. A
                        // stopped lane shows every hit at one steady, unflared brightness instead.
                        if runningNow {
                            // steps since the comet passed this node (0 = just now), wrapped positive every lap —
                            // direction-aware: FWD unchanged; BKW mirrors it (the comet visits box i when
                            // cometRaw = n−i); PING-PONG visits box i TWICE per lap (ascending at cometRaw=i,
                            // descending at cometRaw=2n−i) — age takes whichever visit was more recent.
                            let age: Double
                            switch dir {
                            case .fwd:
                                let raw = (cometRaw - Double(i)).truncatingRemainder(dividingBy: nD)
                                age = raw < 0 ? raw + nD : raw
                            case .bkw:
                                let raw = (cometRaw + Double(i)).truncatingRemainder(dividingBy: nD)
                                age = raw < 0 ? raw + nD : raw
                            case .pingpong:
                                let cycleLen = 2 * nD
                                func wrap(_ v: Double) -> Double { let r = v.truncatingRemainder(dividingBy: cycleLen); return r < 0 ? r + cycleLen : r }
                                age = min(wrap(cometRaw - Double(i)), wrap(cometRaw - (cycleLen - Double(i))))
                            }
                            let recede = max(0, 1 - age / euclideousFlareAfterglowSteps)     // the lingering afterglow (unchanged window — now a shared constant, so the Fourfold output rings fade with it)
                            // DRAMATIC HIT: a short, sharp BURST window layered on top of the lingering afterglow:
                            // the box's glow swells, a hot white flash core blooms inside it, and a shockwave
                            // OUTLINE expands outward — all decay much faster than `recede` so the strike itself
                            // reads as an impact, not just a brighter box.
                            let burst = max(0, 1 - age / euclideousFlareBurstSteps)
                            do {
                                // a top-lit gradient fill — a flat fill read as a dead swatch; light-to-dark top-to-
                                // bottom gives each box a glassy, lit-from-above quality, brightening further on its
                                // own burst.
                                ctx.drawLayer { layer in
                                    layer.addFilter(.shadow(color: cellColour.opacity(min(1, 0.55 + burst)), radius: 5 + 14 * burst + 4 * recede))
                                    layer.fill(box, with: .linearGradient(Gradient(colors: [cellColour.opacity(min(1, 0.95 + 0.3 * burst) * cellFade), cellColour.opacity((0.55 + 0.25 * recede) * cellFade)]),
                                                                           startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                                }
                                ctx.stroke(box, with: .color(.white.opacity(0.18 + 0.5 * burst)), lineWidth: 1)
                                if burst > 0.04 {   // the hot flash core — a bright inset band, not a second shape
                                    let core = Path(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.3), cornerRadius: corner * 0.6)
                                    ctx.drawLayer { layer in
                                        layer.addFilter(.shadow(color: .white.opacity(burst), radius: 6 * burst))
                                        layer.fill(core, with: .color(.white.opacity(burst * 0.9)))
                                    }
                                }
                                if burst > 0.06 {   // the shockwave — an expanding box outline, reads as an impact not just a flash
                                    let grow = 11 * (1 - burst)
                                    let ring = Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow), cornerRadius: corner + grow * 0.4)
                                    ctx.stroke(ring, with: .color(cellColour.opacity(0.4 * burst)), lineWidth: 1.5)
                                }
                            }
                        } else if exactStyle {
                            // 2026-10-13 ferry, literal: "Hits are LANE-100" — the resting (stopped) hit cell,
                            // flat and full-strength, no dimming/border (the running case above, with its own
                            // gradient/burst/flash/shockwave, is untouched — nothing in this ferry addresses it).
                            ctx.fill(box, with: .color(cellColour.opacity(cellFade)))
                        } else {
                            ctx.fill(box, with: .color(cellColour.opacity(0.55 * cellFade)))
                            ctx.stroke(box, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        }
                    } else if missStyle {
                        // MISS STYLE (ferry §3.2): this box is one of the ORIGINAL Euclid hits, now silent — a
                        // 1.5pt lane-coloured outline with NO fill at all, so the original pattern stays legible
                        // as outlines while the filled (sounding) cells above show what actually plays.
                        ctx.stroke(box, with: .color(cellColour), lineWidth: 1.5)
                    } else if exactStyle {
                        // 2026-10-13 ferry, literal: "misses are #2c2f36" — a flat fill, no border.
                        ctx.fill(box, with: .color(Color(hex: 0x2C2F36)))
                    } else {
                        // REST: every box's RECT is mathematically fixed per step index regardless of hit/rest, so
                        // the grid itself never relocates — only which boxes are lit does. A plainly visible
                        // FILLED + bordered box (same shape family as a hit, just dim), not a hollow ring, so the
                        // fixed slot grid stays legible regardless of which subset is currently lit.
                        ctx.fill(box, with: .color(.white.opacity(0.09)))
                        ctx.stroke(box, with: .color(.white.opacity(0.16)), lineWidth: 1)
                    }
                }
                // THE COMET — a soft blurred trail + a glowing head, riding OVER the box row. MOTION reverses for
                // BKW and bounces for PING-PONG — `hx` tracks `cometPos`'s own direction-aware sweep; the TRAIL
                // (which side of the head it extends from — always "behind" the direction of travel) follows
                // `movingRight`, which flips for BKW and switches mid-lap for PING-PONG. STOPPED: not drawn at
                // all — a paused TimelineView freezes `cometPos`, so without this guard the comet would sit
                // motionless at its last live position instead of disappearing.
                if runningNow {
                    let hx = xFor(cometPos)
                    let movingRight: Bool
                    switch dir {
                    case .fwd: movingRight = true
                    case .bkw: movingRight = false
                    case .pingpong: movingRight = cometRaw < nD
                    }
                    let tx = movingRight ? max(insetL, hx - 22) : min(insetL + usable, hx + 22)
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 3))
                        var trail = Path()
                        trail.move(to: CGPoint(x: hx, y: midY)); trail.addLine(to: CGPoint(x: tx, y: midY))
                        layer.stroke(trail, with: .linearGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0)]),
                                                                   startPoint: CGPoint(x: hx, y: midY), endPoint: CGPoint(x: tx, y: midY)),
                                     lineWidth: 5)
                    }
                    let dotD: CGFloat = 10
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: tint, radius: 9))
                        layer.fill(Path(ellipseIn: CGRect(x: hx - dotD / 2, y: midY - dotD / 2, width: dotD, height: dotD)), with: .color(tint))
                    }
                }
            }
            .opacity(mutedNow && !suppressMuteDim ? EuclideousLaneDimStyle.opacity : 1)   // LANES GRID: a muted lane dims to the page's 42% (and, since LANE SOLO, eases over 0.15 s both ways)
            .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: mutedNow && !suppressMuteDim)
            .allowsHitTesting(false)
        }
        // GESTURES: 1-finger drag left/right = Δrotate, up/down = Δhits (this lane); 2-finger drag does the same
        // but to EVERY lane (the caller's own `onAllRotateDelta`/`onAllHitsDelta`). PINCH = ΔSTEPS is the only way
        // to change STEPS from this bar. `rotateStepPt` (box-pitch-matched) governs the horizontal axis only.
        EuclidGesturePad(onRotateDelta: onRotateDelta, onHitsDelta: onHitsDelta, onStepsDelta: onStepsDelta,
                         onAllRotateDelta: onAllRotateDelta, onAllHitsDelta: onAllHitsDelta, onDragState: onDragState,
                         rotateStepPt: rotateStepPt)
            .padding(.horizontal, 14)
        // THE STRIP'S VOICEOVER (LANE STRIP ferry §6, replacing the per-step footer labels and the NOTES tab's "the notes play on hits…" value): ONE element, its value each hit in step order from the pass the
        // footers show (built per body by the caller), then — read at this body's evaluation — "on step N" while the lane plays and "silent at this step" while the LANES grid mutes it.
        if let strip {
            let beatNow = clock.anchor + Date().timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            let cl = euclidCycleLen(dir, n: n)
            let onStep: Int? = running ? euclidReadIndex(posMod(Int(cometRawAt(beatNow).rounded(.down)), cl), n: n, dir: dir) + 1 : nil
            Color.clear
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lane \(pulseLane + 1) step strip")
                .accessibilityValue(euclideousAppendSilencedBySolo(euclideousStripAppendLive(strip.hitsPhrase, onStep: onStep, muted: mutedAt?(beatNow) ?? false), silenced: soloSilencedWords))
        }
        }
        // LEFTOVER RULE (2026-10-14 ferry, "Step groups on the lane step row" §3): a 2pt bar, 1pt corner
        // radius, LANE-100, sitting 2pt below the bottom of the step cells — drawn OUTSIDE the Canvas above
        // (which, for `exactStyle` callers, has its own box fill the Canvas's FULL height, leaving no room
        // inside it for anything below the boxes) as a plain overlay anchored to this whole bar's own
        // bottom-left corner, then nudged right/down into position. Shown only when `grouped` AND the step
        // count isn't an exact multiple of the group size ("counts that divide evenly get no rule") — reads
        // `groupGeo` (computed once at body scope, the SAME values the Canvas's own `localGroupGeo` re-derives
        // from `size.width`, which `.frame(width: width)` below pins to this identical `width`). Depends on
        // nothing but `n`/`grouped`/`rate` — never hits/play state/the riff — and never responds to touch
        // (layered in an `.overlay`, outside any gesture/hit-testing path; nothing here calls `.contentShape`
        // or attaches a gesture).
        .overlay(alignment: .bottomLeading) {
            if let g = groupGeo, let rx = g.ruleX, let rw = g.ruleW {
                RoundedRectangle(cornerRadius: 1).fill(tint)
                    .frame(width: rw, height: 2)
                    .offset(x: insetL + rx, y: 4)
                    .allowsHitTesting(false)
            }
        }
        // PIN THE REAL RENDER WIDTH TO THE `width` PARAMETER (found 2026-10-13, chasing "the lane footer
        // cells don't line up with the step boxes above them"): nothing below this struct's own body EVER
        // constrained its width explicitly — the Canvas's `size.width` (what it actually draws boxes
        // against) was left to whatever `EuclidLaneBox`'s surrounding HStack happened to allocate the lone
        // flexible child, which SwiftUI doesn't guarantee matches the HAND-COMPUTED `width` parameter
        // (`width − 64 − badgeReserve`) to the pixel — especially once `stepCountBadge`'s own AnyView
        // content (an arbitrary view, not a bare fixed-width rect) sits as a third HStack sibling. The
        // Canvas's own box math was always internally self-consistent (it reads `size.width` for
        // everything), so this bar never looked broken on its own — but `laneFooter` (EuclideousPage.swift)
        // computes its OWN, SEPARATE footer-cell positions purely from the `width` PARAMETER (it has no
        // access to this Canvas's real `size.width`), so any drift between the two was invisible to every
        // static read and every test, only showing up as a real, on-device seam between the footer and the
        // step boxes it's meant to sit under. Forcing `.frame(width: width)` here makes `size.width` and
        // `width` the SAME number by construction — not just by a formula that's supposed to agree with
        // whatever the HStack decides.
        .frame(width: width)
    }
}

/// A UIKit pan+pinch bridge — SwiftUI's own `DragGesture` doesn't distinguish touch COUNT, only
/// position, and the EUCLID bar needs a genuine 1-vs-2-finger distinction (1 finger = this lane,
/// 2 fingers = every lane). Touch count is LATCHED at `.began`, not re-read every `.changed`, so
/// a finger lifting or landing mid-drag can't flip which mode the drag is in partway through.
/// PINCH (spread = add steps, pinch-in = remove) runs on the SAME view as a second recognizer —
/// a genuine pinch (fingers moving apart/together, centroid roughly static) and a 2-finger pan
/// (both fingers moving together) measure near-orthogonal things, so they coexist without
/// fighting in practice; the delegate below just lifts UIKit's own default "one gesture at a
/// time per view" restriction so neither silently blocks the other.
// NOT private (Paul 2026-10-06): the per-button gesture pads on Euclideous's new 1/3-width square
// buttons (EuclideousPage.swift) construct this SAME component directly, each wired to a different
// X/Y mapping — "share the component, don't duplicate it" extended to a second caller.
struct EuclidGesturePad: UIViewRepresentable {
    let onRotateDelta: (Int) -> Void        // 1-finger horizontal — Δrotate, this lane
    let onHitsDelta: (Int) -> Void          // 1-finger vertical — Δhits, this lane
    let onStepsDelta: (Int) -> Void         // pinch — Δsteps, this lane (shared with the +/- tap glyphs)
    let onAllRotateDelta: (Int) -> Void     // 2-finger horizontal — Δrotate, every lane
    let onAllHitsDelta: (Int) -> Void       // 2-finger vertical — Δhits, every lane
    // (location, isAllRows) — location is WINDOW-space (`location(in: view.window)`), non-nil while a touch is
    // down, nil the instant it lifts/cancels. Reported on EVERY `.changed` tick too, not just begin/end, so a
    // HUD tracking the finger moves continuously, not just at the start of the gesture.
    let onDragState: (CGPoint?, Bool) -> Void
    // ROTATE SENSITIVITY (Paul 2026-10-06): "the distance the finger moves should line up with the number of
    // spaces a hit moves" — the HORIZONTAL axis's own points-per-step, computed by the caller from this
    // lane's real box pitch (`euclidBoxGeometry`), so a drag of exactly one box's width moves rotate by
    // exactly one step. The VERTICAL (hits) axis is unaffected — it keeps the fixed `euclidDragStepPt`.
    let rotateStepPt: CGFloat
    func makeUIView(context: Context) -> UIView {
        // RAW TOUCH TRACKING — UIPanGestureRecognizer/UIPinchGestureRecognizer only transition to .began once a
        // touch has moved past UIKit's own recognition slop, so driving the HUD from them alone leaves a dead
        // zone right after contact (and a plain tap that never moves enough never shows anything). TouchView's
        // raw touchesBegan/Moved/Ended bridge that gap — see its own doc comment below.
        let v = TouchView(); v.backgroundColor = .clear; v.isOpaque = false
        v.coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false   // let TouchView keep receiving touch events through the whole gesture, not just up to the moment the recognizer takes over
        v.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false
        v.addGestureRecognizer(pinch)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.owner = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    /// Reports raw touch contact straight to the Coordinator, independent of whatever the pan/pinch recognizers
    /// decide — see `makeUIView`'s own comment for why this exists. Tracks the active touch SET (not just one) so
    /// a 2-finger gesture doesn't look "lifted" the instant the FIRST of the two fingers comes up; `allRows`
    /// (≥2 touches) is a plain snapshot of that count, not a latch — it's only used for this early, pre-
    /// recognition HUD label, and corrects itself within milliseconds once the real recognizer's own LATCHED
    /// `twoFinger` (handlePan) takes over reporting.
    private final class TouchView: UIView {
        weak var coordinator: Coordinator?
        private var active: Set<UITouch> = []
        private func report() {
            guard let t = active.first else { return }
            coordinator?.handleRawTouch(t.location(in: window), active.count >= 2)
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event); active.formUnion(touches); report()
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event); report()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event); active.subtract(touches)
            active.isEmpty ? coordinator?.handleRawTouch(nil, false) : report()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event); active.subtract(touches)
            active.isEmpty ? coordinator?.handleRawTouch(nil, false) : report()
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: EuclidGesturePad
        func handleRawTouch(_ point: CGPoint?, _ allRows: Bool) { owner.onDragState(point, allRows) }
        private var twoFinger = false
        private var appliedX = 0, appliedY = 0
        private var appliedPinchSteps = 0
        private var pinchStartDist: CGFloat = 0
        private let stepPt = euclidDragStepPt
        init(_ o: EuclidGesturePad) { owner = o }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                twoFinger = g.numberOfTouches >= 2
                appliedX = 0; appliedY = 0
                owner.onDragState(g.location(in: g.view?.window), twoFinger)
            case .changed:
                let t = g.translation(in: g.view)
                let stepsX = Int((t.x / owner.rotateStepPt).rounded())   // box-pitch-matched — Paul 2026-10-06
                let stepsY = Int((-t.y / stepPt).rounded())   // screen-down is +y; dragging UP should INCREASE
                if stepsX != appliedX {
                    let d = stepsX - appliedX
                    twoFinger ? owner.onAllRotateDelta(d) : owner.onRotateDelta(d)
                    appliedX = stepsX
                }
                if stepsY != appliedY {
                    let d = stepsY - appliedY
                    twoFinger ? owner.onAllHitsDelta(d) : owner.onHitsDelta(d)
                    appliedY = stepsY
                }
                owner.onDragState(g.location(in: g.view?.window), twoFinger)   // every tick — the HUD tracks the finger live, not just at touch-down
            case .ended, .cancelled, .failed:
                owner.onDragState(nil, twoFinger)
            default: break
            }
        }
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                appliedPinchSteps = 0
                pinchStartDist = pinchTouchDistance(g)
                owner.onDragState(g.location(in: g.view?.window), false)   // pinch is always scoped to this lane — no "all lanes" steps mode; position set ONCE, not re-tracked below
            case .changed:
                let delta = pinchStartDist * (g.scale - 1)
                let steps = Int((delta / stepPt).rounded())
                if steps != appliedPinchSteps {
                    owner.onStepsDelta(steps - appliedPinchSteps)
                    appliedPinchSteps = steps
                }
            case .ended, .cancelled, .failed:
                owner.onDragState(nil, false)
            default: break
            }
        }
        private func pinchTouchDistance(_ g: UIPinchGestureRecognizer) -> CGFloat {
            // UIKit guarantees 2 touches by the time .began fires, so this guard shouldn't trigger in practice —
            // but IF it ever did, a non-zero guess here would silently compute a WRONG step delta. 0 is the one
            // value that's always SAFE: it's only ever read as `pinchStartDist` at .began, and
            // `delta = pinchStartDist * (scale - 1)` is then 0 for the gesture's entire lifetime regardless of
            // scale — a clean no-op rather than a guessed-but-wrong one.
            guard g.numberOfTouches >= 2 else { return 0 }
            let p0 = g.location(ofTouch: 0, in: g.view), p1 = g.location(ofTouch: 1, in: g.view)
            return hypot(p1.x - p0.x, p1.y - p0.y)
        }
    }
}

/// One hit/miss beacon dot — extracted from `ProcessorBox`'s `euclidBeaconDot` cluster (Paul
/// 2026-10-05). `isReady` replaces the bitmask read (the old `euclidBeaconCanPlay`) — the
/// caller does that bit-math once (it owns the per-cell `euclidLineReady` bit-layout convention,
/// Router.swift) and hands over a plain bool, decoupling this component from that encoding.
/// ACCURATE BY CONSTRUCTION: reuses the exact same pure functions the real render path uses for
/// its own per-tick hit decision (`euclidReadIndex`/`euclidCycleLen`/`euclidPatternInto`) via the
/// same continuous tick-count the comet bar drives its own sweep from (`euclidCometRaw`).
struct EuclidBeacon: View {
    let line: EuclidLine
    let isMiss: Bool
    let accent: Color
    let clock: EuclidLiveClock
    let rate: ArpRate
    let spanN: Int
    let isReady: Bool

    var body: some View {
        let n = max(2, min(16, line.steps))
        let k = max(0, min(n, line.pulses))
        let dir = line.directionResolved
        let sub = max(0.03125, rate.beats)
        let spanBeats = spanN > 0 ? spanLadderBeats(spanN, S: clock.stepBeats, row: Double(clock.cols) * clock.stepBeats) : 0
        let running = clock.playing && line.enabledResolved
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running || !isReady)) { tl in
            beaconCircle(flash: beaconFlash(tl.date, n: n, k: k, rotate: line.rotate, dir: dir, sub: sub, spanBeats: spanBeats, running: running))
        }
    }
    /// Pure scalar half — pulled out so the `TimelineView` closure above stays a single simple
    /// call (Swift's result-builder type inference chokes on a longer inline version).
    private func beaconFlash(_ date: Date, n: Int, k: Int, rotate: Int, dir: EuclidDir, sub: Double, spanBeats: Double, running: Bool) -> Double {
        guard running && isReady else { return 0 }
        let liveBeat = clock.anchor + date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
        let cometRaw = euclidCometRaw(mTickBeat: liveBeat, sub: sub, spanBeats: spanBeats, n: n, dir: dir)
        var buf = [Bool](repeating: false, count: n)
        _ = euclidPatternInto(&buf, pulses: k, steps: n, rotation: rotate)
        let rawTick = Int(cometRaw.rounded(.down))
        let isHitTick = buf[euclidReadIndex(rawTick, n: n, dir: dir)]
        guard isMiss ? !isHitTick : isHitTick else { return 0 }
        let age = cometRaw - Double(rawTick)                 // 0..<1, how far into the current tick we are
        return max(0, 1 - age / 0.4)                         // a short, sharp pulse — not a held glow
    }
    private func beaconCircle(flash: Double) -> some View {
        Circle().fill(accent.opacity(0.25 + 0.75 * flash))
            .frame(width: 6, height: 6)
            .shadow(color: accent.opacity(flash), radius: 3 * flash)
    }
}
