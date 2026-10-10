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
}

/// ~18pt per step, vertical (hits) axis — a first-pass sensitivity (tunable): deliberately coarser than
/// NumPair's own 14pt/step scrub, since this bar is small and a finger resting on it covers a fair chunk of
/// it. The HORIZONTAL (rotate/offset) axis instead uses `euclidBoxGeometry`'s own pitch (below) — Paul
/// 2026-10-06: "the distance the finger moves should line up with the number of spaces a hit moves."
let euclidDragStepPt: CGFloat = 18

/// Shared step-box geometry — the SAME formula `EuclidCometBar`'s own Canvas drawing uses for box width/
/// gap, so the gesture pad's rotate-drag sensitivity (how many points of finger movement = one step) can
/// never compute a DIFFERENT box pitch than what's actually on screen for that lane. One function, two
/// callers, by construction can't drift apart (the RATCHET/DEST class of bug this codebase keeps guarding
/// against — a widget and the thing it controls silently disagreeing about the same quantity).
func euclidBoxGeometry(n: Int, usableWidth: CGFloat) -> (boxW: CGFloat, gap: CGFloat, pitch: CGFloat) {
    let gap: CGFloat = n <= 8 ? 4 : (n <= 12 ? 3 : 2)
    let boxW = max(3, (usableWidth - gap * CGFloat(n - 1)) / CGFloat(n))
    return (boxW, gap, boxW + gap)
}

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
    // TRAILING CONTENT (Paul 2026-10-06, EUCLIDEOUS): an optional extra row drawn INSIDE this box's own
    // border/background, directly below the play+comet row — so a caller's own per-lane controls (e.g.
    // Euclideous's gesture-tab selector) read as "part of the lane control", not a separate floating box
    // underneath it. nil (every existing BUILD-page call site) ⇒ byte-identical to before. Type-erased
    // (not generic) so this struct's own type stays concrete/unchanged for its existing callers.
    var trailingContent: AnyView? = nil
    var trailingHeight: CGFloat = 0   // the exact height the caller's trailingContent needs — lets the comet row claim the rest, rather than guessing
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

    var body: some View {
        let on = line.enabledResolved
        // NO GAP (Paul 2026-10-06): "the buttons that toggle x/y [to] be directly under the boxes on the lane
        // with no gap or padding" — the VStack spacing between the step-box row and trailingContent (the
        // gesture-tab row) is 0; `reserve` drops its own +6 for that now-removed gap to match exactly.
        let reserve: CGFloat = trailingContent == nil ? 0 : trailingHeight
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: on ? "play.fill" : "stop.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(on ? accent : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleEnabled() }   // its own tap wins over the cell's outer select-tap below, at this exact spot — standard SwiftUI nested-gesture precedence
                // WIDTH (Paul 2026-10-06): the comet bar's own real rendered width, derived exactly from this
                // box's layout (6pt padding ×2 + the 44pt play button + 8pt HStack spacing = 64pt, PLUS — if a
                // badge is present — its own width and the SECOND inter-item gap before it, fixed 2026-10-10:
                // the original formula silently omitted both whenever `stepCountBadge` was non-nil, so the
                // comet bar's own Canvas was told it had more width than the HStack actually gave it) — NOT
                // measured via GeometryReader — so `EuclidCometBar` can compute its box pitch (for the
                // rotate-drag sensitivity) from the SAME width it will actually render at, no approximation.
                let badgeReserve: CGFloat = stepCountBadge == nil ? 0 : (8 + stepCountBadgeWidth)
                EuclidCometBar(pulses: line.pulses, steps: line.steps, rotate: line.rotate, invert: line.invert, dir: line.directionResolved,
                               rate: rate, spanN: spanN, tilt: line.tiltResolved, tint: accent, lanePlaying: on, clock: clock, width: max(1, width - 64 - badgeReserve),
                               onRotateDelta: onRotateDelta, onHitsDelta: onHitsDelta, onStepsDelta: onStepsDelta,
                               onAllRotateDelta: onAllRotateDelta, onAllHitsDelta: onAllHitsDelta, onDragState: onDragState)
                    .frame(height: max(20, height - 12 - reserve))   // 12 = the 6pt top+bottom padding below — matches the original 44=56-12 derivation, generalized
                if let stepCountBadge { stepCountBadge }
            }
            if let trailingContent { trailingContent }
        }
        .padding(6)
        .frame(width: width, height: height)   // EXPLICIT width/height — the stroke/background below can never bleed past it
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.07 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? accent.opacity(0.5) : Color.clear, lineWidth: 1.5))
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
    let tint: Color
    let lanePlaying: Bool
    let clock: EuclidLiveClock
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
        let sub = max(0.03125, rate.beats)
        let spanBeats = spanN > 0 ? spanLadderBeats(spanN, S: clock.stepBeats, row: Double(clock.cols) * clock.stepBeats) : 0
        // PER-LANE PLAY/STOP: a SECOND, independent gate alongside `clock.playing` (the HOST transport). `running`
        // is true only when BOTH the transport is playing AND this specific lane's own PLAY/STOP is engaged; a
        // stopped lane freezes/hides its comet exactly like a stopped transport does, regardless of whether OTHER
        // lanes (or the transport itself) are still running.
        let running = clock.playing && lanePlaying
        // ROTATE-DRAG SENSITIVITY (Paul 2026-10-06): "the distance the finger moves should line up with the
        // number of spaces a hit moves" — one finger-pitch of travel = one step, matching what's actually on
        // screen for THIS lane's own step count, instead of a fixed point distance regardless of N/width.
        let insetL: CGFloat = 6, insetR: CGFloat = 6
        let rotateStepPt = euclidBoxGeometry(n: n, usableWidth: max(1, width - insetL - insetR)).pitch
        ZStack {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { tl in
            let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            // DIRECTION-AWARE SWEEP: `cometRaw` is the raw tick count mod the direction's real cycle length (n, or
            // 2n under PING-PONG); `cometPos` is its continuous screen position, reversing/bouncing per
            // `euclidCometPos`'s own doc comment. The per-box HIT/REST content (`euclidReadIndex` below) is
            // untouched — only the comet's own visual sweep motion varies by direction.
            let cometRaw = euclidCometRaw(mTickBeat: liveBeat, sub: sub, spanBeats: spanBeats, n: n, dir: dir)
            let cometPos = euclidCometPos(cometRaw, n: n, dir: dir)
            let nD = Double(n)
            Canvas { ctx, size in
                var buf = [Bool](repeating: false, count: n)
                _ = euclidPatternInto(&buf, pulses: k, steps: n, rotation: rotate)
                if tilt != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: tilt) }   // ferry §3.4 — match the real engine's own emission exactly
                let w = size.width, midY = size.height / 2
                let insetL: CGFloat = 6, insetR: CGFloat = 6
                let usable = max(1, w - insetL - insetR)
                func xFor(_ pos: Double) -> CGFloat { insetL + usable * CGFloat(pos / Double(n)) }   // the comet still rides this CONTINUOUS position — independent of the discrete boxes below
                // STEP BOXES: N bounded, gap-separated rounded-rect slots read the step COUNT at a glance — the
                // boxes themselves ARE the grid, with or without anything lit. Gap narrows as N grows so a dense
                // 16-step lane doesn't crush its boxes into nothing; corner radius is capped relative to box width
                // for the same reason at the thin end.
                let (boxW, gap, _) = euclidBoxGeometry(n: n, usableWidth: usable)   // the SAME shared formula the outer rotate-drag sensitivity uses — can't drift apart
                let boxH = min(30, size.height - 6)
                let corner = min(5, boxW / 2.2)
                func boxRect(_ i: Int) -> CGRect {
                    CGRect(x: insetL + CGFloat(i) * (boxW + gap), y: midY - boxH / 2, width: boxW, height: boxH)
                }
                // BOX CONTENT IS DIRECTION-INDEPENDENT — box `i` always shows `buf[i]`, the raw pattern buffer at
                // that screen position, full stop. The age/flare timing below is keyed on screen position `i`
                // directly; only the comet's own motion (via `cometRaw`/`cometPos`, already direction-aware)
                // varies by DIRECTION.
                for i in 0..<n {
                    let hit = invert ? !buf[i] : buf[i]
                    let rect = boxRect(i)
                    let box = Path(roundedRect: rect, cornerRadius: corner)
                    if hit {
                        // STOPPED: `running` false (either the HOST transport, or THIS LANE's own PLAY/STOP) means
                        // the TimelineView above is PAUSED, so `phase` is frozen at whatever it was the instant
                        // playback stopped, not a meaningful "time since the comet passed." Drawing the age/
                        // recede/burst flare off a frozen age would leave some hit box stuck mid-flash forever. A
                        // stopped lane shows every hit at one steady, unflared brightness instead.
                        if running {
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
                            let recede = max(0, 1 - age / 1.5)     // the lingering afterglow (unchanged window)
                            // DRAMATIC HIT: a short, sharp BURST window layered on top of the lingering afterglow:
                            // the box's glow swells, a hot white flash core blooms inside it, and a shockwave
                            // OUTLINE expands outward — all decay much faster than `recede` so the strike itself
                            // reads as an impact, not just a brighter box.
                            let burst = max(0, 1 - age / 0.35)
                            // a top-lit gradient fill — a flat fill read as a dead swatch; light-to-dark top-to-
                            // bottom gives each box a glassy, lit-from-above quality, brightening further on its
                            // own burst.
                            ctx.drawLayer { layer in
                                layer.addFilter(.shadow(color: tint.opacity(min(1, 0.55 + burst)), radius: 5 + 14 * burst + 4 * recede))
                                layer.fill(box, with: .linearGradient(Gradient(colors: [tint.opacity(min(1, 0.95 + 0.3 * burst)), tint.opacity(0.55 + 0.25 * recede)]),
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
                                ctx.stroke(ring, with: .color(tint.opacity(0.4 * burst)), lineWidth: 1.5)
                            }
                        } else {
                            ctx.fill(box, with: .color(tint.opacity(0.55)))
                            ctx.stroke(box, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        }
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
                if running {
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
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: tint, radius: 9))
                        layer.fill(Path(ellipseIn: CGRect(x: hx - 5, y: midY - 5, width: 10, height: 10)), with: .color(tint))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        // GESTURES: 1-finger drag left/right = Δrotate, up/down = Δhits (this lane); 2-finger drag does the same
        // but to EVERY lane (the caller's own `onAllRotateDelta`/`onAllHitsDelta`). PINCH = ΔSTEPS is the only way
        // to change STEPS from this bar. `rotateStepPt` (box-pitch-matched) governs the horizontal axis only.
        EuclidGesturePad(onRotateDelta: onRotateDelta, onHitsDelta: onHitsDelta, onStepsDelta: onStepsDelta,
                         onAllRotateDelta: onAllRotateDelta, onAllHitsDelta: onAllHitsDelta, onDragState: onDragState,
                         rotateStepPt: rotateStepPt)
            .padding(.horizontal, 14)
        }
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
