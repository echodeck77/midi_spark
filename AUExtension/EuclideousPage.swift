//  EuclideousPage.swift
//  MidiSpark — EUCLIDEOUS (Paul 2026-10-05): a standalone, playable 4-lane EUCLID instrument.
//  Reuses the EXACT lane box/comet bar/gesture pad ProcessorBox's own EUCLID editor uses
//  (EuclidLaneUI.swift), sized generously to fill the screen rather than squeezed into a small
//  inline processor panel — "four Euclid lanes in the centre of the screen... a playable,
//  grabbable instrument." Presented as a plain overlay (DiagView's root ZStack), the same
//  mechanism CogPage uses (engine never stops), but NOT CogPage's small bounded-card sizing.
//  Foundation/SwiftUI/UIKit-only, same seam as every other GridUI/BuildPage file.
//
//  PAGE REWORK (Paul 2026-10-07, ratified spec `Docs/SPEC-euclideous-rework.md` + mockup
//  `Docs/euclideous-rework-mockup-2026-10-07.html`): the riff editor moved onto the page itself
//  (fixed 8 steps, no popup); new GLOBAL reset-span/main-out/key+scale/source-mode controls;
//  the old IN A/B/C/D selector is gone (MIDI mode now reads receivers 1 and 4 behind the
//  scenes — see BuildSceneLogic.swift/SnapshotBuilder.swift); each lane gained PATTERN/RIFF/MASK
//  tabs under its XY pads; a brand-new per-lane EUCLID MASK (pattern/transport only — its
//  actual effect is explicitly deferred, §4 of the spec); lane boxes are now square; hit/miss
//  beacons are removed.
//
//  RESET SPAN (Paul 2026-10-08, direct follow-up): reset span is a real engine feature — it
//  re-anchors every lane's own K/N/rotate pattern AND the riff's own advance ordinal every N
//  bars (Router.swift, `runEuclidLine`'s span override), including a hard reset of DRUNK's walk.
//
//  FERRY — riff control, riff display, portrait + landscape (Paul 2026-10-08, rulings, supersedes
//  the single-row riff + note-name display from the entry above): (1) the riff grid is BACK to the
//  original 8-column × 8-rank MATRIX (tap to set a step's rank, tap the same cell again to clear to
//  rest), neutral-coloured cells, not lane-coloured — the single-row level-bar design and its
//  rank/note-name readout are GONE entirely, not relocated. (2) the whole page is now genuinely
//  orientation-aware: PORTRAIT stacks header → 2×2 lane grid → riff grid; LANDSCAPE puts the lane
//  grid on the left and the riff grid on the right, filling the height below a shared header — both
//  computed fresh from the real view bounds on every size change, no fixed widths/heights. Lane
//  boxes stay square in both; XY pads and riff cells have protected minimum sizes that spacing and
//  text shrink around, never the reverse. The HITS/OFFS pad's old verbose face text ("N HITS OUT OF
//  M") truncated under pressure — replaced with a compact "K/N · ±R" format, matching the format
//  VEL/GATE already used and the ratified mockup's own literal example string.

import SwiftUI
import UIKit

// EUCLIDEOUS INVERT (euclideousInvertLine/euclideousEnsureMissDefaults) and the NOTE/OCTAVE cycle
// (euclideousNoteSelCycle/euclideousStepNoteSel) live in Derivations.swift (Paul 2026-10-05) —
// Foundation-only, so they reach the macOS unit-test target; this file only CALLS them. (The rate
// stepper, euclideousNextRate, was REMOVED 2026-10-06 — superseded by ratePopupCard below.)

// The 4 two-axis gesture pads (EuclideousGestureTab/EuclideousXYAxis/EuclideousXYPad/
// EuclideousPadFramePreferenceKey/EuclideousPadValues et al.) that used to live here — HITS/OFFSET
// sharing one pad, OFFSET/STEPS another, GATE/VELOCITY a third, plus NOTE/OCT or SHIFT/OCT — were
// REMOVED WHOLESALE 2026-10-12 (usability ferry), replaced by six independent single-axis sliders
// (`EuclideousSliderField`/`EuclideousSlider`, defined further below, right beside
// `EuclideousPage.sliderRow` which lays them out — 3 vertical on the left, 3 horizontal on the right,
// per the same-day rearrangement). The ferry's own Engineering section asked for this literally: "delete
// the XY pad view code and its gesture recognisers. Leave no dead code paths."

/// The KEY tab's own on-screen frame (Paul 2026-10-12, second same-day ferry) — lets the key picker
/// anchor itself near the tab that opened it (the melody pop-up's own `EuclideousStripFramePreferenceKey`
/// solved this same "a view learns its own frame" need; that pop-up — and its preference key — is retired
/// 2026-10-13, this one stands alone now, a single rect, not a dictionary).
struct EuclideousRiffTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let v = nextValue() { value = v }
    }
}

/// PER-LANE RESET (2026-10-14 ferry §3) — a DICTIONARY, not a single rect like the key-tab key above: all 4
/// lanes' own reset chips publish their frame every frame (there are 4 simultaneous controls, not one), and
/// the popup looks up whichever lane is actually open by index — merged, not last-write-wins, so one lane
/// publishing doesn't clobber another's already-known frame.
struct EuclideousResetChipFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The selected CHORDS segment's own on-screen frame (Fourfold header ferry §5.3) — the chord-grid pop-up anchors under it,
/// exactly as the key pop-up anchors under the key pill. Only that one segment publishes, so a single rect suffices.
struct EuclideousChordsSegmentFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let v = nextValue() { value = v }
    }
}

/// A tapped output's pulse (Fourfold header §7.1): `token` increments per tap so a second tap restarts the ring animation.
struct EuclideousOutputPulse: Equatable { var output: Int; var token: Int }
/// What one lane shows for the active output cue (pulse or hold-trace): which output, whether it's a held trace, and the
/// cue itself (`dim`, or a ring around the OUT circle / RHYTHM tab).
struct EuclideousOutputCueInfo { let output: Int; let held: Bool; let token: Int; let cue: EuclideousOutputCue }

/// The ring a pulse/trace draws on a lane (Fourfold header §7.1/§7.2): 2pt #DFE3EA. A PULSE starts at 95% opacity and
/// scale 1 and eases out over 650ms to 0% and scale 1.35; a HELD trace sits still at 95% until release. Visual only — never
/// blocks a touch. Reduce Motion: fade only, no scale.
struct EuclideousOutputCueRing: View {
    enum Kind { case circle, tab }
    let kind: Kind
    let held: Bool
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    var body: some View {
        Group {
            switch kind {
            case .circle: Circle().stroke(Color(hex: 0xDFE3EA), lineWidth: 2)
            case .tab: RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xDFE3EA), lineWidth: 2).padding(4)
            }
        }
        .opacity(held ? 0.95 : 0.95 * Double(1 - progress))
        .scaleEffect(held || reduceMotion ? 1 : 1 + 0.35 * progress)
        .allowsHitTesting(false)
        .onAppear { if !held { withAnimation(.easeOut(duration: 0.65)) { progress = 1 } } }
    }
}

/// LONG-PRESS HELP (usability ferry §3.3, literal): "long-pressing any control for 0.5s shows a small
/// bubble above it with a one-line plain-English explanation; it disappears on release... must never also
/// change the control's value." Attached ALONGSIDE a control's own `.onTapGesture`, never replacing it —
/// SwiftUI's own gesture-recognizer exclusivity (the same mechanism UIKit's tap/long-press recognizers use
/// underneath) ensures only one of the two ever actually fires for a given touch: a quick release satisfies
/// the sibling `TapGesture` before this one's 0.5s threshold is reached, so the long-press's `perform` never
/// runs and the control's own tap action fires completely unaffected; a genuine 0.5s+ hold satisfies THIS
/// gesture first, which cancels the competing tap recognizer for that touch — the control's value never
/// changes on a long-press, by construction, not by a hand-rolled timing check. SCOPED DELIBERATELY: only
/// ever applied to a plain `.onTapGesture`-only control. The 4 XY pads (TILT/HITS/OFFSET/STEPS/GATE/VELOCITY)
/// and the mask's own drag-to-adjust parameter chips (CHANCE included) are NOT covered — both already own a
/// full-surface UIKit (`EuclideousXYPad`) or SwiftUI `DragGesture` of their own, and layering a THIRD,
/// competing gesture on top of either without a device to verify the result risked breaking a working drag/
/// pinch/double-tap interaction for a polish feature — flagged as a real, deliberate scope reduction, not an
/// oversight (two of the ferry's own 8 named examples, TILT/OFFSET and CHANCE, fall in this excluded set).
struct EuclideousHelpBubble: ViewModifier {
    let text: String
    @State private var showing = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showing {
                    Text(text)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white).lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x22252C)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .offset(y: -28)
                        .transition(.opacity)
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 30,
                                 pressing: { down in if !down { showing = false } },
                                 perform: { showing = true })
    }
}
extension View {
    /// Attach AFTER the control's own `.onTapGesture` (order doesn't affect gesture exclusivity, but keeps
    /// the call sites reading tap-then-help, matching the order the two actually resolve in).
    func euclideousHelp(_ text: String) -> some View { modifier(EuclideousHelpBubble(text: text)) }
}

/// ONE of the SIX sliders (usability ferry, 2026-10-12, REARRANGED 2026-10-12 follow-up — Paul: "3
/// vertical on the left (count, hits, velocity) and 3 horizontal on the right (offset, tilt and gate)")
/// — HITS · STEPS · OFFSET · TILT · GATE · VELOCITY (`EuclideousSliderField`, Derivations.swift),
/// replacing `EuclidGesturePad`'s own `EuclideousXYPad` bridge entirely. Absolute touch-down-sets-value,
/// single-axis, independently owned per slider: a plain SwiftUI `DragGesture` is scoped to the ONE view
/// it's attached to, so there's no shared axis-lock/dead-zone bridge left to build at all — a sideways
/// drift from one slider onto a neighbour can never hand the touch over, since SwiftUI's gesture
/// recognition commits to the view it began on for the whole gesture's lifetime (ferry Touch behaviour
/// §1: "a touch belongs to the slider it started on until it lifts... never passes to a neighbouring
/// slider").
///
/// ORIENTATION (`horizontal`): STEPS/HITS/VELOCITY stay the original vertical track (fill rises from the
/// bottom, drag reads Y); OFFSET/TILT/GATE are now horizontal (fill grows from the left, drag reads X) —
/// same pure range/frac/commit/revert/default logic either way (Derivations.swift is orientation-
/// agnostic by construction, since it only ever reasons about a 0...1 fraction), only the GEOMETRY
/// (which axis is "travel," which is "cross") and the touch-point axis read differ, all handled by
/// `travelPos`/`crossPos`/`frac(at:)` below rather than duplicating the view twice.
///
/// `onCommit` mirrors `EuclideousPage.edit(idx:_:)`'s own shape exactly — a MUTATION closure handed
/// upward, not a precomputed line value handed back — deliberately, not incidentally: `line` below is a
/// snapshot from the LAST SwiftUI render pass, so overwriting the live model with a value computed from
/// it could silently clobber a near-simultaneous edit from a DIFFERENT slider on the same lane (two
/// fingers, two sliders, one tick apart). Mutating the TRUE live line in place — read fresh at the
/// moment `edit` actually runs on the VC side — has no such race.
///
/// DOUBLE-TAP is detected manually (two short, non-moving touches inside a 0.35s window), not via a
/// sibling native `TapGesture(count: 2)` — this file's own history (`EuclidGesturePad`'s multi-
/// recognizer coexistence notes elsewhere in this codebase) treats UIKit/SwiftUI gesture-recognizer
/// coexistence as the single most device-uncertain class of bug in this exact area; a second gesture
/// layered on top of an always-live `DragGesture(minimumDistance: 0)` risks either never firing or
/// firing unpredictably, with no way to verify which off-device. Tracking it by hand inside the SAME
/// gesture's own `onEnded` removes that uncertainty entirely.
///
/// JUDGMENT CALL, flagged: the OLD pads' 2-finger "ALL LANES" drag (nudging every lane's own field at
/// once) has no equivalent anywhere in this ferry's Touch-behaviour spec — every rule describes a single
/// finger only — and the ferry's own Engineering section says to delete the old gesture code and "leave
/// no dead code paths," not to port one of its mechanisms onto a structurally different widget. Read as
/// a deliberate scope cut: multi-lane editing is still reachable by repeating the same drag on each lane
/// in turn, just no longer in one combined gesture.
struct EuclideousSlider: View {
    let field: EuclideousSliderField
    let line: EuclidLine
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let horizontal: Bool
    var touchPad: CGFloat = 0   // 2026-10-14 ferry Fix 3: extra hit-testing margin, vertical only, horizontal
    // sliders. `var` (not `let`): a `let` property's own default value is NOT picked up by Swift's
    // synthesized memberwise init (SE-0242 only applies to `var`) — a `let` here would make every existing
    // call site that omits this param fail to compile, confirmed by the real build before landing on `var`.
    let onCommit: (@escaping (inout EuclidLine) -> Void) -> Void
    let onDoubleTap: () -> Void
    let onRevertToEuclid: () -> Void
    // LISTEN/FOLLOW (§5, adversarial-review fix, 2026-10-15): "HITS, STEPS and TILT show the partner's
    // values at 42% opacity and can't be dragged" — `displayOverrideLine` (the partner's own EuclidLine,
    // when FOLLOW is lit for this lane) makes every display computation below read the PARTNER's value
    // instead of this line's own; `listenFollowLocked` (true for exactly those 3 fields while following)
    // dims the whole slider and disables its gesture/double-tap/accessibility-adjust, mirroring the
    // EXISTING `edited` mechanism's own disable-the-gesture shape rather than inventing a second one.
    // Both default nil/false — every pre-existing call site (every OTHER field, every non-Euclideous
    // caller — there are none, but the principle holds) is byte-identical.
    var displayOverrideLine: EuclidLine? = nil
    var listenFollowLocked: Bool = false

    @State private var snapshot: EuclidLine? = nil
    @State private var lastCommitted: Double? = nil
    @State private var helpActive = false
    @State private var helpWorkItem: DispatchWorkItem? = nil
    @State private var startLocation: CGPoint? = nil
    @State private var lastShortTapAt: Date? = nil

    private let inset: CGFloat = 6

    /// The coordinate along the TRAVEL axis (x if horizontal, y if vertical) a given fraction maps to,
    /// within a track of the given travel-axis length — shared by the Canvas drawing and the touch
    /// mapping below, so the drawn fill/ticks and the gesture can never disagree about where a value
    /// sits (ferry Touch behaviour §2: "a touch inside the insets clamps to the end value").
    private func travelPos(_ frac: Double, length: CGFloat) -> CGFloat {
        let travel = max(1, length - inset * 2)
        let f = CGFloat(max(0, min(1, frac)))
        return horizontal ? inset + f * travel : inset + (1 - f) * travel
    }
    /// The inverse of `travelPos` — a raw touch coordinate along the travel axis → 0 (min) ... 1 (max).
    private func frac(atTravel p: CGFloat, length: CGFloat) -> Double {
        let travel = max(1, length - inset * 2)
        let clamped = max(inset, min(length - inset, p))
        return horizontal ? Double((clamped - inset) / travel) : Double(1 - (clamped - inset) / travel)
    }

    /// TILT disabled on a hand-edited pattern (ferry, literal): "EDITED pattern: TILT is disabled."
    /// FOLLOW (§5) takes priority over this when both would apply to the same field — a FOLLOWing
    /// lane's own hand edits are moot (its generation is replaced entirely), so the slider should read
    /// as locked-to-the-partner, not as "EDITED," while following.
    private var edited: Bool { field == .tilt && line.customHits != nil && !listenFollowLocked }
    /// §5: display FROM the partner while locked, otherwise this line's own value — the one switch every
    /// display computation below reads through, so the two can never independently drift.
    private var effectiveLine: EuclidLine { displayOverrideLine ?? line }

    /// A small opaque backing — the colour of the EMPTY track, so the value/label text reads as sitting
    /// on an island the fill/value-line never crosses (2026-10-14 fixes-after-build ferry §4): GATE at 90%
    /// put the value line through "90%"; HITS at 0 put it along the bottom of "HITS"; VEL near 127 would
    /// cross its value at the top. Drawn AFTER the Canvas (so it sits above the fill/line) but is itself
    /// just padding, not a visual box — it reads as "the text has its own small opaque patch," not a chip.
    private func backed<V: View>(_ content: V) -> some View {
        content
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x22252C)))
    }

    var body: some View {
        let curFrac = euclideousSliderFrac(field, effectiveLine)
        ZStack {
            Canvas { ctx, size in
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(Color(hex: 0x22252C)))
                let len = horizontal ? size.width : size.height
                func pos(_ f: Double) -> CGFloat { travelPos(f, length: len) }
                /// A rect spanning the FULL cross-axis, from one travel-axis coordinate to another —
                /// `a`/`b` in travel-axis order (either may be the lesser), so callers never need to
                /// know which end is "start."
                func bar(_ a: CGFloat, _ b: CGFloat) -> CGRect {
                    let lo = min(a, b), hi = max(a, b)
                    return horizontal ? CGRect(x: lo, y: 0, width: hi - lo, height: size.height)
                                      : CGRect(x: 0, y: lo, width: size.width, height: hi - lo)
                }
                /// A thin 2pt edge/centre LINE across the cross-axis, centred at one travel-axis coordinate.
                func edgeLine(_ p: CGFloat) -> CGRect { bar(p - 1, p + 1) }
                if !edited {
                    // TICKS (ferry, literal): "1pt high, 5pt long, at the left edge of the track" — HITS/
                    // OFFSET only. Rotated for a horizontal track: 1pt wide, 5pt long, at the BOTTOM edge.
                    for tf in euclideousSliderTickFracs(field, effectiveLine) {
                        let tp = pos(tf)
                        let tick: CGRect = horizontal ? CGRect(x: tp - 0.5, y: size.height - 5, width: 1, height: 5)
                                                       : CGRect(x: 0, y: tp - 0.5, width: 5, height: 1)
                        ctx.fill(Path(tick), with: .color(Color(hex: 0x4A4E57)))
                    }
                }
                if edited {
                    // DISABLED (ferry, literal): "no fill, a grey centre edge."
                    ctx.fill(Path(edgeLine(len / 2)), with: .color(.white.opacity(0.25)))
                } else if field == .tilt {
                    // BIPOLAR (ferry, literal): "the fill runs from the centre line to the value" — up
                    // for positive / down for negative when vertical, left/right when horizontal.
                    // "A centre tick is always visible."
                    let center = len / 2, value = pos(curFrac)
                    // FIX 2 (2026-10-14 ferry, "RHYTHM tab sliders: keep the mix"): the zero line is now
                    // drawn BEHIND the fill, not on top of it — "1pt #3a3e47, full height, at the centre,
                    // behind everything" — a plain draw-order swap (was fill-then-zero-line-then-value-
                    // edge; now zero-line-then-fill-then-value-edge). Still the same neutral grey as every
                    // other slider's static ticks, distinguishing "where centre is" (static) from "where
                    // the value sits" (the accent edgeLine(value) line, still live-coloured, drawn last).
                    ctx.fill(Path(edgeLine(center)), with: .color(Color(hex: 0x3A3E47)))
                    ctx.fill(Path(bar(center, value)), with: .color(accent.opacity(0.2)))
                    ctx.fill(Path(edgeLine(value)), with: .color(accent))
                } else {
                    // UNIPOLAR (ferry, literal): "rises from the bottom of the track to the value" —
                    // grows from the LEFT when horizontal.
                    let value = pos(curFrac)
                    ctx.fill(Path(bar(horizontal ? 0 : len, value)), with: .color(accent.opacity(0.2)))
                    ctx.fill(Path(edgeLine(value)), with: .color(accent))
                }
            }
            if horizontal {
                // FIX 1 (2026-10-14 ferry, "RHYTHM tab sliders: keep the mix"): one line, vertically
                // centred, matching the NOTES VEL bar's own established convention exactly — name left,
                // value right, nothing in the middle of the bar. Replaces the vertical sliders' own
                // stacked value-over-label layout, which crossed the TILT zero line when used here.
                HStack {
                    backed(
                        Text(euclideousSliderLabelText(field, effectiveLine))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.8)
                            .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                    )
                    Spacer(minLength: 4)
                    if edited {
                        // THE EDITED CHIP (ferry, literal): "LANE-20 fill, LANE-100 border, 10pt... in
                        // the value position." Its own hit area is the overlay below, not this label.
                        // Already opaque-backed by its own fill — no additional text backing needed.
                        Text("EDITED").font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.2)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent, lineWidth: 1))
                    } else {
                        backed(
                            Text(euclideousSliderValueText(field, effectiveLine))
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1).minimumScaleFactor(0.7)
                        )
                    }
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 0) {
                    // Exact-dimensions ferry (2026-10-13): value text 14pt heavy TEXT, 6pt from the
                    // slider's top edge; label 10pt MUTED, 5pt from the bottom — no longer vertically
                    // centred as a pair, each pinned to its own edge via the Spacer between them.
                    if edited {
                        // THE EDITED CHIP (ferry, literal): "LANE-20 fill, LANE-100 border, 10pt... in the
                        // value position." Its own hit area is the overlay below, not this label. Already
                        // opaque-backed by its own fill — no additional text backing needed.
                        Text("EDITED").font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.2)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent, lineWidth: 1))
                            .padding(.top, 6)
                    } else {
                        backed(
                            Text(euclideousSliderValueText(field, effectiveLine))
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1).minimumScaleFactor(0.7)
                        )
                        .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                    backed(
                        Text(euclideousSliderLabelText(field, effectiveLine)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                    )
                    .padding(.bottom, 5)
                }
            }
            if helpActive {
                Text(field.help).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .frame(width: 180)   // fixed, not width-derived — a wide horizontal slider would otherwise balloon the bubble
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x22252C)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .offset(y: -height / 2 - 30)
                    .zIndex(1000).allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        // LISTEN/FOLLOW (§5): "HITS, STEPS and TILT show the partner's values at 42% opacity" —
        // a plain opacity multiply on the whole slider; `displayOverrideLine`/`effectiveLine` above
        // already make every drawn/text value the partner's own, so this is purely the dimming half.
        .opacity(listenFollowLocked ? 0.42 : 1)
        // THE 2pt TOUCH BORDER is REMOVED (Paul 2026-10-12: "when a slider is selected it has an outline
        // appear. Please remove this behaviour") — was the ferry's own original "while touched: a 2pt
        // LANE-100 border" spec; `touching` (the @State that drove it) is gone too, having no other use.
        // FIX 3 (2026-10-14 ferry): `touchPad` extends the HIT-TESTING area only — never the visual frame
        // above — by that many points above and below, so a touch landing in the gap between two stacked
        // horizontal sliders still lands on whichever one it's closer to, with no dead strip between them.
        // `DragGesture`'s own `g.location` stays relative to this view's UNCHANGED `width×height` frame
        // regardless (a contentShape extending beyond a view's bounds doesn't move its own coordinate
        // origin), and a horizontal slider's fraction math only ever reads `g.location.x` — so padding the
        // shape vertically can't perturb where a touch resolves along the travel axis, only widen where a
        // touch is still accepted as belonging to this slider at all.
        .contentShape(touchPad > 0 ? Path(CGRect(x: 0, y: -touchPad, width: width, height: height + touchPad * 2)) : Path(CGRect(x: 0, y: 0, width: width, height: height)))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !edited, !listenFollowLocked else { return }   // ferry, literal: "touches elsewhere on a disabled TILT do nothing" / "[HITS/STEPS/TILT] can't be dragged" while following
                    if snapshot == nil {
                        snapshot = line
                        lastCommitted = euclideousSliderRange(field, line).value
                        startLocation = g.location
                        scheduleHelpCheck()
                    }
                    let start = startLocation ?? g.location
                    let moved = hypot(g.location.x - start.x, g.location.y - start.y)
                    if moved > 4 { cancelHelpCheck() }
                    guard !helpActive else { return }
                    let len = horizontal ? width : height
                    var f = frac(atTravel: horizontal ? g.location.x : g.location.y, length: len)
                    if field == .tilt { f = euclideousTiltDetentFrac(f) }
                    let v = euclideousSliderValueAt(field, line, frac: f)
                    // "NO CHANGE, NO COMMIT" (ferry Touch behaviour §6) — a touch landing on (or staying
                    // within) the band of the value it started at writes nothing.
                    if v != lastCommitted, let snap = snapshot {
                        lastCommitted = v
                        onCommit { l in euclideousSliderCommit(field, &l, snapshot: snap, newValue: v) }
                    }
                }
                .onEnded { g in
                    guard !edited, !listenFollowLocked else { return }
                    let start = startLocation ?? g.location
                    let totalMoved = hypot(g.location.x - start.x, g.location.y - start.y)
                    let wasShortTap = totalMoved <= 4 && !helpActive
                    cancelHelpCheck()
                    snapshot = nil; lastCommitted = nil; startLocation = nil; helpActive = false
                    if wasShortTap {
                        if let last = lastShortTapAt, Date().timeIntervalSince(last) <= 0.35 {
                            // DOUBLE-TAP (ferry §9): applied LAST, after whatever each individual tap's own
                            // touch-down already committed — so the default value is what's actually left
                            // once the gesture settles, even though two transient single-tap commits land
                            // first (both fold into the SAME undo coalesce burst as this one, so an UNDO
                            // afterward still restores cleanly to the state before the whole double-tap).
                            lastShortTapAt = nil
                            onDoubleTap()
                        } else {
                            lastShortTapAt = Date()
                        }
                    } else {
                        lastShortTapAt = nil
                    }
                }
        )
        .overlay(alignment: horizontal ? .trailing : .top) {
            if edited {
                // THE EDITED CHIP'S hit area (ferry, literal): "covers the top half of the slider" —
                // the TRAILING half (right) when horizontal, the natural rotation of "top" (the positive-
                // value end) for a track whose positive direction now runs left→right instead of bottom→top.
                Color.clear.frame(width: horizontal ? width / 2 : width, height: horizontal ? height : height / 2)
                    .contentShape(Rectangle())
                    .onTapGesture { onRevertToEuclid() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(listenFollowLocked ? "\(field.name), following" : (edited ? "\(field.name), edited" : field.name))
        .accessibilityValue(edited ? "double-tap to revert" : euclideousSliderAccessibilityValueText(field, effectiveLine))
        .accessibilityAdjustableAction { direction in
            guard !edited, !listenFollowLocked else { return }
            let step = euclideousSliderAccessibilityStep(field)
            let cur = euclideousSliderRange(field, line).value
            let target = direction == .increment ? cur + step : cur - step
            onCommit { l in euclideousSliderCommit(field, &l, snapshot: line, newValue: target) }
        }
    }

    /// Long-press help (ferry Touch behaviour §10, literal): "restore the value from the touch-down
    /// snapshot, then show the help bubble." `snapshot` is still this slider's OWN captured touch-down
    /// state at the time this fires (≥0.5s after touch-down, <4pt of movement the whole time —
    /// `cancelHelpCheck()` is called the instant movement exceeds 4pt, which stops this from ever firing
    /// mid-drag).
    private func scheduleHelpCheck() {
        let item = DispatchWorkItem {
            helpActive = true
            if let snap = snapshot {
                onCommit { l in euclideousSliderRevert(field, &l, snapshot: snap) }
            }
        }
        helpWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
    private func cancelHelpCheck() { helpWorkItem?.cancel(); helpWorkItem = nil }
}

/// PER-LANE TABS (Paul 2026-10-07): PATTERN/RIFF/MASK, switching independently per lane — replaces
/// the old always-visible stacked DIRECTION/HIT-MISS-RATE/RIFF-direction rows with one tabbed slot.
/// This enum's `laneTab` state is purely ephemeral (never persisted), so reordering/removing its raw
/// values here has no migration concern — a fresh page open still starts every lane on PATTERN.
// RIFF TAB RETIRED (Paul 2026-10-10 ferry §1.2) — its own direction/FREE-LOCK/INVERT/ON-REST controls moved
// to the melody pop-up's WALK section. `laneTab` is purely ephemeral (never persisted, never defaults to a
// removed case — confirmed by its own declaration), so there's no "stuck on a now-gone tab" migration needed.
// I/O TAB RETIRED (Paul 2026-10-11: "I want the io tab removed and for the output to be set in the
// pattern tab on the bottom right") — its sole remaining content (the per-lane OUT toggles, `laneOutRow`;
// the MIDI IN/KEY/CHORDS source selector had already moved to the melody pop-up on 2026-10-10) now shares
// the PATTERN tab's own bottom row with DIRECTION — see `patternControlBlock` (restyled again 2026-10-12,
// ratified PATTERN-tab-layout ferry).
// RHYTHM/MELODY/MASK (Paul 2026-10-13 ferry, "MELODY tab on the lane cards") — `pattern` renamed `rhythm`
// (display label only — "RHYTHM is PATTERN renamed," its content is unchanged); the melody pop-up (SOURCE/
// MODE/NOTE/WALK/PLACEMENT, shipped 2026-10-10) is retired entire in favour of this new tab, which holds
// every melodic setting a lane has: note choice, octave, and all riff settings.
// RIFF/NOTES SPLIT (Paul's third same-day ferry): MELODY is retired in favour of two dedicated tabs —
// RIFF (the whole riff editor + a mini-grid thumbnail that doubles as its own on/off switch) and NOTES
// (lit notes/TOP/TOP2 + the notes layer's own on/off, per-note octave shifts, octave, and velocity
// offset) — "this undoes the ruling that one OCT applies to both layers. Each layer now has its own
// octave." `laneTab` stays purely ephemeral (never persisted), so a lane saved with MELODY open opens
// on RHYTHM (the array's own fixed default) the instant this binary ships — no migration needed.
enum EuclideousLaneTab: Int, CaseIterable {
    // LISTEN REPLACES MASK (ferry 2026-10-14 §1): "Remove the MASK tab and stop the Euclid mask affecting
    // output. Keep the mask's code and saved data for now." — the tab ITSELF is gone (this case renamed,
    // not added alongside); `EuclidLine.mask`/`EuclidLineMask`/`runEuclidLine`'s own mask-application code
    // are all untouched, just never reachable from the UI and never fed a genuinely-enabled mask by the
    // one call site that used to (see Router.swift's own call-site comment).
    case rhythm = 0, riff = 1, notes = 2, listen = 3
    var label: String { switch self { case .rhythm: "RHYTHM"; case .riff: "RIFF"; case .notes: "NOTES"; case .listen: "LISTEN" } }
}

struct EuclideousPage: View {
    let lines: [EuclidLine]
    let lineReady: UInt8
    // LOOP SLOTS (FERRY "loop slots replace the riff tabs", ratified 2026-10-16) — SUPERSEDES the old
    // "four riffs, picked by tabs" model (`riffs`/`activeRiff`/`playingRiffIndex`) entirely. `liveGrid` is
    // the grid's own ranks when no slot plays (§1.2, replaces "the active riff" — one editable surface,
    // not four, edited directly or via jams — see `onEditLiveGrid`/`onJam` below). `playingSlot` is which
    // of the 4 slots is ACTUALLY SOUNDING right now (nil ⇒ the live grid plays) — every lane-local "what
    // will this lane really play" surface (the per-lane mini-grid thumbnail, the step-row footer
    // prediction, the silence-reason check) reads the EFFECTIVE grid (`effectiveGridRanks`, computed from
    // this), not a stale per-tab snapshot. `queuedSlot` is a ▶ waiting for its landing bar line,
    // `pendingKeepSlot` is a ● waiting for ITS landing — all three polled live. `riffPositions` is
    // unchanged — each lane's own live step-cursor into the shared pattern (index 0...7, -1 = not
    // started/off), independent of any of the above.
    let liveGrid: EuclideousRiff
    let loopSlots: [EuclideousLoopSlot]
    let playingSlot: Int?
    let queuedSlot: Int?
    let pendingKeepSlot: Int?
    // §6/§11.2: which of the 8 columns is currently jammed, and to what rank — polled live.
    let jamState: [(active: Bool, rank: Int)]
    let playingSlotProgress: (position: Double, lengthBars: Double)
    let riffPositions: [Int]
    // RIFF POSITION MARKERS + LANE FOOTERS (Paul 2026-10-12 ferry): each lane's live hit-ordinal + DRUNK walk
    // state — the main-thread cycle prediction's own `startOrd`/`drunkLive` baseline, same live-poll class as
    // `riffPositions` above.
    let riffWalkState: [Int64]
    // EUCLID MASK — LIVE POSITION (Paul 2026-10-11 bugfix): each lane's own mask position, hit-driven
    // exactly like `riffPositions` above — NOT a self-clock. See `maskCometRow`'s own doc comment for the
    // bug this replaced (the mask's step-bar used to sweep at a hardcoded rate against the page clock,
    // completely unrelated to when the lane actually sounded a hit).
    let maskPositions: [Int]
    // RIFF PANEL — LIVE NOTES (Paul 2026-10-08): kept as a page property (the engine/poll plumbing stays — it's
    // genuinely useful state), but NO LONGER DISPLAYED (ferry ruling 2: "remove the note labels... do not move
    // them anywhere else"). Retained here rather than torn out end-to-end so a future ask to show it again
    // doesn't need the whole poll chain (Router/Kernel/MidiSparkAudioUnit/AudioUnitViewController) rebuilt.
    let riffLivePool: [UInt8]
    // SEQUENCER PANEL (2026-10-14 ferry §2/§3/§4) — the two independent step clocks (LANES: which lanes
    // sound each step; RIFFS: which of the four riffs plays each step), their CONFIG (§2/§3's own ON/RATE/
    // LEN/cells) and their live, continuously-running step position (§4: "the step clock always runs" —
    // polled regardless of either sequencer's own ON state, same class as `riffPositions` above).
    let lanesSeq: EuclideousLanesSeq
    let riffsSeq: EuclideousRiffsSeq
    let lanesSeqStep: Int
    let riffsSeqStep: Int
    // RIFF-CELL WIPES (Paul 2026-10-10 ferry) — each lane's latest wipe-eligible event (column/rank >= 0).
    // The SIBLING NOTE VIEW panel state this queue used to ALSO feed (noteViewLastEvent/RestFlash) was
    // removed along with that panel (2026-10-14 sequencer-panel ferry) — this one survives, feeding the
    // riff grid's own walk-arrow markers, a genuinely separate feature.
    let wipeEvents: [Router.EuclideousNoteViewEventSnapshot?]
    // FOURFOLD HEADER (§4.8): each lane's latest real strike of any kind — read ONLY by the output rings' flare.
    let strikeEvents: [Router.EuclideousNoteViewEventSnapshot?]
    // PAGE REWORK (Paul 2026-10-07): the new global reset-span/key/source-mode/main-out config (§2.2-§2.4).
    let resetSpanBars: Int
    let keyRoot: Int
    let keyType: ScaleType
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the per-lane
    // sourceMode entirely (the 2026-10-08 comment this replaces described per-lane I/O as the live model;
    // it no longer is). One page-level choice, same live-mirror/onSet convention as resetSpanBars/keyRoot
    // above.
    let noteSource: EuclideousLaneSource
    let onSetNoteSource: (EuclideousLaneSource) -> Void
    let mainOutMask: UInt8
    // CHORDS BUTTON (Paul 2026-10-08): "next to [KEY] place a chords button that opens a pop-up to a chord
    // grid with rate control... base this on the existing chord grid used on the chord door." Stored/edited
    // exactly like the chord door's own chord sequencer — a plain MachineParams, only its chords* fields ever
    // touched — via the SAME generic mutate-closure convention every other page-level control here uses.
    let chords: MachineParams
    let onEditChords: (@escaping (inout MachineParams) -> Void) -> Void
    let clock: EuclidLiveClock
    let onEdit: (@escaping (inout [EuclidLine]) -> Void) -> Void
    // LOOP SLOTS — `onEditLiveGrid`/`onEditLoopSlots` are ordinary document edits (live-grid drawing,
    // paste/clear/length-change — §12.1's undo-step list); `onPlayTap`/`onKeepTap` are the ▶/● taps
    // themselves (§2/§3 — NOT ordinary edits, routed to the render thread's own bar-line-accurate timing,
    // never through `onEdit`'s document-mutate funnel); `onJam` is a live grid edit WHILE a slot plays
    // (§6 — rank `nil` clears that column's jam).
    let onEditLiveGrid: (@escaping (inout EuclideousRiff) -> Void) -> Void
    let onEditLoopSlots: (@escaping (inout [EuclideousLoopSlot]) -> Void) -> Void
    let onPlayTap: (Int) -> Void
    let onKeepTap: (Int) -> Void
    let onJam: (Int, Int?) -> Void
    let onEditLanesSeq: (@escaping (inout EuclideousLanesSeq) -> Void) -> Void
    let onEditRiffsSeq: (@escaping (inout EuclideousRiffsSeq) -> Void) -> Void
    // §4.8 (2026-10-15 ferry): "a preset pick is one undo step" — a DISCRETE action, same class as
    // `onSetActiveRiff`/`onSetKeyRoot` below, not a continuous gesture. Routing a preset pick through the
    // generic `edit()`/`onEdit` funnel would share ITS `coalesceKey: "euclideous"` with every other per-lane
    // field edit, letting a pick silently merge into whatever unrelated euclideous-line edit happened
    // immediately before it — a real adversarial-review finding, not a hypothetical. A dedicated setter with
    // its own `coalesceKey: nil` (same idiom as those two) guarantees its own undo step regardless of what
    // came before it.
    let onSetRestartMask: (Int, UInt8) -> Void
    let onSetResetSpanBars: (Int) -> Void
    let onSetKeyRoot: (Int) -> Void
    let onSetKeyType: (ScaleType) -> Void
    let onSetMainOutMask: (UInt8) -> Void
    // FOURFOLD SETTINGS (2026-10-15 ferry) — the sheet's own 4 document fields, threaded in the same plain
    // live-mirror/onSet shape as every field above. `ignoreAllNotesOff`/`busChannels`/`outputNames`/
    // `allOutputName` are the EXISTING, already-live fields/constants this ferry's MIDI IN/MAIN OUT tabs give
    // a SECOND UI surface to (§3.6/§4.3) — not new model, new UI only.
    let midiInChannelMask: UInt16
    let onSetMidiInChannelMask: (UInt16) -> Void
    let ignoreAllNotesOff: Bool
    let onSetIgnoreAllNotesOff: (Bool) -> Void
    let busChannels: [Int]
    let outputNames: [String]
    let allOutputName: String
    let onSetBusChannel: (Int, Int) -> Void
    let onAllNotesOff: () -> Void
    let hostStopBehavior: EuclideousHostStopBehavior
    let onSetHostStopBehavior: (EuclideousHostStopBehavior) -> Void
    let onOpenPresets: () -> Void   // (Paul 2026-10-11: "add a preset button on the euclidius page" — presets
                                     // were only reachable by leaving this page; opens the SAME browser overlay
                                     // the main header already uses, which the VC renders as a sibling z-above
                                     // this one, so it's reachable without ever closing Euclideous.
    // UNDO/REDO (usability ferry §7.1): disabled (40% opacity) when there's nothing to undo/redo — driven by
    // the VC's own EuclideousUndoSnapshot stack (AudioUnitViewController.swift), not persisted here.
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClose: () -> Void

    // LOOP SLOTS §1.2/§11.1: "the grid shows the effective grid at the current beat" — the live grid when
    // nothing plays, else the playing slot's own content at its live ring position, a jam always winning
    // on its own column. ONE pure read (§9.1) — `euclideousSlotRankAtPosition` (Derivations.swift, the
    // SAME function the engine's own `euclideousEffectiveRank` delegates to), never a second derivation.
    private func jamRank(_ col: Int) -> Int? { col >= 0 && col < jamState.count && jamState[col].active ? jamState[col].rank : nil }
    var effectiveGridRanks: [Int] {
        let liveRanks = liveGrid.ranksResolved
        func liveOrJam(_ col: Int) -> Int { jamRank(col) ?? (col < liveRanks.count ? liveRanks[col] : 0) }
        guard let slot = playingSlot, slot >= 0, slot < loopSlots.count else { return (0..<8).map(liveOrJam) }
        return (0..<8).map { col in
            jamRank(col) ?? euclideousSlotRankAtPosition(loopSlots[slot], column: col, positionBars: playingSlotProgress.position) ?? (col < liveRanks.count ? liveRanks[col] : 0)
        }
    }

    // SEQUENCER PANEL (2026-10-14 ferry §1): which of the two tabs (LANES=0, RIFFS=1) is showing — purely
    // ephemeral, never persisted.
    @State private var sequencerTab: Int = 0
    // §3.2's FIRST-RUN PAD HINT (the old XY pads' own animated ↕/↔ affordance) is RETIRED along with the
    // pads themselves (usability ferry, 2026-10-12) — not ported to the new sliders. Each slider's own
    // visible fill/track already reads as "drag me" far more directly than a flat 2D pad ever did (a
    // fill rising from the bottom of a track is a near-universal slider affordance; a blank square
    // wasn't), and the new ferry's own spec never mentions a hint mechanism at all. The now-orphaned
    // `midispark.euclideousPadHintSeen` @AppStorage key is simply never read again — harmless, not worth
    // a migration.
    @State private var singleTouchedLanes: Set<Int> = []
    @State private var allRowsTouched = false
    @State private var dragHUDInfo: EuclidDragHUDInfo? = nil
    // RHYTHM GESTURE CONTROLS (Paul 2026-10-14: "pulling up add hits, down removes hits, left and right are
    // offset — these existing controls exist in euclid mask") — re-enables the main step-box row's own
    // `EuclidGesturePad` (NEUTERED back on 2026-10-09 when the 4 square pads, later the 6 sliders, took over
    // hits/rotate editing — `laneCard`'s own `onRotateDelta`/`onHitsDelta` were left as `{ _ in }` no-ops).
    // `rhythmGestureSnapshot` is the line as it stood at the START of the CURRENT gesture (nil = no gesture
    // in progress) — captured ONCE per gesture (the first non-nil `onDragState` point), not every tick, so
    // HITS' own edited-pattern rebuild can round-trip exactly like the slider's identical mechanism does
    // (`euclideousSliderCommit`'s own snapshot contract). `rhythmHitsAccum`/`rhythmOffsetAccum` accumulate
    // the raw deltas since that same gesture start.
    @State private var rhythmGestureSnapshot: [EuclidLine?] = [nil, nil, nil, nil]
    @State private var rhythmHitsAccum: [Int] = [0, 0, 0, 0]
    @State private var rhythmOffsetAccum: [Int] = [0, 0, 0, 0]
    // MELODY POP-UP RETIRED 2026-10-13 ("MELODY tab on the lane cards") — `melodyPopupLane`/
    // `melodyStripFrames` are gone with it, superseded by `laneTab` below (a lane shows its melody
    // settings in-card, on its own tab, not in a floating anchored popup).
    // HIT|MISS/RATE POPUP both RETIRED 2026-10-12 (ratified PATTERN-tab-layout ferry) — INV (one toggle, same
    // `patternMiss` field) and the RATE division×feel grid both now live directly in `patternControlBlock`,
    // with no local @State of their own left to track (no pop-up to open/collapse).
    // PER-LANE TABS: which of RHYTHM/MELODY/MASK each lane currently shows — purely local/ephemeral, same
    // convention as touchedPad above (not persisted; a fresh page open always starts every lane on RHYTHM).
    @State private var laneTab: [EuclideousLaneTab] = [.rhythm, .rhythm, .rhythm, .rhythm]
    // headerResetChip/resetSpanPopupOpen/resetSpanPopupCard RETIRED (2026-10-14 sequencer-panel ferry §3:
    // "RESET becomes per-lane... replacing the old machine-wide header RESET control") — the struct's own
    // `resetSpanBars`/`onSetResetSpanBars` properties stay in place, unreachable from any new UI, matching
    // how `euclideousReceiver` was handled when ITS control was dropped (decode-safety + the real migration
    // SOURCE `EuclidLine.resetStepsResolved` reads, per Models.swift's own doc comment there).
    @State private var resetPopupLane: Int? = nil
    @State private var resetChipFrames: [Int: CGRect] = [:]
    // FOURFOLD SETTINGS (2026-10-15 ferry): `settingsTab` is explicitly NOT saved ("the sheet reopens on the
    // tab it was left on, in memory, MIDI IN the first time," §2.6) — plain ephemeral @State, same convention
    // as `laneTab` above.
    @State private var settingsOpen = false
    @State private var settingsTab = 0
    // PER-STEP RESTART MARKS (2026-10-15 ferry, "per-step restart points on the LANES tab" §4): which lanes
    // currently have their RESET box held — a Set, not a single Int, because §4.3 explicitly allows "two
    // RESET boxes held → both lanes in edit mode" simultaneously. The matching touch-down timestamp + the
    // lane's own mask AT touch-down (keyed the same way) are what §4.6's quick-tap/long-hold split reads: a
    // release counts as "a quick tap" only if it was short AND the mask is back to exactly what it was at
    // touch-down — comparing the actual resolved mask, not a separate dirty flag, so it can't go stale if a
    // toggle is ever added on a path that forgets to set a flag.
    @State private var restartEditLanes: Set<Int> = []
    @State private var restartEditTouchDown: [Int: Date] = [:]
    @State private var restartEditOriginalMask: [Int: UInt8] = [:]
    // FOUR RIFFS — the tab row's own long-press COPY/PASTE/CLEAR menu (2026-10-14 ferry §7). No precedent
    // for a long-press CONTEXT MENU anywhere in this codebase (grepped first) — built as a 5th instance of
    // the scrim+centred-card family this page already uses 4 times (RESET/MASK MODE/CHORDS/KEY), not an
    // anchored popover like the per-lane RESET above, matching the plan's own "small 3-row scrim+card
    // popup" reading, not the anchored one.
    @State private var riffTabMenuLane: Int? = nil
    @State private var keyPopupOpen = false
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry): the KEY tab's own captured
    // on-screen frame (via EuclideousRiffTabFramePreferenceKey above), letting the picker open as a
    // popover anchored near the tab instead of centre-screen — nil until the tab has rendered at least
    // once, in which case the popup falls back to centre (handled at the render site).
    @State private var riffKeyTabFrame: CGRect? = nil
    @State private var chordsPopupOpen = false
    // FOURFOLD HEADER (2026-10-15): the selected CHORDS segment's frame (the chord grid anchors under it), the output ring
    // currently HELD (§4.7, nil = none) and the last tapped output's PULSE (§7.1). Each ring's own tap-vs-hold press state
    // lives INSIDE `EuclideousRingPressable` (one instance per ring), not here.
    @State private var chordsSegmentFrame: CGRect? = nil
    @State private var heldOutput: Int? = nil
    @State private var outputPulse: EuclideousOutputPulse? = nil
    // riffDirPopupLane RETIRED 2026-10-10 alongside the RIFF tab — direction selection lives inline in the
    // melody pop-up's WALK section now, no separate nested popup needed.
    // MASK MODE POPUP (Paul 2026-10-10, "Euclid mask, modes and settings" ferry §4): "tapping opens a picker
    // of the 11 modes, grouped" — same scrim+centred-card shape as `ratePopupCard`. nil = no popup open.
    @State private var maskModePopupLane: Int? = nil
    // LISTEN PARTNER POPUP (ferry 2026-10-14 §4): "tap opens a picker with the other three lane colours" —
    // same scrim+centred-card shape as `maskModePopupCard`. nil = no popup open; otherwise which lane's
    // which row is choosing a partner.
    @State private var listenPartnerPopup: (lane: Int, row: EuclideousListenRow)? = nil
    // WALK TAGS WITH THREADS (ferry 2026-10-15) REPLACE the riff grid's retained `riffMarker` state and its 20Hz
    // refresh timer ENTIRELY. That state was the "arrows move late" prerequisite: a tag position derived through a
    // timer-sampled, retained copy of `riffPositions` can trail the RIFF-tab thumbnail, which reads
    // `riffPositions` straight off the view in the same render. A tag now has no state of its own — every frame
    // it is re-derived from the polled step (the thumbnail's own value) and the live beat (see
    // `euclideousWalkTagPlan`, Derivations.swift), so the two cannot disagree on a display tick and nothing is
    // debounced. `walkTagLog` only exists for the DEBUG device log.
    #if DEBUG
    @State private var walkTagLog = EuclideousWalkTagLog()
    #endif
    // DRAGGABLE RIFF GRID (Paul 2026-10-13, "make the grid draggable"): the matrix used to own one
    // `.onTapGesture` PER CELL — fine for a single tap, but a drag starting on one cell never reaches its
    // neighbours (a tap gesture doesn't track movement at all), so painting a shape across several columns
    // in one continuous stroke was impossible. Fixed the same way `sliderLane`'s own "drag to draw" lane
    // already fixed the identical bug (its own comment: "each bar owned its own gesture, so the first bar
    // touched captured the whole drag and the rest never responded") — ONE gesture over the WHOLE matrix,
    // hit-tested from the finger's (x,y) every `.onChanged` tick. `riffDragLastCell` is this gesture's own
    // "have I already written this exact cell" memory, nil between gestures: the FIRST cell a touch lands
    // on reuses the pre-existing TOGGLE behaviour (tap the already-set rank → clears to rest, preserving
    // every prior single-tap test/behaviour byte-for-byte); every DIFFERENT cell the finger crosses after
    // that is a plain PAINT (always sets, never toggles) — the natural way to draw a melodic shape across
    // the 8 columns without each new column accidentally re-clearing whatever the finger started on.
    @State private var riffDragLastCell: (col: Int, row: Int)? = nil
    // RIFF-CELL WIPES / RESET PROGRESS (Paul 2026-10-10 ferry "riff-cell wipes, reset progress on lane
    // cards" §5) — the first use of Reduce Motion anywhere in this codebase (grepped, zero prior
    // precedent). When on: the riff-cell wipe collapses to a single 150ms flash (no directional sweep, no
    // two-phase split); the lane-card progress FILL is hidden entirely (the fill's own TimelineView simply
    // never draws it); the header "IN n" countdown is UNAFFECTED — §5 explicitly says it "still shows."
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let laneAccents: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.35, green: 0.75, blue: 0.95),
        Color(red: 0.95, green: 0.75, blue: 0.25), Color(red: 0.55, green: 0.85, blue: 0.45),
    ]
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// §3's own partner-button colour names — `laneAccents`' own declared order (RED/BLUE/YELLOW/GREEN).
    private func listenLaneColourName(_ i: Int) -> String { ["RED", "BLUE", "YELLOW", "GREEN"][max(0, min(3, i))] }

    // ================================================================================================
    // THE LAYOUT SYSTEM (Paul 2026-10-09, ferry: "rebuild the layout on the system below; don't patch
    // individual views"). ONE spacing scale, ONE type scale, used everywhere on this page — every size
    // elsewhere in this file should trace back to one of the constants declared here, not a new ad-hoc
    // number. This REPLACES the previous "protected floor" / per-view responsive-scale approach entirely.
    // ================================================================================================

    // --- SPACING SCALE (ferry §3): exactly these three values, nothing else. ---
    private let sp4: CGFloat = 4     // gap between elements INSIDE a card: pads, segmented buttons, rows
    private let sp8: CGFloat = 8     // gap between lane cards; padding inside every card/panel, all 4 sides
    private let sp16: CGFloat = 16   // page margins; gap between header / lane grid / riff panel

    // --- TYPE SCALE: `padValueSize` is still the NOTE VIEW pad-readout size. `padSubtitleSize` (the old
    // shared pad-readout/tab-label pair) was retired 2026-10-13 — the 2026-10-13 "exact dimensions" ferry
    // gives the tab row its own literal 11pt, no longer pinned to a shared constant (the two numbers just
    // happen to still agree). `padHeadingSize` (the old pad edge-axis-label size) and its own fit-check
    // `euclideousAxisLabelFits` were retired 2026-10-12 alongside the pads themselves (usability ferry, six
    // vertical sliders) — the sliders name their own field directly on their face (`EuclideousSliderField.
    // name`, a plain always-full-length label; there's no edge-label fit problem left to solve).
    private let padValueSize: CGFloat = 13

    /// Edits ONE line by index — the shared mutation path every per-lane control below goes through.
    private func edit(_ idx: Int, _ mutate: @escaping (inout EuclidLine) -> Void) {
        onEdit { lines in guard idx >= 0, idx < lines.count else { return }; mutate(&lines[idx]) }
    }
    /// Edits ONE line's MASK by index — mirrors `edit` above, materializing a fresh `EuclidLineMask` the
    /// first time a lane's mask is ever touched (its own plain struct default, matching every other
    /// additive-Optional nested-struct precedent in this codebase, e.g. `Cell.chop`).
    private func editMask(_ idx: Int, _ mutate: @escaping (inout EuclidLineMask) -> Void) {
        edit(idx) { line in var m = line.mask ?? EuclidLineMask(); mutate(&m); line.mask = m }
    }
    // RESET MELODY RETIRED along with the melody pop-up it lived at the bottom of (Paul 2026-10-13 ferry,
    // "MELODY tab on the lane cards") — the ferry names no replacement slot for it anywhere in the new
    // tab layout, so it's treated as retired, not relocated (a disclosed interpretation, not a silent drop).

    var body: some View {
        GeometryReader { geo in
            // ORIENTATION (Paul 2026-10-08, ferry §3): recomputed from the view's OWN live bounds every time
            // SwiftUI re-lays-out (host rotation, AUM windowed ↔ full-screen, split-view resize, …) — never a
            // cached/fixed assumption. Landscape = strictly wider than tall.
            let isLandscape = geo.size.width > geo.size.height
            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.055, blue: 0.07).ignoresSafeArea()
                if isLandscape { landscapeLayout(geo.size) } else { portraitLayout(geo.size) }
                // THE DRAG HUD — same floating-card pattern as the existing EUCLID editor's own HUD
                // (BuildPage.swift's buildEuclidDragHUD/AudioUnitViewController.swift's root-ZStack
                // rendering): a top-level sibling so it can float anywhere over the lanes, converting
                // the UIKit window-space touch point via this view's own `geo.frame(in: .global)`.
                if let info = dragHUDInfo {
                    let origin = geo.frame(in: .global).origin
                    let hudW: CGFloat = 230
                    let rawX = info.point.x - origin.x
                    let halfW = hudW / 2 + 8
                    let x = min(max(rawX, halfW), max(halfW, geo.size.width - halfW))
                    // TOP-EDGE FLOOR sized to the card's own HALF-HEIGHT, not an arbitrary smaller number
                    // (found during a legibility review, 2026-10-09): `euclideousDragHUD`'s own content —
                    // 3 stacked lines (10/22/12pt, ~5pt gaps) + 16pt vertical padding each side — comes to
                    // roughly 95pt tall by the same line-height estimate this file uses elsewhere (~1.2×
                    // point size), so half of that is ~47-48pt. The previous floor of 40 left a few points
                    // of the card's own top edge able to render past y=0 when a touch lands very near the
                    // top of the page — harmless (nothing SwiftUI-clips it, and nothing sits behind it up
                    // there), but not a real guarantee either. 50 covers the estimate with margin.
                    let y = max(50, info.point.y - origin.y - 130)
                    euclideousDragHUD(info).frame(width: hudW).position(x: x, y: y).allowsHitTesting(false).zIndex(2)
                }
                // THE RATE POP-UP is RETIRED (ratified PATTERN-tab-layout ferry, 2026-10-12) — RATE now
                // lives directly in the tab as a division×feel grid, no overlay card needed.
                // MASK MODE POP-UP (Paul 2026-10-10 ferry §4) — same scrim+centred-card shape popups
                // elsewhere on this page already use.
                if let lane = maskModePopupLane {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { maskModePopupLane = nil }
                        .zIndex(3)
                    maskModePopupCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // LISTEN PARTNER POP-UP (ferry 2026-10-14 §4) — same scrim+centred-card shape.
                if let target = listenPartnerPopup {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { listenPartnerPopup = nil }
                        .zIndex(3)
                    listenPartnerPopupCard(lane: target.lane, row: target.row).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // THE MELODY POP-UP IS RETIRED ENTIRE (Paul 2026-10-13 ferry, "MELODY tab on the lane cards"):
                // every setting it held (note choice, octave, all riff settings) now lives in the RIFF and
                // NOTES tabs on each lane's own card (`tabContent`'s `.riff`/`.notes` cases, RIFF/NOTES SPLIT
                // ferry) — there is no floating popup left to anchor. `melodyPopupLane`/`melodyStripFrames`/
                // `EuclideousStripFramePreferenceKey`/`euclideousMelodyAnchor`/`melodyPopupCard`/
                // `melodyPointer` are all deleted, not left dead — confirmed by grep before removing, zero
                // remaining readers.
                // RESET SPAN + KEY POPUPS (Paul 2026-10-07) — the SAME scrim+card shape, reused rather than
                // reinvented, for the two new global pickers.
                if let lane = resetPopupLane {
                    // ANCHORED, not centred (ferry §3: "anchored near the tapped reset box") — same
                    // non-dimming full-screen tap-catcher idiom as the KEY popup just above.
                    Color.clear.contentShape(Rectangle()).onTapGesture { resetPopupLane = nil }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(3)
                    let frame = resetChipFrames[lane]
                    let anchorX = frame.map { max(110, $0.midX) } ?? geo.size.width / 2
                    let anchorY = frame.map { $0.maxY + 70 } ?? geo.size.height / 2
                    resetPopupCard(lane).position(x: min(anchorX, geo.size.width - 110), y: min(max(90, anchorY), geo.size.height - 90)).zIndex(4)
                }
                if let lane = riffTabMenuLane {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { riffTabMenuLane = nil }
                        .zIndex(3)
                    riffTabMenuCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // LOOP SLOTS §10.6: the length picker, non-dimming (same idiom as the RESET box's own
                // anchored popover) — tapping anywhere else closes it via the existing outside-tap sweep.
                if let lane = slotLengthPopoverLane {
                    slotLengthPopoverCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                if keyPopupOpen {
                    // ANCHORED POPOVER, now UNDER THE KEY PILL (Fourfold header ferry §6.2): a non-dimming full-screen
                    // tap-catcher, and the card's TOP edge sp4 below the pill, its leading edge on the pill's (clamped
                    // inside the page). The old placement centred the card beside the anchor at y ≥ 140 — fine for a
                    // mid-page tab, wrong for a header pill (it would hang ~50pt off the top). Falls back to centre if the
                    // pill hasn't published a frame yet.
                    Color.clear.contentShape(Rectangle()).onTapGesture { keyPopupOpen = false }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(3)
                    if let f = riffKeyTabFrame {
                        keyPopupCard
                            .offset(x: min(max(f.minX, sp8), max(sp8, geo.size.width - 260 - sp8)), y: f.maxY + sp4)
                            .zIndex(4)
                    } else {
                        keyPopupCard.position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                    }
                }
                // THE CHORDS POP-UP — same dimming scrim as before (content unchanged), but ANCHORED under the selected
                // CHORDS segment (Fourfold header ferry §5.3) instead of centred: top edge sp4 below the segment, leading
                // edge on the segment's, clamped inside the page (the card is up to 640 wide).
                if chordsPopupOpen {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { chordsPopupOpen = false }
                        .zIndex(3)
                    if let f = chordsSegmentFrame {
                        let cardW = min(640, geo.size.width - 32)
                        chordsPopupCard(geo.size)
                            .offset(x: min(max(f.minX, sp8), max(sp8, geo.size.width - cardW - sp8)), y: f.maxY + sp4)
                            .zIndex(4)
                    } else {
                        chordsPopupCard(geo.size).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                    }
                }
                // THE XY PAD VALUE BUBBLE is RETIRED along with the pads themselves (usability ferry,
                // 2026-10-12) — each of the six new sliders shows its own value permanently, in place, so
                // there's no floating readout left to anchor anywhere.
                // FOURFOLD SETTINGS (2026-10-15 ferry §2): "a plain overlay on the page, the way CogPage and
                // the key pop-up are: the engine never stops" — rendered at the SAME nesting level as the key
                // pop-up above (NOT CogPage's own AudioUnitViewController-level overlay — the gear lives
                // inside this page). `headerH`/`containerW` recomputed via the SAME `headerLayout` call the
                // two layout functions already use (one formula, not a parallel derivation).
                if settingsOpen {
                    let containerW = geo.size.width - sp16 * 2
                    let hdr = headerLayout(containerW: containerW, isLandscape: isLandscape)
                    EuclideousSettingsSheet(
                        tab: $settingsTab, containerW: containerW, containerH: geo.size.height,
                        headerBottomY: HM.topMargin + hdr.height,
                        onCloseSheet: { settingsOpen = false },
                        onWorkbench: { onClose() },
                        midiInMask: midiInChannelMask, onSetMidiInMask: onSetMidiInChannelMask,
                        ignoreAllNotesOff: ignoreAllNotesOff, onSetIgnoreAllNotesOff: onSetIgnoreAllNotesOff,
                        laneMasks: euclideousLaneMasks(lines), mainOutMask: mainOutMask, busChannels: busChannels,
                        outputNames: outputNames, allOutputName: allOutputName, onSetBusChannel: onSetBusChannel,
                        onAllNotesOff: onAllNotesOff,
                        hostStopBehavior: hostStopBehavior, onSetHostStopBehavior: onSetHostStopBehavior
                    )
                    .padding(.horizontal, sp16)
                    .zIndex(5)
                }
            }
            .coordinateSpace(name: "euclideousXY")
            .onPreferenceChange(EuclideousRiffTabFramePreferenceKey.self) { if let f = $0 { riffKeyTabFrame = f } }
            .onPreferenceChange(EuclideousChordsSegmentFramePreferenceKey.self) { if let f = $0 { chordsSegmentFrame = f } }
            .onPreferenceChange(EuclideousResetChipFramePreferenceKey.self) { resetChipFrames = $0 }
        }
        #if DEBUG
        .onChange(of: wipeEvents) { evs in logWalkTagHits(evs) }
        #endif
    }

    // (riffMarkerPointsRight / updateRiffMarkers REMOVED — superseded by the stateless walk-tag plan; see the
    // 2026-10-15 note on the old `riffMarker` state above.)

    // MARK: - ONE CONTAINER (this ferry §1.3, re-affirming the layout-system ferry's own rule): "the view's
    // bounds minus 16pt left and right. Header, lane grid and riff panel all span exactly that container.
    // Left and right margins must be equal within 1pt." Applied on all four sides for symmetry.
    //
    /// The riff panel's total height at a given MATRIX row height: top+bottom padding (sp8 each) + the
    /// LOOP SLOTS slot row (54pt — §10.1/§10.3: two 40pt tiles + a 14pt foot, no gap) + a gap + 8 matrix
    /// rows with 7 gaps between them. SUPERSEDES the old title-row/column-number-row budget (36pt total)
    /// the slot row replaced. `riffRowHForPanelHeight` solves the SAME formula backward from an outer
    /// height — one pair, so the panel's claimed height and its internal row height can never silently
    /// disagree. The grid-row floor rises from 4pt to 24pt (§10.1, a NEW floor this ferry introduces, not
    /// a kept one — nothing in this formula enforced 24pt before).
    private let riffSlotRowH: CGFloat = 54
    private func riffPanelHeight(rowH: CGFloat) -> CGFloat {
        sp8 * 2 + riffSlotRowH + sp4 + rowH * 8 + sp4 * 7
    }
    private func riffRowHForPanelHeight(_ panelH: CGFloat) -> CGFloat {
        max(24, (panelH - sp8 * 2 - riffSlotRowH - sp4 * 7) / 8)
    }

    // --- LANE CARD'S OWN FIXED-HEIGHT ROWS — hoisted to struct level (not re-declared inside `laneCard`),
    // read by `laneCard` itself for its internal row math. ---
    // EXACT DIMENSIONS (2026-10-13, "lane card, exact dimensions" ferry — device-mocked, measured from the
    // real mockup): the card frame is 346×306 at reference size; an outer 10pt inset (a 2pt border, visible
    // only when selected, PLUS 8pt padding — modelled as one flat `cardInset` padding since a cosmetic
    // overlay stroke doesn't itself consume layout space in SwiftUI, and toggling selection must never shift
    // where the content sits) puts the content at 326×286. Three rows — step row (44) · tab row (28) · tab
    // content (202) — separated by two 6pt gaps: 44+6+28+6+202 = 286, matching exactly.
    private let cardInset: CGFloat = 10
    private let cardRowGap: CGFloat = 6
    private let footerBandH: CGFloat = 14
    private let cometRowH: CGFloat = 44
    private let tabRowH: CGFloat = 28
    private let contentLineH: CGFloat = 36
    /// 202, the ferry's own literal "Tab content" height — this IS `tabContentH` now (not a floor the
    /// gesture pads/step-bar stretch within, now that the RHYTHM tab's own content is itself a fully fixed-
    /// height layout per the SAME ferry's RHYTHM table: 118 (sliders) + 4 + 80 (rate/direction/emitter
    /// block) = 202, exactly matching — so nothing stretches to fill a budget anymore, every number is
    /// literal).
    private var tabContentH: CGFloat { 202 }
    /// A lane card's own fixed overhead — every row except… nothing stretches anymore (ferry: "every card is
    /// 306 tall... whatever tab is open and however many steps"), so this is now simply the card's own total
    /// fixed height end to end. Used only to protect a lane-grid floor in `portraitLayout` below.
    private var laneCardFixedOverhead: CGFloat { cometRowH + tabRowH + tabContentH + cardInset * 2 + cardRowGap * 2 }

    /// FULL-WIDTH LAYOUT (this ferry §1, a BLOCKER fix; §2 removes the placeholder entirely) — SUPERSEDES
    /// the "six equal boxes" design wholesale. ROOT CAUSE of the reported bug: that design forced every
    /// cell to be SQUARE (`cellSize = min(widthCandidate, heightCandidate)`) — whichever axis was more
    /// constrained (usually height, since these panels are wide) set the size, and the OTHER axis was left
    /// with unclaimed empty space the square cells never grew into. "Content stops ~350px short of the
    /// right edge" is exactly that. FIXED by computing the lane grid's width and height INDEPENDENTLY
    /// (lane cards are no longer forced square) so the grid always fills its own column on BOTH axes, by
    /// construction — re-verified numerically (not just reasoned through) at several panel sizes before
    /// shipping, since that's the only check this environment can actually perform; see the reply for the
    /// worked numbers.
    ///
    /// PORTRAIT: lane grid spans the full container width (§1.4); below it, riff panel + NOTE VIEW split
    /// the remaining row 50/50 (this ferry §0.1, a real layout change — the space the DASHED PLACEHOLDER
    /// used to occupy, before the previous ferry deleted it outright, is NOT empty anymore; it's NOTE VIEW,
    /// per this ferry's own "supersedes the previous ferry's instruction to delete that placeholder: replace
    /// it with NOTE VIEW instead"). JUDGMENT CALL, flagged: neither ferry specifies a split fraction between
    /// riff and NOTE VIEW — 50/50 is a neutral default, not a derived number, worth correcting once seen.
    /// The shared row still gets a TARGET height (`riffRowHTarget`, 20pt/row — now NOTE VIEW's own per-strip
    /// budget too, see `riffPanelHeight`) that FLEXES DOWN below it — never the lane grid — under the SAME
    /// "fit always wins, but the primary content is protected first" precedent an earlier ferry established.
    private let riffRowHTarget: CGFloat = 20
    private func portraitLayout(_ size: CGSize) -> some View {
        let containerW = size.width - sp16 * 2
        let hdr = headerLayout(containerW: containerW, isLandscape: false)
        let headerH = hdr.height
        let totalBelowH = max(1, size.height - headerH - (HM.topMargin + sp16 * 2))   // header top margin (9, keeps the 31pt centre line) + header↔grid gap + bottom margin
        let riffTargetH = riffPanelHeight(rowH: riffRowHTarget)
        let laneGridMinH = laneCardFixedOverhead * 2 + sp8   // 2 lane-card rows + the gap between them; the gesture-pad row alone shrinks toward 0
        let sharedRowH = min(riffTargetH, max(1, totalBelowH - sp16 - laneGridMinH))
        let laneGridH = max(1, totalBelowH - sp16 - sharedRowH)
        let laneW = max(1, (containerW - sp8) / 2)
        let laneH = max(1, (laneGridH - sp8) / 2)
        let halfW = max(1, (containerW - sp16) / 2)   // riff | NOTE VIEW, 50/50 (judgment call, see above)
        let riffRowH = riffRowHForPanelHeight(sharedRowH)
        return VStack(alignment: .leading, spacing: sp16) {
            // CONTAINER RULE (this ferry §1.3): "every element is laid out within the view bounds minus
            // 16pt left and right... recalculated on every size change" — the header was the ONE element on
            // this page with no explicit width ceiling (every other row below already had `.frame(width:
            // containerW)`), so its own content (title+MAIN OUT+ON+close on row 1) could render wider than
            // the real screen with nothing to clip or compress it — the confirmed root cause of "D cut off,
            // ON/close missing." Same frame-then-pad order as the content VStack below, so both compute the
            // identical left/right margin from the SAME `containerW`.
            fourfoldHeader(hdr, containerW: containerW)
                .padding(.horizontal, sp16).padding(.top, HM.topMargin)
            VStack(spacing: sp16) {
                // AnyView on each laneCard call (2026-10-13 crash fix, see the comment inside laneCard
                // itself): the EXACT frames named in the device crash (`closure #1 in closure #1 in
                // landscapeLayout`/portraitLayout's own equivalent HStack, resolving 4 laneCard copies'
                // combined type) — erasing here bounds each HStack to a fixed-size `TupleView<(AnyView,
                // AnyView)>` instead of a tuple of 4 independently-huge opaque types.
                VStack(spacing: sp8) {
                    HStack(spacing: sp8) { AnyView(laneCard(0, width: laneW, height: laneH)); AnyView(laneCard(1, width: laneW, height: laneH)) }
                    HStack(spacing: sp8) { AnyView(laneCard(2, width: laneW, height: laneH)); AnyView(laneCard(3, width: laneW, height: laneH)) }
                }
                HStack(spacing: sp16) {
                    riffGridView(maxWidth: halfW, rowH: riffRowH).frame(width: halfW, height: sharedRowH)
                    sequencerPanel(maxWidth: halfW, maxHeight: sharedRowH)
                }
            }
            .frame(width: containerW, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }

    /// LANDSCAPE (this ferry §1.4 history, literal): lane grid ≈64% of the container, riff ≈36%, a 16pt gap
    /// between them. The riff column's share is computed DIRECTLY from the container, and the lane column
    /// takes the exact COMPLEMENT (`containerW − riffColW − sp16`) — the two always sum to exactly
    /// `containerW`, never a rounding-induced gap at the right edge. The lane grid's 2×2 cells are sized
    /// independently on each axis from that column, same non-square fix portrait uses above.
    ///
    /// The right column (this ferry §0.1, a real layout change): was riff panel alone, full column height
    /// — now riff (top) / NOTE VIEW (bottom), splitting that SAME column height 50/50 (the same judgment
    /// call as portrait's own split, flagged there).
    private func landscapeLayout(_ size: CGSize) -> some View {
        let containerW = size.width - sp16 * 2
        let hdr = headerLayout(containerW: containerW, isLandscape: true)
        let headerH = hdr.height
        let belowH = max(1, size.height - headerH - (HM.topMargin + sp16 * 2))   // header top margin (9, keeps the 31pt centre line) + header↔grid gap + bottom margin
        let cols = euclideousLandscapeColumns(containerW: containerW)   // ONE column split, shared with the header (riff panel's edge, lane gutter)
        let riffColW = cols.riffColW
        let laneColW = cols.laneColW
        let laneW = max(1, (laneColW - sp8) / 2)
        let laneH = max(1, (belowH - sp8) / 2)
        let halfH = max(1, (belowH - sp16) / 2)   // riff (top) / NOTE VIEW (bottom), 50/50
        let riffRowH = riffRowHForPanelHeight(halfH)
        return VStack(alignment: .leading, spacing: sp16) {
            fourfoldHeader(hdr, containerW: containerW).padding(.horizontal, sp16).padding(.top, HM.topMargin)
            HStack(spacing: sp16) {
                // AnyView on each laneCard call — see the 2026-10-13 crash-fix comment inside laneCard and
                // portraitLayout's identical HStack above. This is the literal pair of frames named in the
                // device crash report ("closure #1 in closure #1 in EuclideousPage.landscapeLayout(_:)").
                VStack(spacing: sp8) {
                    HStack(spacing: sp8) { AnyView(laneCard(0, width: laneW, height: laneH)); AnyView(laneCard(1, width: laneW, height: laneH)) }
                    HStack(spacing: sp8) { AnyView(laneCard(2, width: laneW, height: laneH)); AnyView(laneCard(3, width: laneW, height: laneH)) }
                }
                .frame(width: laneColW)
                VStack(spacing: sp16) {
                    riffGridView(maxWidth: riffColW, rowH: riffRowH).frame(width: riffColW, height: halfH)
                    sequencerPanel(maxWidth: riffColW, maxHeight: halfH)
                }
                .frame(width: riffColW)
            }
            .frame(width: containerW, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }

    // MARK: - FOURFOLD HEADER (ferry "Fourfold header", approved by Paul 2026-10-15) — replaces the old one-row-or-two
    // header (title · undo/redo · MIDI IN/CHORD/KEY chips · CHORDS chip · MAIN OUT circles · ON · presets · close) with four
    // GROUPS that each sit over what they control: BRAND (mark, FOURFOLD, undo/redo) · OUTPUTS (the four output rings) ·
    // NOTES (the source control + the key pill) · UTILITIES (presets, close). ON is gone — the page always runs.
    //
    // ONE FORMULA: every position/size below comes from `euclideousHeaderLayout` / `EuclideousHeaderMetrics`
    // (Derivations.swift, unit-tested) — the layout (A one row / B two rows / C compact two rows) is CHOSEN from the same
    // numbers the views are DRAWN with, and `portraitLayout`/`landscapeLayout` read this header's height and the landscape
    // column split from the same functions, so the body and the header can never disagree. No ScrollView, no
    // `.minimumScaleFactor` (house rules): text that doesn't fit truncates.
    private typealias HM = EuclideousHeaderMetrics
    private var headerInk: Color { Color(hex: 0x0D0F14) }
    private var headerText: Color { Color(hex: 0xF2F4F7) }
    private var headerMuted: Color { Color(hex: 0xAAB0BA) }
    private var headerDim: Color { Color(hex: 0x8A909A) }

    private func headerLayout(containerW: CGFloat, isLandscape: Bool) -> EuclideousHeaderLayout {
        if isLandscape {
            let c = euclideousLandscapeColumns(containerW: containerW)
            return euclideousHeaderLayout(containerW: containerW, isLandscape: true, riffLeadingX: c.riffLeadingX, laneCentreX: c.laneCentreX)
        }
        // Portrait: the lane grid spans the whole container, so its vertical gutter is the container's centre.
        return euclideousHeaderLayout(containerW: containerW, isLandscape: false, riffLeadingX: 0, laneCentreX: containerW / 2)
    }

    /// The whole header: four groups placed by the pure layout, every group centred on the 44pt row's own midline (31pt
    /// below the page top, the spec's centre line, because the page gives the block a 9pt top margin).
    private func fourfoldHeader(_ layout: EuclideousHeaderLayout, containerW: CGFloat) -> some View {
        let rowStep = HM.rowH + HM.sp4
        return ZStack(alignment: .topLeading) {
            headerBrand(layout).frame(width: layout.brand.width, height: HM.rowH, alignment: .leading)
                .offset(x: layout.brand.x, y: CGFloat(layout.brand.row) * rowStep)
            headerOutputs(layout).frame(width: layout.outputs.width, height: HM.rowH, alignment: .leading)
                .offset(x: layout.outputs.x, y: CGFloat(layout.outputs.row) * rowStep)
            headerNotes().frame(width: layout.notes.width, height: HM.rowH, alignment: .leading)
                .offset(x: layout.notes.x, y: CGFloat(layout.notes.row) * rowStep)
            headerUtilities(layout).frame(width: layout.utilities.width, height: HM.rowH, alignment: .trailing)
                .offset(x: layout.utilities.x, y: CGFloat(layout.utilities.row) * rowStep)
        }
        .frame(width: containerW, height: layout.height, alignment: .topLeading)
    }

    // MARK: BRAND — the mark, FOURFOLD, undo, redo
    private func headerBrand(_ layout: EuclideousHeaderLayout) -> some View {
        let compact = layout.compact
        let target = compact ? HM.compactTarget : HM.target
        return HStack(spacing: 0) {
            FourfoldMark()
            Color.clear.frame(width: HM.sp8, height: 1)
            if !compact {
                Text("FOURFOLD").font(.system(size: HM.wordmarkSize, weight: .heavy, design: .monospaced))
                    .tracking(HM.wordmarkTracking * HM.wordmarkSize).foregroundColor(headerText).lineLimit(1)
                    .frame(width: HM.wordmarkWidth, alignment: .leading)
                Color.clear.frame(width: HM.sp16, height: 1)
            }
            // §3.3: undo/redo keep their glyphs and their 40%-disabled look, 18pt #AAB0BA, on adjacent targets.
            Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .bold))
                .foregroundColor(headerMuted.opacity(canUndo ? 1 : 0.4))
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture { if canUndo { onUndo() } }
                .euclideousHelp("Undo the last change")
                .accessibilityLabel("Undo").accessibilityAddTraits(.isButton)
            Image(systemName: "arrow.uturn.forward").font(.system(size: 18, weight: .bold))
                .foregroundColor(headerMuted.opacity(canRedo ? 1 : 0.4))
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture { if canRedo { onRedo() } }
                .euclideousHelp("Redo the last undone change")
                .accessibilityLabel("Redo").accessibilityAddTraits(.isButton)
        }
    }

    // MARK: OUTPUTS — "OUT" + the four output rings (MAIN OUT A–D)
    private func headerOutputs(_ layout: EuclideousHeaderLayout) -> some View {
        let compact = layout.compact
        let pitch = compact ? HM.compactRingPitch : HM.ringPitch
        return HStack(spacing: 0) {
            if !compact {
                Text("OUT").font(.system(size: HM.captionSize, weight: .bold, design: .monospaced))
                    .tracking(HM.captionTracking * HM.captionSize).foregroundColor(headerDim).lineLimit(1)
                    .frame(width: HM.captionWidth, alignment: .leading)
                Color.clear.frame(width: HM.sp4, height: 1)
            }
            // One TimelineView for the four rings (never one per ring — the page's standing DSP rule): it only ticks while
            // the transport runs, because the only thing animating here is a strike's flare.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.playing)) { tl in
                let beat = walkTagBeat(at: tl.date)
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { b in outputRing(b, pitch: pitch, beat: beat) }
                }
            }
        }
    }

    /// A quarter's flare: its lane routes to this output, the output is ON, the transport runs, and that lane's latest real
    /// strike (the engine's own NOTE VIEW event, `strikeEvents`) is `age` lane-steps old — the same step unit and the same
    /// afterglow/burst windows the comet bar uses (`euclideousRingFlare`). A strike whose onset is still in the future
    /// (the engine renders ahead) reads 0 until its moment arrives.
    private func ringFlare(_ b: Int, masks: [UInt8], beat: Double) -> [Double] {
        guard clock.playing, (mainOutMask >> UInt8(b)) & 1 != 0 else { return [0, 0, 0, 0] }
        return (0..<4).map { lane -> Double in
            guard (masks[lane] >> UInt8(b)) & 1 != 0, lane < strikeEvents.count, lane < lines.count, let ev = strikeEvents[lane] else { return 0 }
            let step = max(1e-6, (lines[lane].rate ?? .r1_16).beats)
            return euclideousRingFlare(ageSteps: (beat - ev.onsetBeat) / step)
        }
    }

    private func outputRing(_ b: Int, pitch: CGFloat, beat: Double) -> some View {
        let masks = euclideousLaneMasks(lines)
        let state = euclideousOutputRingState(output: b, laneMasks: masks, mainOutMask: mainOutMask)
        let held = heldOutput == b
        let flare = ringFlare(b, masks: masks, beat: beat)
        return EuclideousRingPressable(
            onTap: { toggleMainOut(b); pulseOutput(b) },
            onHold: { began in
                // A hold NEVER toggles. Only the ring that is currently the traced one may clear the trace.
                if began { heldOutput = b } else if heldOutput == b { heldOutput = nil }
            }
        ) {
            EuclideousOutputRing(letter: ["A", "B", "C", "D"][b], state: state, laneColours: laneAccents, held: held,
                                 flare: flare, width: pitch, height: HM.rowH)
                .opacity(heldOutput != nil && !held ? 0.42 : 1)        // §4.7: while one is held, the other three sit at 42%
        }
        .accessibilityElement(children: .ignore)
        // §4.9: "Main out A, on, fed by lanes 1 and 4" — the state is IN the label (spec string), so no separate value.
        .accessibilityLabel(ringAccessibilityLabel(b, state: state))
        .accessibilityHint("Hold to show its lanes")
        .accessibilityAddTraits(.isButton)
        .ringToggleTrait()
        .accessibilityAction { toggleMainOut(b); pulseOutput(b) }
        .accessibilityAction(named: "Show its lanes") { pulseOutput(b) }   // VoiceOver can't perform a hold
    }
    private func ringAccessibilityLabel(_ b: Int, state: EuclideousOutputRingState) -> String {
        let fed = (0..<4).filter { state.lit[$0] }.map { $0 + 1 }
        let lanes: String
        switch fed.count {
        case 0: lanes = "no lanes"
        case 1: lanes = "lane \(fed[0])"
        default: lanes = "lanes " + fed.dropLast().map(String.init).joined(separator: ", ") + " and \(fed[fed.count - 1])"
        }
        return "Main out \(["A", "B", "C", "D"][b]), \(state.mode == .off ? "off" : "on"), fed by \(lanes)"
    }
    private func toggleMainOut(_ b: Int) { onSetMainOutMask(mainOutMask ^ (1 << UInt8(b))) }   // unchanged action: no undo recorded
    /// PULSE (§7.1): one ring per routed lane, then gone. Visual only — no state worth keeping, no undo.
    private func pulseOutput(_ b: Int) {
        let token = (outputPulse?.token ?? 0) + 1
        outputPulse = EuclideousOutputPulse(output: b, token: token)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if outputPulse?.token == token { outputPulse = nil }
        }
    }
    // MARK: NOTES — the source control + the key pill
    private func headerNotes() -> some View {
        HStack(spacing: HM.sp8) {
            headerSourceControl()
            headerKeyPill()
        }
    }
    /// MIDI IN · CHORDS · KEY as ONE segmented control (§5): a 32pt #2A2D34 container (radius 8), 24pt segments (radius 6)
    /// of FIXED widths 66/70/40 so nothing moves when the selection changes. Tapping an unselected segment switches the
    /// source; tapping the SELECTED CHORDS opens the chord grid (only that segment shows a chevron); tapping the selected
    /// MIDI IN or KEY does nothing — KEY no longer opens the key pop-up (the pill does).
    private func headerSourceControl() -> some View {
        let current = noteSource
        let items: [(src: EuclideousLaneSource, label: String, spoken: String)] = [(.midi, "MIDI IN", "MIDI in"), (.chords, "CHORDS", "Chords"), (.key, "KEY", "Key")]
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                headerSourceSegment(items[i].src, label: items[i].label, spoken: items[i].spoken, width: HM.segmentWidths[i], selected: current == items[i].src)
            }
        }
        .padding(.horizontal, HM.segmentInset)
        .frame(width: HM.segmentedWidth, height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(patternUnselectedFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note source")
    }
    private func headerSourceSegment(_ src: EuclideousLaneSource, label: String, spoken: String, width: CGFloat, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(selected ? Color(hex: 0xDFE3EA) : Color.clear).frame(height: 24)
            HStack(spacing: HM.sp4) {
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundColor(selected ? headerInk : headerMuted).lineLimit(1)
                if selected && src == .chords {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(headerInk)
                }
            }
        }
        .frame(width: width, height: 32)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: EuclideousChordsSegmentFramePreferenceKey.self,
                                       value: src == .chords ? g.frame(in: .named("euclideousXY")) : nil)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !selected { onSetNoteSource(src) }
            else if src == .chords { settingsOpen = false; chordsPopupOpen = true }   // §2.1: opening it closes the sheet first
            // selected MIDI IN / KEY: literally nothing.
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected && src == .chords ? "Double-tap to edit the chord grid" : "")
    }
    /// The key pill (§6): the current key in the receiver chip's own format, a chevron, tap → the existing key pop-up
    /// anchored under it. Shown and active in every source mode. While the pop-up is open it inverts and the chevron flips.
    private func headerKeyPill() -> some View {
        let open = keyPopupOpen
        return HStack(spacing: HM.sp8) {
            Text(euclideousKeyLabel(root: keyRoot, type: keyType)).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
                .foregroundColor(open ? headerInk : headerText).lineLimit(1).truncationMode(.tail)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(open ? headerInk : headerMuted)
                .rotationEffect(.degrees(open ? 180 : 0)).fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HM.sp8)
        .frame(width: HM.keyPillWidth, height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(open ? Color(hex: 0xDFE3EA) : patternUnselectedFill))
        .background(
            GeometryReader { g in
                // The key pop-up's anchor — the publisher MOVED here from the old KEY chip (the pop-up reads it unchanged).
                Color.clear.preference(key: EuclideousRiffTabFramePreferenceKey.self, value: g.frame(in: .named("euclideousXY")))
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { settingsOpen = false; keyPopupOpen = true }   // §2.1: opening it closes the sheet first
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key, \(euclideousKeySpokenName(root: keyRoot, type: keyType))")
        .accessibilityHint("Double-tap to change")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: UTILITIES — presets, close (outline icons, one family with undo/redo)
    private func headerUtilities(_ layout: EuclideousHeaderLayout) -> some View {
        let target = layout.compact ? HM.compactTarget : HM.target
        return HStack(spacing: 0) {
            Image(systemName: "folder").font(.system(size: 18)).foregroundColor(headerDim)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture { settingsOpen = false; onOpenPresets() }   // §2.1: opening it closes the sheet first
                .accessibilityLabel("Presets").accessibilityAddTraits(.isButton)
            // FOURFOLD SETTINGS (2026-10-15 ferry §1): the × (xmark) LEAVES the header — its old job (back to
            // the workbench) moves to the sheet footer's WORKBENCH link (§7.1). UTILITIES keeps its exact
            // widths (still 2 icons, `target` unchanged) so the header ladder holds as written (§1.1, §9).
            Image(systemName: "gearshape").font(.system(size: 18)).foregroundColor(settingsOpen ? Color(hex: 0x0D0F14) : headerDim)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(settingsOpen ? Color(hex: 0xDFE3EA) : Color.clear))
                .animation(.easeInOut(duration: 0.15), value: settingsOpen)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture {
                    if !settingsOpen { closeAllOtherOverlays() }
                    settingsOpen.toggle()
                }
                .accessibilityLabel("Settings").accessibilityAddTraits(.isButton).accessibilityAddTraits(settingsOpen ? .isSelected : [])
        }
    }
    /// §2.1: "one overlay at a time: opening the key pill, the chord grid or presets closes the sheet first,
    /// and opening the sheet closes them" — this half of that rule (closing the OTHER three before the sheet
    /// opens); the sibling trigger points (key pill, chords segment, the folder/presets icon) each call this
    /// too before opening their own overlay. No existing "one overlay at a time" coordination to extend —
    /// every pop-up on this page toggles fully independently today, confirmed by reading each one first.
    private func closeAllOtherOverlays() {
        keyPopupOpen = false; chordsPopupOpen = false; resetPopupLane = nil; riffTabMenuLane = nil; slotLengthPopoverLane = nil
    }

    // MARK: LANE SIDE of the output rings (§7) — pulse (after a tap) and trace (while held)
    /// What lane `lane` shows right now: nil when nothing is pulsing/held or this lane isn't involved.
    private func outputCue(forLane lane: Int) -> EuclideousOutputCueInfo? {
        let mode: EuclideousOutputCueMode, output: Int, token: Int
        if let h = heldOutput { mode = .trace; output = h; token = 0 }
        else if let p = outputPulse { mode = .pulse; output = p.output; token = p.token }
        else { return nil }
        let rhythm = (0..<4).map { ($0 < laneTab.count ? laneTab[$0] : .rhythm) == .rhythm }
        let cue = euclideousOutputCues(output: output, laneMasks: euclideousLaneMasks(lines), laneShowsRhythm: rhythm, mode: mode)[lane]
        return cue == .none ? nil : EuclideousOutputCueInfo(output: output, held: mode == .trace, token: token, cue: cue)
    }

    /// PER-LANE RESTART PRESETS popup (2026-10-15 ferry §6, replacing the 2026-10-14 ferry's plain OFF/
    /// 1/2/4/8 list): same outer card chrome as before (kept, not reinvented — §6 itself: "keep the existing
    /// popup's presentation... only the content changes," and this codebase's own standing "source wins
    /// over a screenshot measurement" rule applies here too, so the OUTER card's fill/border/radius/padding/
    /// width/shadow stay exactly what's already shipped; only the three rows inside are new). Picking a
    /// chip stamps `EuclidLine.restartMask` via the existing generic `edit`/`onEdit` funnel — the SAME path
    /// (and therefore the same undo-coalescing behaviour) a direct hand-edit during a hold already uses.
    private func resetPopupCard(_ lane: Int) -> some View {
        let mask = lane < lines.count ? lines[lane].restartMaskResolved : 0
        let len = max(1, min(8, lanesSeq.len))
        let label = euclideousRestartLabel(mask: mask, loopSteps: len)
        let accent = laneAccents[lane % laneAccents.count]
        func chip(_ title: String, width: CGFloat, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(title).font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(selected ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
                .frame(width: width, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? lane20(accent) : Color(hex: 0x2A2D34)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? lane100(accent) : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RESTART · LANE \(lane + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.04).foregroundColor(Color(hex: 0xAAB0BA))
                Spacer()
                if label.unit == "PTS" {
                    Text("CUSTOM · \(label.value) PTS").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xF2F4F7))
                        .padding(.horizontal, 4).frame(height: 14)
                        .background(RoundedRectangle(cornerRadius: 4).fill(lane20(accent)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(lane100(accent), lineWidth: 1))
                }
            }
            .frame(height: 14)
            HStack(spacing: 4) {
                Text("EVERY").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                ForEach([1, 2, 4, 8], id: \.self) { n in
                    let selected = label.unit == "STEP" && label.value == "\(n)"
                    chip("\(n)", width: 30, selected: selected) {
                        onSetRestartMask(lane, euclideousStampMask(n))
                        resetPopupLane = nil
                    }
                }
                Text("STEP").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                Spacer(minLength: 8)
                chip("OFF", width: 38, selected: label.unit == "OFF") {
                    onSetRestartMask(lane, 0)
                    resetPopupLane = nil
                }
            }
            .frame(height: 30)
            Text("HOLD RESET + TAP STEPS = CUSTOM").font(.system(size: 9, design: .monospaced))
                .tracking(0.02).foregroundColor(Color(hex: 0x8A909A))
                .frame(height: 12)
        }
        .padding(8).frame(width: 256)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - KEY (Paul 2026-10-08, moved into header row 1 above)

    /// KEY mode's exact root/scale options and whether it should reuse the SCALE-door/FOUNT machinery are
    /// explicitly OPEN (spec §4.3) — this reuses the existing, already-canonical `ScaleType` (13 cases) as
    /// the scale list rather than inventing a second taxonomy, which is the one part of this picker that
    /// ISN'T a guess; the root grid reuses this codebase's own standard 12-note-name array.
    private var keyPopupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEY").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { k in
                    let on = ((keyRoot % 12) + 12) % 12 == k
                    Text(noteNames[k]).font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.75))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                        .onTapGesture { onSetKeyRoot(k) }
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(ScaleType.allCases, id: \.self) { t in
                        let on = keyType == t
                        Text(t.label).font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                            .onTapGesture { onSetKeyType(t); keyPopupOpen = false }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(16).frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - The CHORDS pop-up (Paul 2026-10-08): "a pop-up to a chord grid with rate control... base this on
    // the existing chord grid used on the chord door."
    //
    // SCOPED to PATTERN mode only — no MODE/SCALE-FROM/VOICING/SPREAD/WALK (the full feature set the regular
    // CHORDS processor/chord door expose) — "a chord grid with rate control" names exactly two concerns, and
    // SCALE FROM specifically would be a dead control here regardless (it points at a receiver door; Euclideous
    // has none — this page's own KEY, right beside the CHORDS button, is the key already). VOICING/SPREAD sit
    // at their sensible defaults (TRIAD/CLOSE), not exposed.
    //
    // NOT a literal `ProcessorBox(machine:...type: .chords)` mount (the way the chord door reuses the whole
    // processor editor) — that component's own SCALE-FROM control has no meaning here and nothing in this
    // page's own call would ever read it, which would make it a convincing-looking but inert control. Instead
    // this reuses the exact PURE functions the real matrix is built from — `chordsMatrixCell`/`degreeLabel`
    // (Derivations.swift, already free/shared) — in a bespoke grid modelled closely on `riffGridView`'s own
    // tap-to-set pattern a few hundred lines below, not on the private `stateMatrixRadio` (which also drags in
    // live-playhead/pulse-glow/E-BRUSH machinery this page's scoped-down popup doesn't need).
    private func chordsPopupCard(_ size: CGSize) -> some View {
        let steps = chords.chordsStepsResolved
        let degrees = chords.chordsDegreesResolved(steps: steps)
        let rows = Array(0...7)   // 0...6 = degrees I...vii, 7 = REST — matches the regular CHORDS processor's own matrix exactly
        let cellGap: CGFloat = 3
        let rowLabelW: CGFloat = 64
        let maxW = min(640, size.width - 32)
        let cellW = max(18, (maxW - 32 - rowLabelW - cellGap * CGFloat(max(1, steps) - 1)) / CGFloat(max(1, steps)))
        let cellH: CGFloat = 24
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CHORDS").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                Spacer()
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    .contentShape(Rectangle()).onTapGesture { chordsPopupOpen = false }
            }
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("STEPS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    chordsStepStepper("−") { onEditChords { $0.chordsSteps = max(1, steps - 1) } }
                    Text("\(steps)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)).frame(minWidth: 20)
                    chordsStepStepper("+") { onEditChords { $0.chordsSteps = min(16, steps + 1) } }
                }
                HStack(spacing: 6) {
                    Text("RATE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    HStack(spacing: 2) {
                        ForEach(StepRate.allCases, id: \.self) { r in
                            let on = chords.chordsRateResolved == r
                            // §6.1's 10pt floor (this re-check pass): dropped the `.minimumScaleFactor(0.6)`
                            // that used to sit here — it never actually triggered (StepRate's longest raw
                            // value, "1/2.", is 4 chars, well under this 34pt box at 10pt) but COULD have
                            // rendered as small as 6pt if it ever had, a live violation of the floor rather
                            // than a safe no-op; removing it costs nothing since it was never load-bearing.
                            Text(r.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(on ? .black : .white.opacity(0.7)).lineLimit(1)
                                .frame(width: 34, height: 24)
                                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                                .contentShape(Rectangle())
                                .onTapGesture { onEditChords { $0.chordsRate = r } }
                        }
                    }
                }
            }
            VStack(spacing: cellGap) {
                ForEach(rows, id: \.self) { opt in
                    HStack(spacing: cellGap) {
                        Text(opt == 7 ? "REST" : degreeLabel(degree: opt, scaleTones: keyType.intervals))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                            .frame(width: rowLabelW, alignment: .leading)
                        ForEach(0..<steps, id: \.self) { c in
                            let cell = chordsMatrixCell(degrees, step: c, steps: steps)
                            let on = cell.bright == opt
                            let dimOn = !on && cell.faint == opt
                            RoundedRectangle(cornerRadius: 4)
                                .fill(on ? Color.white.opacity(0.9) : (dimOn ? Color.white.opacity(0.22) : Color.white.opacity(0.06)))
                                .frame(width: cellW, height: cellH)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : 0.12), lineWidth: 1))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Matches the regular CHORDS processor's own set: closure exactly — an
                                    // unconditional write, no tap-again-to-clear (REST is its own explicit row).
                                    onEditChords { p in
                                        var a = p.chordsDegreesResolved(steps: steps)
                                        if c < a.count { a[c] = opt }
                                        p.chordsDegrees = a
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: maxW)
        .frame(maxHeight: size.height - 60)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    private func chordsStepStepper(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // LANE-CARD RESET-PROGRESS BACKGROUND FILL REMOVED (Paul 2026-10-12: "remove... the Euclid control
    // background effect") — the slow per-lane band that used to creep across a card as the RESET SPAN
    // window elapsed (`laneCardProgressFill`, + its own `TimelineView`) is gone entirely, ahead of the
    // incoming lane-footer redesign. `euclideousResetProgress`/`euclideousNoteViewSpanBeats` (the pure
    // Derivations functions it read) are untouched — they're still used elsewhere (the header's own
    // "IN n" RESET countdown) — only this one background-fill consumer is removed.

    /// LANE FOOTER STATES (2026-10-13, "footers inside the step cells" ferry — supersedes the separate
    /// `laneFooter` ROW this replaces; now a PURE computation, not a view) — one state per Euclid step, fed
    /// straight to `EuclidCometBar` so it can draw each step's own band INSIDE that step's own cell rect,
    /// rather than a second row underneath that needed its own hand-replicated alignment geometry. Reads
    /// the shared `euclideousLapHitSteps`/`euclideousRiffLapBaseline`/`euclideousRiffCyclePrediction`/
    /// `euclideousFooterStates` pure functions (Derivations.swift) fresh every time this view's body runs —
    /// SwiftUI only re-evaluates it when one of `line`/`riff`/`riffWalkState` actually changes, which is
    /// exactly "recompute... whenever settings... change" (Prediction rule 1) without a hand-rolled cache.
    private func laneFooterStates(_ idx: Int, _ line: EuclidLine) -> [EuclidFooterState] {
        // A FOLLOW lane plays its PARTNER's pattern (and step count), so its footer is predicted from THAT — the same
        // finished buffer the engine and the step bar use (`euclideousEffectivePattern`). Every other lane is unchanged.
        let follow = euclideousEffectivePattern(lane: idx, lines: lines).flatMap { $0.followsPartner ? $0 : nil }
        let steps = follow?.n ?? max(2, min(16, line.steps))
        let hitSteps = follow.map { euclideousLapHitSteps(buf: Array($0.buf.prefix($0.n)), dir: line.directionResolved) }
            ?? euclideousLapHitSteps(pulses: line.pulses, steps: steps, rotate: line.rotate,
                                      tilt: line.tiltResolved, patternMiss: line.patternMissResolved,
                                      customHits: line.customHitsResolved(steps), dir: line.directionResolved)
        var prediction: [Int]? = nil
        if line.riffOnResolved {
            let ws = idx < riffWalkState.count ? riffWalkState[idx] : Int64(0)
            let locked = line.riffLockResolved, advanceStep = line.riffAdvanceStepResolved
            let baseline = euclideousRiffLapBaseline(hitSteps: hitSteps, lapSteps: steps, locked: locked, advanceStep: advanceStep,
                                                       liveOrd: ws, dir: line.directionResolved)
            prediction = euclideousRiffCyclePrediction(hitSteps: hitSteps, advanceStep: advanceStep, dir: line.euclideousRiffDirResolved,
                                                         stride: line.riffStrideResolved, length: line.riffLengthResolved,
                                                         rotate: line.riffRotateResolved, seed: UInt64(bitPattern: Int64(line.riffDirSeedResolved)),
                                                         startOrd: baseline.startOrd)
        }
        // LIT NOTES PLUS THE RIFF (Paul 2026-10-13 ferry), Elsewhere-on-page §4: riff off + notes lit → a
        // `.hit(riffStep: nil)` band (drawn grey, no number, by `EuclidCometBar` itself); riff off + nothing
        // lit → `.miss` everywhere, "because nothing will sound."
        // RIFF/NOTES SPLIT (third same-day ferry): the notes layer's own master switch gates this too —
        // nothing can be "lit" in the sense that matters here if the whole layer is off.
        let anyLit = line.notesOnResolved && (line.litNotesResolved != 0 || line.topLitResolved || line.top2LitResolved)
        return euclideousFooterStates(hitSteps: hitSteps, lapSteps: steps, prediction: prediction, riffRanksResolved: effectiveGridRanks, anyLit: anyLit)
    }

    @ViewBuilder private func laneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        let tab = idx < laneTab.count ? laneTab[idx] : .rhythm
        // ONE INNER WIDTH FOR EVERY ROW — every row below is built from THIS one width, never the raw card
        // `width` (W = 326 at the ferry's own reference 346pt card). "Wider cards: flexible items share the
        // extra width" — `innerWidth` scales directly with `width`, so every formula below that derives from
        // it already satisfies this. "Narrower cards: if W is under 326, stop and report" — flagged in the
        // CLAUDE.md status entry for this ferry; nothing here can literally halt rendering, so a too-narrow
        // card still lays out (by the same scaling formulas), just unverified below the reference size.
        let innerWidth = max(1, width - cardInset * 2)
        // THREE FIXED ROWS (ferry: step row 44 · tab row 28 · tab content 202, two 6pt gaps between them) —
        // `contentAreaH` is no longer a "whatever's left" budget; it's the literal 202 whenever `height`
        // matches the reference 306 exactly, and scales only if a caller ever hands this a different height.
        let outerVPad: CGFloat = cardInset * 2
        let rowGaps: CGFloat = cardRowGap * 2
        let contentAreaH = max(1, height - cometRowH - tabRowH - outerVPad - rowGaps)
        let steps = max(2, min(16, line.steps))
        VStack(alignment: .leading, spacing: cardRowGap) {
            // LISTEN TAB: a FOLLOW lane PLAYS its partner's pattern, at the partner's rate — so its bar shows THAT (lit cells in the
            // partner's colour, faded; the comet sweeping at the partner's pace) and its bar gestures edit the PARTNER, the thing it
            // is following (2026-10-16). SHADOW keeps its footer-height partner-colour band (see `EuclidLaneBox`).
            let followIdx = euclideousFollowPartner(lane: idx, lines: lines)
            let gestureLane = euclideousRhythmGestureTarget(lane: idx, lines: lines)
            let followEff = followIdx != nil ? euclideousEffectivePattern(lane: idx, lines: lines) : nil
            let listenFollowTint: Color? = followIdx.map { laneAccents[$0 % laneAccents.count] }   // the partner's colour: the lit cells + the badge dot
            let listenShadowTint: Color? = line.listenPitchMode == .shadow ? laneAccents[line.listenPitchPartnerResolved % laneAccents.count] : nil
            EuclidLaneBox(idx: idx, line: line, width: innerWidth, height: cometRowH, accent: accent,
                          // WHOLE-CARD OUTLINE (ferry §1.4): `selected` here used to draw EuclidLaneBox's own
                          // border/fill around just this row (the step-bar area) — always `false` now; the
                          // selection indicator moved to a single outline around the ENTIRE card below.
                          selected: false, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: followIdx.map { lines[$0].rate ?? .r1_16 } ?? (line.rate ?? .r1_16), spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          // RHYTHM GESTURE CONTROLS (Paul 2026-10-14, re-enabled — mirrors MASK's own
                          // identical wiring, `maskStepBar` below, just targeting this lane's REAL
                          // pulses/rotate instead of its mask's): up adds hits, down removes, left/right
                          // is offset — routed through the SAME `euclideousSliderCommit` the RHYTHM tab's
                          // own HITS/OFFSET sliders use, so an edited (hand-drawn) pattern rebuilds/round-
                          // trips identically whichever control you drag, and OFFSET can't disagree with
                          // the slider's own just-fixed drag-direction mirror.
                          // A FOLLOWing lane's gestures edit the lane it follows (`gestureLane` = idx for every other lane).
                          onRotateDelta: { d in euclideousApplyRhythmX(gestureLane, d) },
                          onHitsDelta: { d in euclideousApplyRhythmY(gestureLane, d) },
                          onStepsDelta: { d in edit(gestureLane) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },   // PINCH — the one thing explicitly kept on the comet bar itself
                          onAllRotateDelta: { d in euclideousApplyAllRhythmX(d) },
                          onAllHitsDelta: { d in euclideousApplyAllRhythmY(d) },
                          onDragState: { point, allRows in euclideousRhythmDragState(gestureLane, via: idx, point, allRows) },
                          // WHOLE-CARD SELECTION HIGHLIGHT REMOVED (Paul: "remove the highlight that
                          // sometimes appears around the euclid lane boxes") — `onSelect` has no remaining
                          // effect anywhere on this page (confirmed by grep before removing the state it
                          // used to drive), so this is a genuine no-op, not a disabled one.
                          onSelect: { },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          // LANE FOOTER BANDS (2026-10-13 ferry, "footers inside the step cells" — supersedes
                          // the separate trailing row the comment here used to describe): a pure array, not a
                          // view — `EuclidCometBar` draws each step's own band directly inside that step's
                          // own cell rect now, so there's no separate row height/gap to budget here at all.
                          footerStates: laneFooterStates(idx, line),
                          stepCountBadge: AnyView(stepCountBadge(
                              followEff?.n ?? steps,
                              dotTint: listenFollowTint)),
                          stepCountBadgeWidth: stepCountBadgeTotalWidth,
                          // EXACT DIMENSIONS (2026-10-13 ferry): zero self-padding, 6pt spacing, the CHIP+
                          // triangle play button, flat LANE-100/#2c2f36 cell colours, the hand-placed notch.
                          compact: true,
                          // STEP GROUPS (2026-10-14 ferry): the RHYTHM tab's own main step row groups its
                          // steps (4, or 3 under triplet feel) with a leftover rule — this is the ONE call
                          // site this ferry's own §1-4 target ("a lane's step row"); the MASK step bar
                          // (§5, `maskStepBar`) opts in separately, and the regular BUILD-page EUCLID
                          // editor (GridUI.swift) is untouched, per `grouped`'s own false default.
                          grouped: true, listenShadowTint: listenShadowTint,
                          // FOLLOW: the bar's cells must be the pattern that actually plays (the partner's), or the footer drawn
                          // inside them — and the cells themselves — disagree with the engine. They are drawn in the partner's
                          // colour, faded, and the comet sweeps at the partner's rate × the multiplier.
                          patternOverride: followEff.map { Array($0.buf.prefix($0.n)) },
                          cellTint: listenFollowTint, cellFade: followIdx != nil ? euclideousListenCellFade : 1,
                          rateBeatsOverride: followEff?.rateBeats,
                          // FERRY (2026-10-14 §5): the one piece the footer prediction itself doesn't carry —
                          // whether landing on a riff rest actually sounds (FILL) or not (SKIP/TIE).
                          riffOnRest: line.riffOnRestResolved)
            // TYPE-METADATA STACK OVERFLOW FIX (2026-10-13, device crash: "Thread stack size exceeded" /
            // EXC_BAD_ACCESS on the main thread, inside recursive swift::Demangle type-metadata decoding,
            // bottoming out through landscapeLayout's laneCard assembly — EuclideousLaneTab visible in a
            // crashing register). The MELODY tab's rewrite this session (8 note buttons + TOP/TOP2 each
            // individually ZStack'd/modified/ForEach'd, plus the walk/modes/values rows) pushed laneCard's
            // combined view-tree type past what the Swift runtime can demangle without overflowing the main
            // thread's 1MB stack when AttributeGraph first resolves it. AnyView here breaks the type up into
            // independently-resolvable chunks — the SAME technique this function already uses for
            // `stepCountBadge` below (and, at the time, the now-retired `trailingContent` slot) — rather
            // than a logic change; nothing about what's drawn or how it behaves is different.
            AnyView(laneTabRow(idx, line, accent, rowH: tabRowH))
            AnyView(tabContent(idx, line, tab, accent, contentAreaH: contentAreaH, fullWidth: innerWidth))
        }
        .padding(cardInset)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1B1D23)))
        .clipped()
        // FOURFOLD §7.2: while an output ring is HELD, every lane NOT routed to it sits at the existing OFF-dim 42% (no animation
        // — release restores everything at once). Routed lanes get their ring in `laneTabRow` / `laneOutRow` instead.
        .opacity(outputCue(forLane: idx)?.cue == .dim ? 0.42 : 1)
    }

    // THE COUNT BOX (2026-10-13 "lane card, exact dimensions" ferry, literal): "CHIP fill, 9pt radius,
    // number 15pt heavy TEXT, centred." Simplified from the old output-chip/NO-OUT sub-display — that per-
    // lane routing readout is now the RHYTHM tab's own dedicated Emitters row (A·B·C·D, part of this SAME
    // ferry's own RHYTHM table), making the count box's old secondary content redundant; dropped here rather
    // than kept alongside it. `accent`/`mask` params are gone — this box no longer needs either.
    private var stepCountBadgeTotalWidth: CGFloat { 44 }
    /// §8: "FOLLOW: the count box shows the inherited step count, with an 8pt dot in the partner's
    /// LANE-100 3pt below the number." `dotTint` nil (every other state) ⇒ byte-identical to before.
    private func stepCountBadge(_ n: Int, dotTint: Color? = nil) -> some View {
        VStack(spacing: 3) {
            Text("\(n)").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(patternSelectedText)
            if let dotTint { Circle().fill(dotTint).frame(width: 8, height: 8) }
        }
        .frame(width: stepCountBadgeTotalWidth, height: 44)
        .background(RoundedRectangle(cornerRadius: 9).fill(patternUnselectedFill))
    }

    // MARK: - COLOUR HIERARCHY (this ferry §4): "lane colour is currently used at full strength in about
    // seven places per card, so nothing stands out." Three strengths of each lane's own accent, used
    // consistently instead of ad-hoc opacity values guessed per call site:
    //   LANE-100 — the full colour: lit hit cells in the shared comet bar (untouched, a pre-existing
    //     component), the selected lane's card outline, the RIFF/MASK tab on-dots, and the 1pt borders
    //     LANE-20 fills in §4.2 get.
    //   LANE-40  — the lane colour at 40% (§4.4's riff-pad tint was stronger than this; §5.2's rhythm
    //     picture hit cells use this tier).
    //   LANE-20  — the lane colour at 20% (§4.2's "selected choice" fills; §5.1/§5.3's picture fills).
    // Plain `.opacity()` is the correct, idiomatic way to render "at N% over the card background" in
    // SwiftUI — every one of these call sites already draws directly over that background, so the
    // composited result reads exactly as a blend with it, matching every other tint already in this file.
    private func lane100(_ c: Color) -> Color { c }
    private func lane40(_ c: Color) -> Color { c.opacity(0.4) }
    private func lane20(_ c: Color) -> Color { c.opacity(0.2) }

    // PATTERN CONTROL BLOCK's own button styling (ratified PATTERN-tab-layout ferry, 2026-10-12, §6,
    // literal hexes) — a SEPARATE palette from the LANE-20/40/100 hierarchy above: "selected" still uses
    // LANE-20+LANE-100-border, but "unselected" is a fixed, lane-independent #2a2d34/#aab0ba (not an
    // opacity of the accent), and an ACTIVE EMITTER gets its own third look (solid LANE-100, dark text)
    // specifically so it reads differently from a selected option, per the ferry's own words.
    private let patternUnselectedFill = Color(hex: 0x2A2D34)
    private let patternUnselectedText = Color(hex: 0xAAB0BA)
    private let patternSelectedText = Color(hex: 0xF2F4F7)
    private let patternEmitterActiveText = Color(hex: 0x0D0F14)

    /// Signed value text matching the ferry's own literal examples exactly: "+2" / "−1" (a true minus
    /// sign, U+2212, not the ASCII hyphen Swift's own string interpolation of a negative Int produces) /
    /// a bare "0" with NO sign at all. Used by TILT and OCT — the two fields whose §4 examples show a
    /// sign-free zero ("TILT 0", "OCT 0") alongside signed nonzero values.
    private func euclideousSigned(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "0") }
    // MARK: - The six sliders (usability ferry, 2026-10-12, REARRANGED same day — Paul: "3 vertical on
    // the left (count, hits, velocity) and 3 horizontal on the right (offset, tilt and gate)") — HITS ·
    // STEPS · OFFSET · TILT · GATE · VELOCITY, replacing the "5 pictures"/pad-value/commit/double-tap/
    // 2-finger machinery that used to live here entirely (`euclideousPadValues`/`euclideousAxisNames`/
    // `pointsPerUnit`/`euclideousPadPicture` + its 5 picture functions/`padBaseline`/`commitAxis`/
    // `doubleTapReset`/`applyAllDelta`/`euclideousApplyAllDelta`). The pure per-field logic (range/
    // fraction/value-at-touch/commit/revert/double-tap-default/the value-text formatter) lives in
    // Derivations.swift, reachable by the macOS unit-test target, and is fully orientation-agnostic —
    // only the layout (this function) and the slider's own gesture-bearing View (`EuclideousSlider`,
    // declared earlier in this file) needed to change for the rearrangement.

    /// LEFT: HITS/STEPS/VELOCITY stacked side by side, each a VERTICAL slider spanning the full row
    /// height. RIGHT: OFFSET/TILT/GATE stacked top to bottom, each a HORIZONTAL slider spanning the full
    /// right column's width. The two columns split the row's width in half with an `sp4` gap between
    /// them — no divider line here (unlike `patternControlBlock`'s own ratified 8pt/1pt-divider seam
    /// below this row, which came from a DIFFERENT, separately-ratified spec); nothing in this ask named
    /// one, so a plain gap was the simpler, unassuming choice.
    // RESTORED (2026-10-13, Paul: "I previously requested that three of the six sliders... be
    // horizontal, but this has been undone") — a same-day "exact dimensions" ferry had flattened all 6
    // into one row of equal-width VERTICAL sliders (HITS·TILT·STEPS·OFFSET·VEL·GATE), explicitly
    // retiring this two-column design; that flattening is reverted here per direct instruction, back to
    // the original two-column split (left column vertical, right column horizontal) `EuclideousSlider`
    // was always built to support either way (its own `travelPos`/`frac` are fully orientation-agnostic).
    private func sliderRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, rowHeight: CGFloat) -> some View {
        let leftFields: [EuclideousSliderField] = [.hits, .steps, .velocity]
        let rightFields: [EuclideousSliderField] = [.offset, .tilt, .gate]
        let halfW = max(1, (fullWidth - sp4) / 2)
        let leftSliderW = max(1, (halfW - sp4 * 2) / 3)
        let rightRowH = max(1, (rowHeight - sp4 * 2) / 3)
        // LISTEN/FOLLOW (§5, adversarial-review fix): "HITS, STEPS and TILT show the partner's values at
        // 42% opacity and can't be dragged... VEL, GATE, direction and outputs stay the follower's own."
        // The exact 3-field set this row owns that's affected — OFFSET (this row's own `.offset` field)
        // is explicitly excluded even though it's drawn here, matching "OFFSET stays live" literally.
        let followPartner: EuclidLine? = {
            guard line.listenRhythmMode == .follow else { return nil }
            let p = line.listenRhythmPartnerResolved
            return p >= 0 && p < lines.count ? lines[p] : nil
        }()
        let lockedFields: Set<EuclideousSliderField> = followPartner != nil ? [.hits, .steps, .tilt] : []

        func verticalSlider(_ field: EuclideousSliderField) -> some View {
            EuclideousSlider(
                field: field, line: line, accent: accent, width: leftSliderW, height: rowHeight, horizontal: false,
                onCommit: { mutate in edit(idx, mutate) },
                onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(field, &$0) } },
                onRevertToEuclid: { edit(idx) { $0.customHits = nil } },
                displayOverrideLine: lockedFields.contains(field) ? followPartner : nil,
                listenFollowLocked: lockedFields.contains(field))
        }
        func horizontalSlider(_ field: EuclideousSliderField) -> some View {
            EuclideousSlider(
                field: field, line: line, accent: accent, width: halfW, height: rightRowH, horizontal: true,
                touchPad: 2,   // 2026-10-14 ferry Fix 3: 2pt into each neighbouring sp4(4pt) gap, no dead strip
                onCommit: { mutate in edit(idx, mutate) },
                onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(field, &$0) } },
                onRevertToEuclid: { edit(idx) { $0.customHits = nil } },
                displayOverrideLine: lockedFields.contains(field) ? followPartner : nil,
                listenFollowLocked: lockedFields.contains(field))
        }

        return HStack(spacing: sp4) {
            HStack(spacing: sp4) { ForEach(leftFields, id: \.rawValue) { field in verticalSlider(field) } }
                .frame(width: halfW, height: rowHeight)
            VStack(spacing: sp4) { ForEach(rightFields, id: \.rawValue) { field in horizontalSlider(field) } }
                .frame(width: halfW, height: rowHeight)
        }
        .frame(width: fullWidth, height: rowHeight)
    }

    // MARK: - Per-lane tab row + content (Paul 2026-10-07, §2.6)

    private func laneTabRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(EuclideousLaneTab.allCases, id: \.rawValue) { t in
                let sel = (idx < laneTab.count ? laneTab[idx] : .rhythm) == t
                // DOT (RIFF/NOTES SPLIT, third same-day ferry §1): RIFF/NOTES/MASK each carry their own
                // dot again — filled (lane-coloured) while that layer is genuinely ON, hollow while off.
                // RHYTHM never shows one (always "on"). All three share ONE rendering (below), replacing
                // MASK's own previously-bespoke inline Circle so the three tabs can't drift onto two
                // different dot looks.
                let dotOn: Bool? = {
                    switch t {
                    case .rhythm: return nil
                    case .riff: return line.riffOnResolved
                    case .notes: return line.notesOnResolved && (line.litNotesResolved != 0 || line.topLitResolved || line.top2LitResolved)
                    // LISTEN (§1): "filled... when ANY row has a lit button, hollow otherwise."
                    case .listen: return line.listenRhythmMode != nil || line.listenPitchMode != nil || line.listenLevelMode != nil
                    }
                }()
                // VIEWS (2026-10-13 "lane card, exact dimensions" ferry, literal): "Labels are 11pt heavy
                // with 1pt tracking, centred. The selected tab is TEXT, the others MUTED. A 2pt underline
                // runs along each tab's bottom edge, the full width of the tab: LANE-100 for the selected
                // tab, CHIP for the others." — a real change from before: EVERY tab now shows an underline
                // (CHIP when unselected, not invisible), not just the active one.
                HStack(spacing: 5) {
                    Text(t.label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
                        .foregroundColor(sel ? patternSelectedText : patternUnselectedText)
                        .lineLimit(1)
                    if let on = dotOn {
                        // LANE-100 — 7×7, filled + a matching 1pt ring when on; a hollow 1.5pt MUTED ring
                        // when off (so the dot's own presence still tells "this tab HAS an on/off state"
                        // even while that state is currently off).
                        Circle().fill(on ? lane100(accent) : Color.clear)
                            .overlay(Circle().stroke(on ? lane100(accent) : Color(hex: 0xAAB0BA), lineWidth: on ? 1 : 1.5))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center).frame(height: rowH)
                .overlay(Rectangle().fill(sel ? lane100(accent) : patternUnselectedFill).frame(height: 2), alignment: .bottom)
                .overlay {
                    // FOURFOLD §7.1: a pulse/trace for an output this lane feeds, while the card is showing another tab —
                    // the ring goes around the RHYTHM tab ("your OUT toggles are in here"). Visual only.
                    if t == .rhythm, let c = outputCue(forLane: idx), c.cue == .ringRhythmTab {
                        EuclideousOutputCueRing(kind: .tab, held: c.held, reduceMotion: reduceMotion).id(c.token)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if idx < laneTab.count { laneTab[idx] = t } }
                // A ringed cell is raised above its siblings so the ring (which grows past the cell) is never painted over.
                .zIndex(t == .rhythm && outputCue(forLane: idx)?.cue == .ringRhythmTab ? 1 : 0)
            }
        }
    }

    /// LAYOUT (PATTERN-tab-layout ferry, ratified 2026-10-12, literal §1: "the content is 84pt tall: two
    /// lines of 38pt with a 4pt gap between them"): `contentAreaH` is the WHOLE space this tab's content
    /// has to work with; PATTERN gives its one fixed 80pt block (`patternControlBlock` — RATE/DIRECTION/
    /// INV/emitters) and stretches the 6 sliders into whatever's left. MASK has no equivalent fixed-vs-
    /// stretchy split today (`maskLine2` is its one fixed row), so its step-bar (`maskCometRow`) simply
    /// grows to fill everything PATTERN's own fixed block would have otherwise sat above.
    @ViewBuilder private func tabContent(_ idx: Int, _ line: EuclidLine, _ tab: EuclideousLaneTab, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        switch tab {
        case .rhythm:
            // Exact-dimensions ferry (2026-10-13): the control block is 80pt (two 38pt rows + 4pt
            // gap), not 84 — sliders now get the full 118pt the spec's own table gives them (at
            // contentAreaH=202: 202−80−4=118, matching the table exactly).
            let patternBlockH: CGFloat = 80
            let sliderH = max(1, contentAreaH - patternBlockH - sp4)
            VStack(spacing: sp4) {
                sliderRow(idx, line, accent, fullWidth: fullWidth, rowHeight: sliderH)
                patternControlBlock(idx, line, accent, fullWidth: fullWidth)
            }
        case .riff:
            riffTabContent(idx, line, accent, contentAreaH: contentAreaH, fullWidth: fullWidth)
        case .notes:
            notesTabContent(idx, line, accent, contentAreaH: contentAreaH, fullWidth: fullWidth)
        case .listen:
            listenTabContent(idx, line, accent, contentAreaH: contentAreaH, fullWidth: fullWidth)
        }
    }

    /// The 3 DIRECTION buttons, equal width (PATTERN-tab-layout ferry §4: "the three direction buttons
    /// <, ><, > at equal width"). Left-to-right: BACKWARDS · PING-PONG · FORWARDS, glyphs "<" / "><" /
    /// ">" (the SAME convention the regular BUILD-page EUCLID editor's own DIRECTION control already
    /// uses). SELECTED = LANE-20 fill, 1pt LANE-100 border, #f2f4f7 text; UNSELECTED = #2a2d34 fill,
    /// #aab0ba text (ferry §6, applied uniformly across this whole block, not just here).
    private func directionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        let order: [(EuclidDir, String)] = [(.bkw, "<"), (.pingpong, "><"), (.fwd, ">")]
        return HStack(spacing: 3) {   // exact-dimensions ferry: 3 equal buttons, 3pt gaps (was sp4=4)
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.direction = dir } }
            }
        }
    }

    /// INV (ferry §4/§6, literal): "INV replaces the HIT/GAPS pair as one toggle on the same parameter:
    /// off = HIT, on = GAPS. Its behaviour and display are unchanged [from GAPS's own]." Same persisted
    /// field (`patternMiss`), same semantics — only the control SHAPE changed, from two mutually-
    /// exclusive buttons to one toggle.
    /// PER-LANE RESET BOX (2026-10-14 ferry §2, literal placement): "Reset box at the start of each row...
    /// shows the lane's reset: value over the unit STEP/STEPS. OFF shows OFF, with no unit." Lives on the
    /// SEQUENCER panel's own LANES tab now — a same-session self-audit against the ferry's raw text found
    /// the first build had placed this on the RHYTHM tab instead (a judgment call that wasn't actually
    /// warranted; the ferry gives an exact spot). Tap opens the anchored popup (`resetPopupCard`, mirroring
    /// `keyPopupCard`'s own anchored-not-centred idiom) with OFF/1/2/4/8.
    /// 2026-10-15 ferry ("per-step restart points on the LANES tab" §3/§4.2/§4.5/§4.6/§4.9): REPLACES the
    /// old OFF/1/2/4/8-only label with `euclideousRestartLabel`'s general value/unit pair, and the old plain
    /// tap-opens-popup action with a press-vs-hold split — there was no separate long-press action on this
    /// box before (confirmed by reading the prior build: its only gesture was the `.onTapGesture` below), so
    /// nothing is being replaced out from under an existing hold behaviour. Touch-down enters restart-edit
    /// mode immediately (§4.2, "at once, no delay, no animation") via `DragGesture(minimumDistance: 0)` — a
    /// plain `.onTapGesture`/`LongPressGesture` can't do this: SwiftUI only resolves either of those AFTER a
    /// movement/duration threshold, but §4.2 wants the FIRST touch sample to count. Release then decides, in
    /// retrospect, whether the whole press was "a quick tap" (§4.6: <300 ms AND the mask is unchanged from
    /// touch-down) — comparing the live resolved mask against the one captured at touch-down, not a separate
    /// dirty flag, so a toggle added on some other path can't silently fall out of sync with this check.
    private func sequencerResetBox(_ idx: Int, width: CGFloat, height: CGFloat, cellW: CGFloat, gap: CGFloat) -> some View {
        let mask = idx < lines.count ? lines[idx].restartMaskResolved : 0
        let len = idx < lines.count ? max(1, min(8, lanesSeq.len)) : 8
        let label = euclideousRestartLabel(mask: mask, loopSteps: len)
        let accent = laneAccents[idx % laneAccents.count]
        let editing = restartEditLanes.contains(idx)
        // §6: "while open, the anchored RESET box shows the selected-choice style" — a THIRD look, distinct
        // from both the plain idle chip and the solid held-fill (§5), for when the popover is open via a
        // quick tap (by which point the hold itself has already ended, so `editing` is false).
        let popoverOpenHere = resetPopupLane == idx
        return VStack(spacing: 1) {
            Text(label.value).font(.system(size: label.unit == "OFF" ? 13 : 14, weight: .heavy, design: .monospaced))
                .foregroundColor(editing ? Color(hex: 0x0D0F14) : Color(hex: 0xF2F4F7))
            Text(label.unit).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(editing ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(editing ? lane100(accent) : (popoverOpenHere ? lane20(accent) : Color(hex: 0x2A2D34))))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(editing ? Color.clear : lane100(accent), lineWidth: 1.5))
        .contentShape(Rectangle())
        .background(GeometryReader { geo in
            // Same idiom as the header's key-pill publisher — the SAME named coordinate
            // space the surrounding ZStack declares (`.coordinateSpace(name: "euclideousXY")`), not
            // `.global`, since the popup's own `.position(x:y:)` positions within THAT local space.
            Color.clear.preference(key: EuclideousResetChipFramePreferenceKey.self,
                                    value: [idx: geo.frame(in: .named("euclideousXY"))])
        })
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !restartEditLanes.contains(idx) {
                        restartEditLanes.insert(idx)
                        restartEditTouchDown[idx] = Date()
                        restartEditOriginalMask[idx] = mask
                    }
                }
                .onEnded { value in
                    let touchDown = restartEditTouchDown[idx]
                    let original = restartEditOriginalMask[idx] ?? mask
                    restartEditLanes.remove(idx)
                    restartEditTouchDown[idx] = nil
                    restartEditOriginalMask[idx] = nil
                    // ONE-THUMB SHORTCUT (§4.4): the SAME finger slid off the box and lifted over a step of
                    // this lane — toggle that step's mark. Hit-tested with the grid's own cellW/gap (passed
                    // in by the caller, the SAME values it draws the cells with — the two can never silently
                    // disagree because there's only the one source for them).
                    if let step = euclideousRestartStepHitTest(localX: value.location.x, labelW: width, gap: gap,
                                                                cellW: cellW, columns: 8) {
                        edit(idx) { $0.restartMask = $0.restartMaskResolved ^ (1 << step) }
                    }
                    // QUICK TAP (§4.6): short press, mask unchanged by the time it released (neither a hand
                    // edit nor the one-thumb toggle above moved it) → the presets popover. A longer press, or
                    // any edit during the press (including the one-thumb toggle just above, since that WOULD
                    // have changed the live mask before this comparison runs), never opens it.
                    let shortEnough = touchDown.map { Date().timeIntervalSince($0) < 0.3 } ?? false
                    let liveMask = idx < lines.count ? lines[idx].restartMaskResolved : mask
                    if shortEnough && liveMask == original {
                        resetPopupLane = idx
                    }
                }
        )
        // NO `.euclideousHelp` here, unlike most controls on this page — its own doc comment scopes it
        // DELIBERATELY to "a plain `.onTapGesture`-only control" and excludes every other drag/pinch-based
        // control for the same reason (the XY pads, the mask's drag-to-adjust chips): a 0.5s+ hold is
        // exactly this control's OWN core interaction (§4.7), so the help bubble's competing
        // `.onLongPressGesture` would race the restart-hold `DragGesture` on the identical touch instead of
        // layering safely alongside a plain tap. Found on a later adversarial-review pass, not caught when
        // this control's gesture was first changed from a plain tap to a hold. Discovery still exists
        // without it — the popover's own "HOLD RESET + TAP STEPS = CUSTOM" hint row (§6) and the
        // accessibility hint below.
        .accessibilityLabel("Lane \(idx + 1) restarts: \(euclideousRestartAccessibleLabel(mask: mask, loopSteps: len))")
        .accessibilityHint("Double-tap for presets")
    }
    private func invButton(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        let on = line.patternMissResolved
        return Text("INV").font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? patternSelectedText : patternUnselectedText)
            .frame(width: 40, height: rowH)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { edit(idx) { $0.patternMiss = !on } }
            .euclideousHelp("Play on the empty steps instead of the hits")
            .accessibilityLabel("Invert")
    }

    /// EMITTER TOGGLES A–D, equal width (ferry §5/§6/§7). A SIMPLIFICATION from the old `laneOutRow`'s
    /// THREE visual states down to the ferry's own TWO, flagged not silently dropped: "active" (routed
    /// AND this bus's MAIN OUT gate on) is solid LANE-100/#0d0f14 text; anything else — not routed, OR
    /// routed but the main gate is off — now reads as a plain unselected button (#2a2d34/#aab0ba). The
    /// old dashed/hollow "routed but muted" ring and the trailing "NO OUTPUT" warning text are DROPPED —
    /// the ferry's own button-styling rule names only two emitter states, and this fixed 40pt-tall row
    /// has no room left for a third visual language or trailing warning text the way the old, taller/
    /// wider `laneOutRow` (circular dots + an "OUT" caption + a warning label) did.
    private func laneOutRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        let mask = line.emitterMask ?? 0
        let names = ["A", "B", "C", "D"]
        return HStack(spacing: 3) {   // exact-dimensions ferry: 4 equal buttons, 3pt gaps (was sp4=4)
            ForEach(0..<4, id: \.self) { b in
                let routed = (mask >> UInt8(b)) & 1 != 0
                let mainOn = (mainOutMask >> UInt8(b)) & 1 != 0
                // FERRY (2026-10-14 §4): ratified 7 Oct as "routed but main-off draws dashed/hollow" — never
                // built; the chip collapsed routed-but-main-off to the SAME look as not-routed (both read
                // the one bool `routed && mainOn`). The ROUTING itself was always correct (confirmed: the
                // chip turns green the instant main A comes back on) — only the drawing had no 3rd state.
                let style = euclideousLaneOutChipStyle(routed: routed, mainOn: mainOn)
                // ROUND (Paul 2026-10-14: "like the buttons on top of the page, strictly no more space") —
                // mirrors `mainOutToggle`'s own plain `Circle()` fill/stroke exactly; the OUTER footprint
                // (`.frame(maxWidth: .infinity).frame(height: rowH)`, the tap target) is BYTE-IDENTICAL to
                // before — only the drawn shape inside it shrinks from a cell-filling RoundedRectangle to a
                // true circle sized to `rowH` (the row's own existing height, never larger), centred in the
                // unchanged cell, so the row's total width/height can't grow.
                let textColor: Color = {
                    switch style {
                    case .filled: return patternEmitterActiveText
                    case .hollowDashed: return lane100(accent)   // §4: "letter in the lane colour" (my interpretation, disclosed)
                    case .plain: return patternUnselectedText
                    }
                }()
                Text(names[b]).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: rowH, height: rowH)
                    .background(Circle().fill(style == .filled ? lane100(accent) : (style == .plain ? patternUnselectedFill : Color.clear)))
                    .overlay(
                        Group {
                            switch style {
                            case .filled: Circle().stroke(lane100(accent), lineWidth: 1)
                            // §4: "dashed ring in the lane colour, 2pt wide, 3pt dashes with 3pt gaps" (literal).
                            case .hollowDashed: Circle().stroke(lane100(accent), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                            case .plain: EmptyView()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .overlay {
                        // FOURFOLD §7.1: the ring around THIS OUT circle (2pt, inner edge sp4 outside it → diameter + 10)
                        // when the output ring just tapped/held is this one and this lane is routed to it. Visual only.
                        if let c = outputCue(forLane: idx), c.cue == .ringOutCircle, c.output == b {
                            EuclideousOutputCueRing(kind: .circle, held: c.held, reduceMotion: reduceMotion)
                                .frame(width: rowH + 10, height: rowH + 10).id(c.token)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
                    // FOURFOLD §7.1: the cue ring grows past its circle into the 3pt gaps. Later HStack siblings paint ABOVE
                    // earlier siblings' overlays, so a ringed circle is raised above its neighbours or the next circle's fill
                    // would cover the ring's far side.
                    .zIndex({ if let c = outputCue(forLane: idx), c.cue == .ringOutCircle, c.output == b { return 1.0 }; return 0.0 }())
                    .accessibilityLabel("Emitter \(names[b])\(style == .hollowDashed ? ", main output off" : "")")
            }
        }
    }

    /// Draws one feel glyph — ♩ (U+2669 QUARTER NOTE) for straight, ♩+"." for dotted, ♩+a raised "3" for
    /// triplet (ferry §3, literal). Deliberately NOT `design: .monospaced` — JetBrains Mono (this page's
    /// own monospaced font elsewhere) has no glyph for U+2669; the ferry's own explicit warning is "it
    /// must never render as a missing-glyph box," so this uses the plain system font instead, whose own
    /// Unicode fallback cascade (Apple Symbols et al. on iOS) covers the character. UNVERIFIED ON DEVICE —
    /// this environment cannot render a font to confirm the glyph actually appears rather than a tofu box.
    @ViewBuilder private func feelGlyph(_ feel: Int) -> some View {
        // Exact-dimensions ferry (2026-10-13): "down from 17pt and 12pt in the earlier rate
        // instructions, so it fits the 24.67pt height" — 15pt note glyph, 11pt mark.
        switch feel {
        case 0: Text("♩").font(.system(size: 15))
        case 1: HStack(spacing: 0) { Text("♩").font(.system(size: 15)); Text(".").font(.system(size: 15, weight: .bold)) }
        default:
            HStack(alignment: .top, spacing: 0) {
                Text("♩").font(.system(size: 15))
                Text("3").font(.system(size: 11, weight: .bold)).baselineOffset(7)
            }
        }
    }

    /// THE PATTERN CONTROL BLOCK (ratified PATTERN-tab-layout ferry, 2026-10-12; numbers corrected to
    /// the 2026-10-13 exact-dimensions ferry) — a fixed 80pt-tall, two-line layout: LEFT HALF = RATE
    /// (a 3×2 division grid + a 36pt feel column, both reading/writing
    /// the ONE existing `EuclidLine.rate: ArpRate?` field via `euclideousRateDivisionFeel`/
    /// `euclideousRateFromDivisionFeel`, Derivations.swift); RIGHT HALF top line = DIRECTION + INV,
    /// bottom line = the 4 emitter toggles. Replaces the old HIT/GAPS+RATE-popup row and the DIRECTION+
    /// OUTPUT row entirely — "change nothing else: not the sliders, the step row or the tab row."
    ///
    /// AUTO/UNSET RATE, a judgment call flagged rather than silently resolved: the ferry's own grid has
    /// no 19th "follow the machine rate" cell the way the old RATE pop-up's separate "— (MACHINE RATE)"
    /// row did — every cell here is a concrete division×feel. Read literally, tapping any cell always
    /// commits an EXPLICIT rate (exactly as every one of the old popup's own grid-cell taps already did —
    /// only that popup's one separate nil-setting row offered a way back to "auto," and nothing in this
    /// ferry describes an equivalent control existing in the new layout). So a lane whose `rate` is still
    /// nil keeps reading as nil (and therefore still audibly follows the instrument's own step rate,
    /// unchanged) until the user actually taps a cell — the grid just HIGHLIGHTS the nearest division/
    /// feel to what's currently in effect (the same `autoRate`-nearest-match heuristic the old row-based
    /// display already used) rather than writing anything on render. This is the most literal reading
    /// consistent with the ferry's own acceptance line "a preset saved before this change loads with the
    /// same rate" — an AUTO lane's stored nil survives untouched unless the user deliberately picks a cell.
    private func patternControlBlock(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat) -> some View {
        // Exact-dimensions ferry (2026-10-13): rowH 40→38 (two 38pt rows + 4pt gap = 80pt block,
        // matching the 118(sliders)+4(gap)+80(this block)=202 tab-content height exactly); halfW's
        // divider footprint corrected from 8 (a bare 1pt rule + 3.5pt either side) to 17 (1pt rule +
        // 8pt padding either side) — both halves land at the spec's own 154.5pt.
        let rowH: CGFloat = 38, gap: CGFloat = 4, blockH = rowH * 2 + gap
        let halfW = max(1, (fullWidth - 17) / 2)
        let feelColW: CGFloat = 36
        let gridGap: CGFloat = 3   // horizontal gap: across the 3 rate columns, and grid↔feel column
        let gridW = max(1, halfW - gridGap - feelColW)
        let cellW = max(1, (gridW - gridGap * 2) / 3)
        let cellH = max(1, (blockH - gap) / 2)   // vertical gap between the grid's 2 rows is 4pt (`gap`), not gridGap(3)
        let feelBtnH = max(1, (blockH - gridGap * 2) / 3)   // feel buttons stack 3pt apart (gridGap), not `gap`

        let autoRate = ArpRate.allCases.min(by: { abs($0.beats - clock.stepBeats) < abs($1.beats - clock.stepBeats) }) ?? .r1_16
        let resolved = line.rate ?? autoRate
        let (curDiv, curFeel) = euclideousRateDivisionFeel(resolved)
        let divisionLabels = ["1/1", "1/2", "1/4", "1/8", "1/16", "1/32"]
        let feelLabels = ["Straight", "Dotted", "Triplet"]
        func setRate(division: Int? = nil, feel: Int? = nil) {
            edit(idx) { $0.rate = euclideousRateFromDivisionFeel(division: division ?? curDiv, feel: feel ?? curFeel) }
        }
        // LISTEN/FOLLOW (§5, adversarial-review fix): "the six rate cells become multipliers: ÷8 ÷4 ÷2
        // on the top row, ×1 ×2 ×4 on the bottom row... a multiplier whose result would fall outside
        // 1/1-1/32 is greyed... the three feel cells show the partner's feel at 42% opacity."
        let followPartner: EuclidLine? = {
            guard line.listenRhythmMode == .follow else { return nil }
            let p = line.listenRhythmPartnerResolved
            return p >= 0 && p < lines.count ? lines[p] : nil
        }()
        let multLabels: [[String]] = [["÷8", "÷4", "÷2"], ["×1", "×2", "×4"]]
        let multExponents: [[Int]] = [[-3, -2, -1], [0, 1, 2]]
        func multValid(_ mult: Int, partnerBeats: Double) -> Bool {
            let result = partnerBeats * pow(2.0, Double(-mult))
            return result >= ArpRate.r1_32.beats - 0.0001 && result <= ArpRate.r1_1.beats + 0.0001
        }

        let rateHalf = HStack(spacing: gridGap) {
            if let partner = followPartner {
                let partnerBeats = partner.rate?.beats ?? autoRate.beats
                let curMult = line.listenFollowMultResolved
                VStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: gridGap) {
                            ForEach(0..<3, id: \.self) { col in
                                let m = multExponents[row][col]
                                let on = m == curMult
                                let valid = multValid(m, partnerBeats: partnerBeats)
                                Text(multLabels[row][col]).font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundColor(!valid ? patternUnselectedText.opacity(0.4) : (on ? patternSelectedText : patternUnselectedText))
                                    .frame(width: cellW, height: cellH)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(on && valid ? lane20(accent) : patternUnselectedFill))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on && valid ? lane100(accent) : Color.clear, lineWidth: 1))
                                    .contentShape(Rectangle())
                                    .onTapGesture { if valid { edit(idx) { $0.listenFollowMult = m } } }
                            }
                        }
                    }
                }
                VStack(spacing: gridGap) {
                    ForEach(0..<3, id: \.self) { f in
                        let on = f == euclideousRateDivisionFeel(partner.rate ?? autoRate).1
                        feelGlyph(f)
                            .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                            .frame(width: feelColW, height: feelBtnH)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? lane20(accent) : patternUnselectedFill))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                            .accessibilityLabel(feelLabels[f])
                    }
                }
                .opacity(0.42)
                .allowsHitTesting(false)
            } else {
                VStack(spacing: gap) {   // 4pt between the 2 rate-grid rows (ferry rule 2), not the 3pt column gap
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: gridGap) {
                            ForEach(0..<3, id: \.self) { col in
                                let d = row * 3 + col
                                let on = d == curDiv
                                Text(divisionLabels[d]).font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                                    .frame(width: cellW, height: cellH)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                                    .contentShape(Rectangle())
                                    .onTapGesture { setRate(division: d) }
                            }
                        }
                    }
                }
                VStack(spacing: gridGap) {
                    ForEach(0..<3, id: \.self) { f in
                        let on = f == curFeel
                        feelGlyph(f)
                            .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                            .frame(width: feelColW, height: feelBtnH)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? lane20(accent) : patternUnselectedFill))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { setRate(feel: f) }
                            .accessibilityLabel(feelLabels[f])
                    }
                }
            }
        }
        .frame(width: halfW, height: blockH)

        let outHalf = VStack(spacing: gap) {
            HStack(spacing: 3) {   // exact-dimensions ferry: 3pt between the direction group and INV
                directionRow(idx, line, accent, rowH: rowH).frame(maxWidth: .infinity)
                invButton(idx, line, accent, rowH: rowH)
                // RESET moved to the sequencer panel's own LANES tab (2026-10-14 ferry §2 literally places
                // it there, at the start of each row) — the RHYTHM-tab placement here was a same-session
                // judgment call that didn't survive a direct re-check against the ferry's own text; DIRECTION
                // absorbs the freed width via its existing `.frame(maxWidth: .infinity)`.
            }
            laneOutRow(idx, line, accent, rowH: rowH)
        }
        .frame(width: halfW, height: blockH)

        return HStack(spacing: 0) {
            rateHalf
            Rectangle().fill(Color(hex: 0x2A2D34)).frame(width: 1).padding(.horizontal, 8)
            outHalf
        }
        .frame(width: fullWidth, height: blockH)
    }

    // RIFF TAB RETIRED (ferry 2026-10-10 §1.2) — `riffDirGrid`/`riffTabButton`/`euclideousNextOnRest`/
    // `riffDirPopupCard` deleted entire; confirmed by grep to have no remaining callers once `tabContent`'s
    // `.riff` case was removed. Direction/FREE-LOCK/INVERT/ON-REST selection now lives inline in the melody
    // pop-up's own WALK section below. `riffDirShortLabel` (PEND/PING/RAND short labels) is KEPT — still used
    // by the melody pop-up's DIRECTION row and by `noteViewLabelItems`'s own RIFF summary item.
    /// Short direction labels (PEND/PING/RAND) — scoped to THIS page only, never touching the shared
    /// `RiffDir.displayLabel` enum (that enum also serves the unrelated, regular chainable RIFF processor
    /// elsewhere in the app).
    private func riffDirShortLabel(_ d: RiffDir) -> String {
        switch d {
        case .forward: return "FWD"; case .reverse: return "REV"; case .pendulum: return "PEND"
        case .pingpong: return "PING"; case .random: return "RAND"; case .drunk: return "DRUNK"
        }
    }
    /// §3.3's own help-text style (plain English, no jargon, under 60 characters) applied to each WALK
    /// direction — completes "Walk the riff <phrase>."
    private func riffDirHelpPhrase(_ d: RiffDir) -> String {
        switch d {
        case .forward: return "forward each time"
        case .reverse: return "backward each time"
        case .pendulum: return "forward, then back, each end once"
        case .pingpong: return "forward, then back, each end twice"
        case .random: return "to a random step each time"
        case .drunk: return "one step at a time, randomly"
        }
    }
    private func riffOnRestHelpPhrase(_ r: EuclidRiffOnRest) -> String {
        switch r {
        case .skip: return "On a riff rest, play nothing"
        case .fill: return "On a riff rest, play this lane's own note"
        case .tie: return "On a riff rest, hold the previous note"   // §3.3's own literal REST TIE example
        }
    }

    // MARK: - MELODY TAB (Paul 2026-10-13 ferry, "MELODY tab on the lane cards") — every setting the old
    // anchored pop-up held (note choice, octave, all riff settings) now lives in-card, on its own tab,
    // built from the same `melodyButton`/`melodyStepper` visual language that pop-up already established
    // (both kept — reused by the new tab content below, not superseded). `euclideousMelodyAnchor`/
    // `melodyPointer` (the pop-up's own anchoring geometry + its triangular notch) are retired along with
    // it — a lane card tab needs neither.
    /// §4.1/§4.2 colour hierarchy, followed literally even though it diverges slightly from this page's
    /// own pre-existing `Color.white.opacity(0.06)` unselected-button fill elsewhere (`directionRow`/
    /// `ioSourceRow`) — this section explicitly cites "the colour-hierarchy ferry" as its authority, so
    /// its own exact hex is used as given: selected = LANE-20 fill + 1pt LANE-100 border + white text;
    /// unselected = literal #2A2D34 fill + grey text. 40pt tall (§4.4).
    /// `fontSize`/`cornerRadius` (2026-10-14 ferry): the RIFF tab's own 3 button rows each use a different
    /// size/radius (modes row 11pt/r7, direction row 12pt/r7) — both default to this button's original 10pt/
    /// r6, so every OTHER call site across this page (TOP/TOP2/INV/LOCK/HIT/STEP/SKIP/FILL/TIE elsewhere) is
    /// byte-identical. Text colours moved to the ferry's own exact hex ("ON: text #f2f4f7... OFF: text
    /// #aab0ba") — visually near-identical to the prior `.white`/`.white.opacity(0.55)`, but now the same
    /// literal constant this page already uses everywhere else (e.g. the NOTES VEL bar), not a separate guess.
    @ViewBuilder private func melodyButton(_ label: String, on: Bool, accent: Color, height: CGFloat = 40, fontSize: CGFloat = 10, cornerRadius: CGFloat = 6, help: String? = nil, action: @escaping () -> Void) -> some View {
        let base = Text(label).font(.system(size: fontSize, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
            .lineLimit(1)   // §4.6: nothing under 10pt — truncate, never shrink (no .minimumScaleFactor call at all, SwiftUI's own default already never scales below 1.0)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(on ? lane20(accent) : Color(hex: 0x2A2D34)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        if let help { base.euclideousHelp(help) } else { base }
    }
    /// One chip (default 69.5×34, `width` overridable — 2026-10-14 ferry widens the RIFF tab's own 4 steppers
    /// to 79.25 each so the row runs full width, which also widens the decorative end-zones 14→18pt per the
    /// ferry's own exact "‹ zone 18 | centre 43.25 | › zone 18" breakdown at that width): ‹/› glyphs in the end
    /// zones (decorative), name(10pt) over value(14pt) centred, 2pt apart. Tapping the LEFT HALF of the whole
    /// chip decreases; the RIGHT HALF increases — not just the glyph zones.
    @ViewBuilder private func melodyStepper(_ label: String, value: Int, range: ClosedRange<Int>, unit: String? = nil, width: CGFloat = 69.5, help: String? = nil, onChange: @escaping (Int) -> Void) -> some View {
        let w: CGFloat = width, h: CGFloat = 34, arrowZone: CGFloat = 18
        let base = ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34))
            HStack(spacing: 0) {
                Text("‹").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    .frame(width: arrowZone, height: h)
                VStack(spacing: 2) {
                    Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    Text(unit != nil ? "\(euclideousSigned(value)) \(unit!)" : "\(value)")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)   // §4.6: truncate, never shrink — no .minimumScaleFactor
                }
                .frame(maxWidth: .infinity)
                Text("›").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    .frame(width: arrowZone, height: h)
            }
        }
        .frame(width: w, height: h)
        .overlay(
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { onChange(max(range.lowerBound, value - 1)) }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { onChange(min(range.upperBound, value + 1)) }
            }
        )
        if let help { base.euclideousHelp(help) } else { base }
    }
    private func melodySectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
    }
    /// §2.2's own exact note names — "LOWEST, ALL" repeated twice in the ferry's own worked examples,
    /// matching the already-established `.low`→"LOWEST" precedent (NOTE VIEW's own label, this same
    /// file) — not a blanket rename, just the names the ferry literally gives for each case.
    private func melodyNoteSelLabel(_ s: EuclidNoteSel) -> String {
        switch s {
        case .low: return "LOWEST"; case .high: return "HIGHEST"
        case .bottom2: return "BOTTOM TWO"; case .top2: return "TOP TWO"
        case .n1: return "1"; case .n2: return "2"; case .n3: return "3"; case .n4: return "4"
        case .n5: return "5"; case .n6: return "6"; case .n7: return "7"; case .n8: return "8"
        default: return s.rawValue   // ALL, CYCLE
        }
    }
    // melodyModeSection/melodyNoteSection/melodyWalkSection/melodyPlacementSection/melodyPopupCard
    // REMOVED (Paul 2026-10-13 ferry, "MELODY tab on the lane cards") — superseded by the new
    // MELODY tab content below (`melodyNotesRow`/`melodyOctaveRow`/`melodyRiffBlock` and its own
    // sub-rows), which reuses `melodyButton`/`melodyStepper` above verbatim rather than re-deriving the
    // same visual language a second time. CORRECTION (2026-10-13 adversarial review): `melodySectionTitle`/
    // `melodyNoteSelLabel` are NOT actually reused below — that was a false claim left over from an
    // earlier draft. The new Notes row shows bare rank numbers (N1...N8) plus TOP/TOP2 on the Octave row;
    // the old pop-up's full ALL/LOW/BOTTOM2/CYCLE pick set (and their descriptive names) has no reachable
    // UI slot in the new tab at all — a real scope narrowing versus the old pop-up, disclosed here rather
    // than silently absorbed, and flagged for Paul's own call once the literal MELODY-tab spec (promised,
    // not yet received) confirms whether that's intentional. `melodySectionTitle`/`melodyNoteSelLabel`
    // are left in place, unused, rather than deleted — likely needed again if that spec restores them.

    // MARK: - MELODY TAB CONTENT (Paul 2026-10-13, TWO ferries same day) — Notes row (8 equal buttons) ·
    // Octave row (segmented −2…+2 + TOP/TOP2) · Riff block (strip + WALK/MODES/VALUES rows).
    //
    // SUPERSEDED BY THE SECOND, SAME-DAY "lit notes plus the riff" FERRY — the FIRST ferry's own
    // "Behaviour rule 1: the mode is the selection" (one choice at a time, NOTE xor RIFF) is EXPLICITLY
    // RETIRED: "lit notes" (any of the 8 rank buttons + TOP/TOP2) and "the riff" (on/off) are now two
    // INDEPENDENT, ADDITIVE layers — both can sound on the same hit. Tapping a note/TOP/TOP2 button only
    // ever toggles ITS OWN bit (`litNotes`/`topLit`/`top2Lit`); tapping the RIFF strip or a WALK direction
    // button only ever toggles `riffOn`; every OTHER riff control (INV/LOCK/ADV/REST/LEN/NUDGE/STRIDE/
    // TRANS) changes its own setting live and never touches `riffOn`. The riff rows (WALK/MODES/VALUES,
    // NOT the strip itself, NOT the notes/octave rows) dim to 42% only while the riff is off — notes stay
    // fully live/visible regardless (rule 7: "Lit notes never dim them").
    private static let rankNoteSel: [EuclidNoteSel] = [.n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8]
    /// LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry) — "This amends [the MELODY tab]
    /// instructions... replaces: the one-choice-at-a-time behaviour (Behaviour 1–3)." The 8 rank buttons +
    /// TOP/TOP2 are now INDEPENDENT toggles (`litNotes`/`topLit`/`top2Lit`), additive with the riff (also
    /// now a plain on/off, `riffOn`) rather than a single mutually-exclusive pick — superseding every
    /// `noteSel`/`melodyMode`-write below.
    ///
    /// The rank(s) TOP/TOP2 currently resolve to against the live pool, mirroring `riffResolve`'s own
    /// highest/second-highest formula exactly (Router.swift's new lit-notes layer) so the ring below can
    /// never mark a button the engine wouldn't actually strike. `poolCount` is already the RAW (pre-octave-
    /// extension) count — the one `riffLivePool` already reports (Router.swift's own fill reads
    /// `laneNotes(0)` before extension).
    private func euclideousHighPickRanks(topLit: Bool, top2Lit: Bool, poolCount: Int) -> Set<Int> {
        guard poolCount > 0, topLit || top2Lit else { return [] }
        var s: Set<Int> = []
        if topLit { s.insert(poolCount) }
        if top2Lit { s.insert(poolCount); s.insert(max(1, poolCount - 1)) }
        return s
    }
    /// A small ROTATED category label (2026-10-13 ferry §4: "the vertical ADV and REST labels") — a plain
    /// SwiftUI rotate-then-constrain idiom (`.fixedSize()` so the un-rotated text lays out at its natural
    /// width first, THEN the rotation is applied, THEN the outer frame clips to the narrow column it now
    /// occupies) shared by the small in-row labels (ADV/REST) and the full-height RIFF strip below, so the
    /// two can't drift onto two different vertical-text techniques.
    private func melodyVerticalLabel(_ s: String, size: CGFloat = 9, color: Color = Color(hex: 0x8A909A), width: CGFloat = 12, kerning: CGFloat = 0) -> some View {
        Text(s).font(.system(size: size, weight: .heavy, design: .monospaced)).foregroundColor(color).kerning(kerning)
            .fixedSize().rotationEffect(.degrees(-90)).frame(width: width).frame(maxHeight: .infinity)
    }
    /// VALUES row: four stepper chips, LEN · NUDGE (the old SHIFT, relabelled per an earlier ferry — same
    /// `riffRotate` field, same 0...(LEN-1) range) · STRIDE · TRANS, 3pt gaps (2026-10-13 ferry §5). Per ferry
    /// §6, none of these turn the riff on or off. FIX 3 (2026-10-14 ferry): was a narrower, centred row (4×
    /// 69.5pt chips inside a wider tab) — now spans the tab's own full width, each chip sized from it
    /// (`(fullWidth − 3 inter-chip 3pt gaps) / 4` — at the 326pt reference this is exactly 79.25, matching
    /// the ferry's own literal table).
    private func melodyValuesRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat) -> some View {
        let n = line.riffLengthResolved
        let nudge = ((line.riffRotateResolved % n) + n) % n
        let w = max(1, (fullWidth - 3 * 3) / 4)
        return HStack(spacing: 3) {
            melodyStepper("LEN", value: n, range: 1...8, width: w, help: "How many steps the riff walk loops over") { v in
                edit(idx) { $0.riffLength = v }
            }
            melodyStepper("NUDGE", value: nudge, range: 0...(n - 1), width: w, help: "Start the riff walk further along the pattern") { v in
                edit(idx) { $0.riffRotate = v }
            }
            melodyStepper("STRIDE", value: line.riffStrideResolved, range: 1...7, width: w, help: "How many riff steps to move per note") { v in
                edit(idx) { $0.riffStride = v }
            }
            melodyStepper("TRANS", value: line.melodyTransposeResolved, range: -7...7, width: w, help: "Shift every riff note up or down the pool") { v in
                edit(idx) { $0.melodyTranspose = v }
            }
        }
    }
    // MARK: - RIFF TAB (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs"; corrected by a
    // same-week follow-up ferry, "FERRY — RIFF tab fixes", 2026-10-14) — every riff setting + a mini-grid
    // thumbnail that doubles as the riff's own on/off switch + the riff's own octave (independent of the
    // notes layer's — the ferry's explicit reversal: "each layer now has its own octave"). Total content
    // height: 90 (card + OCT trough + direction) + 8 + 48 (modes, 3 groups) + 8 + 48 (values, full width) =
    // 202, matching this page's own established fixed-326×202-tab-content convention exactly.
    //
    // SUPERSEDED LAYOUT, corrected by the follow-up ferry: the first build folded DIRECTION into the modes
    // row as a 4th group (a reasoned default at the time, since no literal ferry text had survived into that
    // implementation pass) — the follow-up ferry's own exact coordinate table puts DIRECTION on `riffTopRow`'s
    // own right-hand column instead, stacked below the OCT trough, with the modes row narrowed back to 3
    // groups at FULL label width. Every width below is now the follow-up ferry's own literal number, verified
    // algebraically (not transcribed blind) before being trusted — see each function's own doc comment.

    /// The riff card's own mini-grid — a STATIC thumbnail of the shared riff pattern (8 steps × 8 ranks),
    /// reusing the main riff grid's own 7×7-cell/1pt-gap idiom at a much smaller scale, but answering a
    /// genuinely different per-cell question: "what rank does THIS step show" (`euclideousRiffStepRanks`,
    /// mask-oblivious — a static per-step property, not a live mask roll), not "which lane's marker sits
    /// here." No per-cell drag/accessibility of its own — the card around it carries one combined label.
    /// A step past this lane's own LEN window is dimmed (it's still part of the SHARED pattern, just not
    /// currently walked by THIS lane); the live step (`riffPositions[idx]`, the SAME raw value the big riff
    /// grid's own walk-arrow reads via `updateRiffMarkers`'s `col = riffPositions[i]` — verified identical,
    /// no transform in either path) gets a highlight, shown regardless of hit/rest, so the thumbnail always
    /// shows "where we are," not just "what the pattern looks like."
    ///
    /// FIX 1 (2026-10-14 ferry, "FERRY — RIFF tab fixes"): rebuilt entire. Was see-through note cells (an
    /// "outside LEN window" treatment that read as near-identical to empty), empty cells lighter than the
    /// card, and the current step drawn as a 1pt white STROKE ring over the whole column of ranks (not just
    /// the lit cell) — all three are what the ferry's own bug report describes. Now: every cell is a plain
    /// filled square, no strokes/outlines/cut-outs/masks/column-highlight anywhere; "current step" is shown
    /// purely by giving JUST that one lit cell its own distinct fill colour, never a column-wide mark. Also
    /// drops the prior session's own "fold an out-of-range transposed rank back into 1...8" judgment call —
    /// the ferry states literally "if r is outside 1–8, that column shows no lit cell," which this rewrite
    /// now follows instead (a rest is already 0 by construction, so "no lit cell" already covers both cases
    /// uniformly with the same `1...8` bounds check, no separate rest-vs-out-of-range branching needed).
    private func riffMiniGrid(_ idx: Int, _ line: EuclidLine, _ accent: Color, size: CGFloat) -> some View {
        let n = 8
        let stepRanks = euclideousRiffStepRanks(ranks: effectiveGridRanks, invert: line.riffInvertResolved, transpose: line.melodyTransposeResolved)
        let len = line.riffLengthResolved
        let curStep = idx < riffPositions.count ? riffPositions[idx] : -1
        let isRiff = line.riffOnResolved
        let cell = max(1, (size - 7) / 8)   // 8 cells + 7 gaps of 1pt
        return VStack(spacing: 1) {
            ForEach((1...8).reversed(), id: \.self) { rank in
                HStack(spacing: 1) {
                    ForEach(0..<n, id: \.self) { col in
                        let raw = col < stepRanks.count ? stepRanks[col] : 0
                        let isHit = raw >= 1 && raw <= 8 && raw == rank
                        let inWindow = col < len
                        let isCur = col == curStep
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(riffMiniGridFill(isRiff: isRiff, isHit: isHit, inWindow: inWindow, isCur: isCur))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
    /// Fix 1's own exact fill table — riff ON (card = lane colour, label INK): a note inside the LEN window
    /// is solid INK; outside the window, INK at 35%; an empty cell is INK at 14%; the CURRENT step's note (if
    /// it has one) is `#f2f4f7`, one cell only. Riff OFF keeps the SAME palette already shipped ("the riff-
    /// OFF thumbnail is correct, keep it" — the ferry's own words) with one addition: a current-step note now
    /// gets its own `#aab0ba` fill too, replacing the old universal stroke ring this fix removes.
    private func riffMiniGridFill(isRiff: Bool, isHit: Bool, inWindow: Bool, isCur: Bool) -> Color {
        if isRiff {
            if isHit && isCur { return Color(hex: 0xF2F4F7) }
            if isHit { return Color(hex: 0x0D0F14).opacity(inWindow ? 1.0 : 0.35) }
            return Color(hex: 0x0D0F14).opacity(0.14)
        } else {
            if isHit && isCur { return Color(hex: 0xAAB0BA) }
            if isHit { return Color.white.opacity(inWindow ? 0.55 : 0.22) }
            return Color.white.opacity(0.06)
        }
    }
    /// The riff card itself — a 90×90 thumbnail that ALSO serves as this lane's on/off switch for the whole
    /// riff layer (ferry §2: "the whole card toggles the riff on and off; turning it on restores the
    /// remembered direction" — `riffDir` is already persisted independent of `riffOn`, so nothing extra is
    /// needed to "remember" it; this is the same one-tap-restores idiom the direction buttons below already
    /// use). The card itself never dims regardless of riff state — its own colour already shows on/off.
    /// Geometry per the 2026-10-14 ferry (confirmed already correct, "keep it"): radius 10, padding 6, a
    /// fixed 12pt-tall label line box with 2pt letter-spacing, a 3pt gap, then the 63×63 grid — 6+12+3+63+6=90.
    private func riffCard(_ idx: Int, _ line: EuclidLine, _ accent: Color, size: CGFloat) -> some View {
        let isRiff = line.riffOnResolved
        return VStack(spacing: 3) {
            Text("RIFF").font(.system(size: 10, weight: .heavy, design: .monospaced)).kerning(2)
                .foregroundColor(isRiff ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .frame(height: 12)
            riffMiniGrid(idx, line, accent, size: 63)
        }
        .padding(.top, 6).padding(.bottom, 6)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 10).fill(isRiff ? lane100(accent) : Color(hex: 0x2A2D34)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isRiff ? Color(hex: 0x0D0F14) : Color(hex: 0x5C626C), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { edit(idx) { $0.riffOn = !($0.riffOnResolved) } }
        .euclideousHelp("The riff as this lane plays it. Tap to turn the riff on or off.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            guard isRiff else { return "Riff, off" }
            let pos = idx < riffPositions.count ? riffPositions[idx] : -1
            return pos >= 0 ? "Riff, on, now on step \(pos + 1)" : "Riff, on"
        }())
    }
    /// The shared octave-trough control (extracted from the old `melodyOctaveTopRow`, which wrote BOTH
    /// `octave` and `riffOctave` together — the ferry's explicit reversal means each caller now writes only
    /// its own one field). A recessed trough (#131519 fill, 1pt #262930 border) holding the −2...+2
    /// segments; the SELECTED octave renders as a solid LANE-100 pill with INK digits at 17pt plus a soft
    /// glow — the same deliberately more-prominent treatment every prior octave control on this page uses.
    /// `label`/`radius` (2026-10-14 ferry Fix 2): the RIFF tab's own trough now carries an "OCT" label
    /// INSIDE itself (was a separate `melodyVerticalLabel` beside it) at radius 10 — both default to nil/8
    /// (the prior, unlabelled, radius-8 shape), so the NOTES tab's own trough call (no label, never
    /// mentioned by this ferry — "anything not mentioned stays as built") is byte-identical.
    private func euclideousOctaveTrough(value: Int, accent: Color, label: String? = nil, radius: CGFloat = 8, onSet: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            if let label {
                melodyVerticalLabel(label, size: 10, color: Color(hex: 0x8A909A), width: 16, kerning: 1)
            }
            ForEach(-2...2, id: \.self) { v in
                ZStack {
                    if value == v {
                        RoundedRectangle(cornerRadius: 7).fill(lane100(accent))
                            .shadow(color: lane100(accent).opacity(0.33), radius: 6, x: 0, y: 1)
                            .padding(3)
                    }
                    Text(euclideousSigned(v))
                        .font(.system(size: value == v ? 17 : 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(value == v ? Color(hex: 0x0D0F14) : Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onSet(v) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Octave \(euclideousSigned(v)), \(value == v ? "selected" : "not selected")")
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: radius).fill(Color(hex: 0x131519)))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(hex: 0x262930), lineWidth: 1))
        .euclideousHelp("Move this layer up or down by octaves.")
    }
    /// The RIFF tab's top row — the card (left) + a right-hand column holding the OCT trough (top, its own
    /// "OCT" label now built INSIDE it) stacked above the direction row (bottom). FIX 2 (2026-10-14 ferry):
    /// SUPERSEDES the prior session's own judgment call of folding DIRECTION into the modes row as a 4th
    /// group — the ferry's own literal row budget never had room for a 13-button modes row without
    /// truncating labels ("PE…, PI…, ST…, SK…, FI…."), and moves DIRECTION here instead, full-width with
    /// full labels. `riffDir` is already persisted independent of `riffOn`, so nothing extra is needed to
    /// "remember" it on turning the riff back on. The card never dims; the right-hand column dims to 42%
    /// while the riff is off, matching every other riff-only control on this tab.
    private func riffTopRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, height: CGFloat) -> some View {
        let isRiff = line.riffOnResolved
        return HStack(spacing: 6) {
            riffCard(idx, line, accent, size: height)
            VStack(spacing: 6) {
                euclideousOctaveTrough(value: line.riffOctaveResolved, accent: accent, label: "OCT", radius: 10) { v in
                    edit(idx) { $0.riffOctave = v }
                }
                .frame(height: 40)
                riffDirectionRow(idx, line, accent)
                    .frame(height: 44)
            }
            .opacity(isRiff ? 1.0 : 0.42)
        }
        .frame(height: height)
    }
    /// The riff direction row — FWD·REV·PEND·PING, 4 equal full-label buttons (moved out of the modes row by
    /// the 2026-10-14 ferry Fix 2, which found no room for it there without truncating labels). Tapping the
    /// lit direction turns the riff off (remembering it); tapping any other turns the riff on with that
    /// direction — unchanged from the prior shared-row version.
    private func riffDirectionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color) -> some View {
        let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]
        let curDir = line.euclideousRiffDirResolved
        let isRiff = line.riffOnResolved
        return HStack(spacing: 3) {
            ForEach(dirs, id: \.self) { d in
                let lit = curDir == d
                melodyButton(riffDirShortLabel(d), on: lit, accent: accent, height: 44, fontSize: 12, cornerRadius: 7,
                             help: "How the riff walks. Tap the lit one to turn the riff off.") {
                    edit(idx) { l in
                        if l.riffOnResolved && l.euclideousRiffDirResolved == d { l.riffOn = false }
                        else { l.riffOn = true; l.riffDir = d }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(riffDirHelpPhrase(d).capitalized), \(lit ? "selected" : "not selected")" + (lit && isRiff ? ". Tap again to turn the riff off." : ""))
            }
        }
    }
    /// The modes row — now exactly 3 groups (DIRECTION moved to `riffTopRow`'s own right column, Fix 2):
    /// ADV+HIT/STEP · REST+SKIP/FILL/TIE · INV+LOCK. None of these turn the riff on or off (the ferry's
    /// standing rule: "change their setting live... so you can set the riff up before bringing it in"). Group
    /// widths are the ferry's own literal 326pt-reference numbers (ADV 93.82 · REST 134.59 · INV 81.6,
    /// re-verified algebraically against every given x-coordinate before trusting them — e.g. ADV = label(13)
    /// + gap(3) + 2 buttons of 37.41 + 1 internal gap(3) = 93.82, exactly reproducing "HIT x 16 · STEP x
    /// 56.41"), scaled proportionally at any other width per the ferry's own "share the extra width across
    /// the stretching items" rule — each group's OWN button area absorbs its share, labels/gaps stay fixed.
    private func riffModesRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat) -> some View {
        let isRiff = line.riffOnResolved
        let avail = max(1, fullWidth - sp8 * 2)   // 2 inter-group 8pt gaps (3 groups now, was 3 gaps for 4)
        let refAdv: CGFloat = 93.82, refRest: CGFloat = 134.59, refInv: CGFloat = 81.6
        let refTotal = refAdv + refRest + refInv
        let wAdv = avail * (refAdv / refTotal), wRest = avail * (refRest / refTotal), wInv = avail * (refInv / refTotal)
        return HStack(spacing: sp8) {
            HStack(spacing: 3) {
                melodyVerticalLabel("ADV", size: 10, width: 13, kerning: 0.5)
                melodyButton("HIT", on: !line.riffAdvanceStepResolved, accent: accent, height: 40, fontSize: 11, cornerRadius: 7,
                             help: "Move the riff only on sounding hits") { edit(idx) { $0.riffAdvanceStep = false } }
                melodyButton("STEP", on: line.riffAdvanceStepResolved, accent: accent, height: 40, fontSize: 11, cornerRadius: 7,
                             help: "Move the riff on every step, not just hits") { edit(idx) { $0.riffAdvanceStep = true } }
            }
            .frame(width: wAdv)
            HStack(spacing: 3) {
                melodyVerticalLabel("REST", size: 10, width: 13, kerning: 0.5)
                ForEach([EuclidRiffOnRest.skip, .fill, .tie], id: \.self) { r in
                    melodyButton(r.rawValue, on: line.riffOnRestResolved == r, accent: accent, height: 40, fontSize: 11, cornerRadius: 7,
                                 help: riffOnRestHelpPhrase(r)) { edit(idx) { $0.riffOnRest = r } }
                }
            }
            .frame(width: wRest)
            HStack(spacing: 3) {
                melodyButton("INV", on: line.riffInvertResolved, accent: accent, height: 40, fontSize: 11, cornerRadius: 7,
                             help: "Flip the riff upside down in pitch") { edit(idx) { $0.riffInvert = !($0.riffInvertResolved) } }
                melodyButton("LOCK", on: line.riffLockResolved, accent: accent, height: 40, fontSize: 11, cornerRadius: 7,
                             help: "Restart the riff each time the pattern loops") { edit(idx) { $0.riffLock = !($0.riffLockResolved) } }
            }
            .frame(width: wInv)
        }
        .opacity(isRiff ? 1.0 : 0.42)
    }
    /// The whole RIFF tab — top row (90pt: card + OCT trough + direction) · modes row (48pt, 3 groups) ·
    /// values row (48pt, full width). 90+8+48+8+48=202, the ferry's own literal arithmetic (previously built
    /// with 4pt row gaps, giving 194 — corrected to the ferry's explicit 8pt gaps here, since its own y-
    /// coordinates for rows 2/3 — "at (0, 98)", "at (0, 154)" — only reconcile at 8pt: 90+8=98, 98+48+8=154).
    private func riffTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        ZStack {
            VStack(spacing: sp8) {
                riffTopRow(idx, line, accent, height: 90)
                riffModesRow(idx, line, accent, fullWidth: fullWidth).frame(height: 48)
                melodyValuesRow(idx, line, accent, fullWidth: fullWidth).frame(height: 48)
                    .opacity(line.riffOnResolved ? 1.0 : 0.42)
            }
            .opacity(line.listenPitchMode == .shadow ? 0.42 : 1)
            .allowsHitTesting(line.listenPitchMode != .shadow)
            listenShadowingOverlay(line)
        }
    }
    /// §6 ("the lane's own riff and lit notes are ignored... drawn at 42% opacity, with 'SHADOWING RED'
    /// ... centred over them"), shared by both `riffTabContent` and `notesTabContent` so the two tabs
    /// can't independently drift on the exact text/colour. `nil` (not SHADOWing) draws nothing.
    @ViewBuilder private func listenShadowingOverlay(_ line: EuclidLine) -> some View {
        if line.listenPitchMode == .shadow {
            let p = line.listenPitchPartnerResolved
            let partnerAccent = laneAccents[p % laneAccents.count]
            Text("SHADOWING \(listenLaneColourName(p))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(partnerAccent)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)
        }
    }

    // MARK: - NOTES TAB (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs") — lit notes/
    // TOP/TOP2 + 4 new things: an on/off strip for the notes layer, per-note octave shifts, the notes
    // layer's own octave (independent of RIFF's — the ferry's explicit reversal), and a velocity offset for
    // the notes layer alone. Total content height: 120 (keys+chips) + 8 + 40 (octave+TOP/TOP2) + 8 + 34
    // (NOTES VEL) = 210 — slightly over this page's usual 202 budget, a disclosed judgment call (see this
    // section's own layout note) rather than squeezing any one row below a comfortable touch size; the
    // excess clips per this file's own established "fit always wins, nothing shrinks a font" precedent if a
    // narrower/shorter real card ever offers less.

    /// One key column: the note button (reusing the lit-notes pitch/ring/riff-reach logic verbatim from the
    /// old `melodyNotesRow`, but NOW genuinely distinguishing an unlit REAL pool note from an unlit OCTAVE-
    /// EXTENDED copy — previously collapsed into one "unlit" look) stacked over its own octave chip (tap-
    /// cycles 0 → +1 → −1 → 0, writing `noteOctShifts[rank-1]` for THIS rank only — "a C3 shifted −1 reads
    /// C2," applied to the SAME resolved pitch the button itself displays, so the two can never disagree).
    private func notesKeyColumn(_ idx: Int, _ line: EuclidLine, _ accent: Color, rank: Int, poolCount: Int,
                                 extendedPool: [Int], source: EuclideousLaneSource, pool: [UInt8], highRanks: Set<Int>, reachable: Set<Int>,
                                 keyHeight: CGFloat, chipHeight: CGFloat) -> some View {
        let isReal = rank <= max(1, poolCount)
        let lit = (line.litNotesResolved & (1 << (rank - 1))) != 0
        let ringed = highRanks.contains(rank)
        let marked = reachable.contains(rank)
        let shift = line.noteOctShiftsResolved[rank - 1]
        let pitchName: String = {
            guard rank <= extendedPool.count else { return "–" }
            let raw = extendedPool[rank - 1] + 12 * (line.octaveResolved + shift)
            guard raw >= 0, raw <= 127 else { return "–" }
            // FERRY (2026-10-14 §1): "one name per note everywhere" — route through the shared dispatcher
            // instead of the old unconditional `flatKey: true` for MIDI IN/CHORD (the exact bug: every F♯
            // read as G♭ regardless of what was actually held).
            return euclideousDisplayNoteName(UInt8(raw), source: source, pool: pool, keyRoot: keyRoot, keyType: keyType)
        }()
        let split = euclideousSplitNoteOctave(pitchName)
        let fill: Color = lit ? lane100(accent) : (isReal ? Color(hex: 0x30343C) : Color(hex: 0x17191E))
        let border: Color = lit ? Color.clear : (isReal ? Color(hex: 0x454A54) : Color(hex: 0x202329))
        let textColor = lit ? Color(hex: 0x0D0F14) : (isReal ? Color.white.opacity(0.75) : Color.white.opacity(0.35))
        let chipLabel = shift == 0 ? "·" : euclideousSigned(shift)
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(split.note).font(.system(size: 15, weight: .heavy, design: .monospaced))
                    Text(split.octave).font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                    .foregroundColor(textColor)
                    .lineLimit(1)   // §4.6's own standing rule for this tab: truncate, never shrink
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(fill))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ringed ? (lit ? Color(hex: 0x0D0F14) : lane100(accent)) : Color.clear, lineWidth: 2).padding(2))
                if marked {
                    RoundedRectangle(cornerRadius: 1.5).fill(lit ? Color(hex: 0x0D0F14) : lane100(accent)).frame(height: 3).padding(.horizontal, 4).padding(.bottom, 3)
                }
            }
            .frame(height: keyHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                // RIFF/NOTES SPLIT: tapping a key while the notes layer is off turns it on AND applies the
                // tap in one gesture — the same one-tap-does-both idiom the RIFF direction row already uses.
                edit(idx) { l in
                    if !l.notesOnResolved { l.notesOn = true }
                    l.litNotes = l.litNotesResolved ^ (1 << (rank - 1))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Note \(rank), \(pitchName), \(lit ? "on" : "off")\(marked ? ", in riff" : "")")
            Text(chipLabel).font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(shift == 0 ? Color.white.opacity(0.4) : Color(hex: 0xF2F4F7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 5).fill(shift == 0 ? Color(hex: 0x2A2D34) : lane20(accent)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(shift == 0 ? Color.clear : lane100(accent), lineWidth: 1))
                .frame(height: chipHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    edit(idx) { l in
                        var s = l.noteOctShiftsResolved
                        s[rank - 1] = shift == 0 ? 1 : (shift == 1 ? -1 : 0)
                        l.noteOctShifts = s
                    }
                }
                .euclideousHelp("Shift this note up or down an octave.")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Note \(rank) octave shift, \(shift == 0 ? "none" : euclideousSigned(shift))")
        }
    }
    /// The 8-key row — equal columns across the tab's own available width (`fullWidth` minus the strip and
    /// its gap, matching this page's own "flexible items share the extra width" convention). Computes the
    /// pool/pitch/ring/riff-reach context ONCE, mirroring the old `melodyNotesRow` exactly, so a key can
    /// never show a pitch the engine wouldn't actually sound.
    private func notesKeysRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, keyHeight: CGFloat, chipHeight: CGFloat) -> some View {
        let poolCount = min(riffLivePool.count, 8)
        let riffOn = line.riffOnResolved
        let highRanks = euclideousHighPickRanks(topLit: line.topLitResolved, top2Lit: line.top2LitResolved, poolCount: poolCount)
        let reachable: Set<Int> = riffOn ? euclideousRiffReachableRanks(
            dir: line.euclideousRiffDirResolved, length: line.riffLengthResolved, stride: line.riffStrideResolved,
            rotate: line.riffRotateResolved, ranks: effectiveGridRanks, invert: line.riffInvertResolved,
            transpose: line.melodyTransposeResolved) : []
        let extendedPool = euclideousGlobalPoolExtended(sortedRaw: riffLivePool.map { Int($0) })
        return HStack(spacing: 3) {
            ForEach(1...8, id: \.self) { rank in
                notesKeyColumn(idx, line, accent, rank: rank, poolCount: poolCount, extendedPool: extendedPool,
                                source: noteSource, pool: riffLivePool, highRanks: highRanks, reachable: reachable,
                                keyHeight: keyHeight, chipHeight: chipHeight)
            }
        }
    }
    /// The NOTES strip — the whole layer's own on/off master switch (same visual language as the RIFF
    /// card's own on/off styling, just vertical), carrying a new 8-bar lit-notes graphic (rank 1 at the
    /// bottom, matching the keys row's own left-to-right rank order read top-down) so the strip itself
    /// shows WHICH notes are lit without needing to glance across the whole row.
    private func notesStrip(_ idx: Int, _ line: EuclidLine, _ accent: Color, height: CGFloat) -> some View {
        let isOn = line.notesOnResolved
        let litMask = line.litNotesResolved
        let litCount = (0..<8).filter { (litMask & (1 << $0)) != 0 }.count + (line.topLitResolved ? 1 : 0) + (line.top2LitResolved ? 2 : 0)
        return VStack(spacing: 8) {
            Text("NOTES").font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(isOn ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .fixedSize().rotationEffect(.degrees(-90)).frame(width: 34)
            VStack(spacing: 1) {
                ForEach((1...8).reversed(), id: \.self) { rk in
                    let lit = (litMask & (1 << (rk - 1))) != 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill((isOn ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA)).opacity(lit ? 1.0 : 0.25))
                        .frame(width: 10, height: 3)
                }
            }
        }
        .frame(width: 34, height: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(isOn ? lane100(accent) : Color(hex: 0x2A2D34)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? Color(hex: 0x0D0F14) : Color(hex: 0x5C626C), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { edit(idx) { $0.notesOn = !($0.notesOnResolved) } }
        .euclideousHelp("Turn the notes layer on or off. Lit notes are remembered.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notes layer, \(isOn ? "on" : "off"), \(litCount) notes lit")
    }
    /// The octave/TOP 2/TOP row — the shared octave trough (writing ONLY `octave`, independent of RIFF's own
    /// `riffOctave` trough) + TOP 2/TOP (reusing `melodyButton` verbatim, same one-tap-turns-the-layer-on
    /// idiom as the key columns above). Never dims — "the control that toggles a layer never dims," the
    /// same rule the RIFF card itself follows; these controls remain fully live regardless of `notesOn`.
    /// FIX 4 (2026-10-14 ferry): TOP 2 now comes FIRST (46pt wide), TOP second (42pt wide) — a literal
    /// width swap too, not just an order swap — and TOP 2's own label gained a space ("TOP2" → "TOP 2").
    private func notesOctaveTopRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, height: CGFloat) -> some View {
        HStack(spacing: sp4) {
            euclideousOctaveTrough(value: line.octaveResolved, accent: accent) { v in
                edit(idx) { l in
                    if !l.notesOnResolved { l.notesOn = true }
                    l.octave = v
                }
            }
            melodyButton("TOP 2", on: line.top2LitResolved, accent: accent, help: "Play the second-highest note of the source on every hit, following chord changes.") {
                edit(idx) { l in
                    if !l.notesOnResolved { l.notesOn = true }
                    l.top2Lit = !(l.top2LitResolved)
                }
            }
            .frame(width: 46)
            melodyButton("TOP", on: line.topLitResolved, accent: accent, help: "Play the highest note of the source on every hit, following chord changes.") {
                edit(idx) { l in
                    if !l.notesOnResolved { l.notesOn = true }
                    l.topLit = !(l.topLitResolved)
                }
            }
            .frame(width: 42)
        }
        .frame(height: height)
    }
    /// NOTES VEL — a new bespoke bipolar control (−64...+64, default 0), modelled on the SAME mechanism
    /// `EuclideousSlider`'s TILT case already proves (bipolar fill-from-centre, a static centre tick, a live
    /// value-edge line, absolute touch-to-value, a centre detent) but as its own small view, not a 7th
    /// `EuclideousSliderField` case — this control's label-left/value-right layout and fixed 287×34
    /// footprint don't match that component's generic stacked-centred convention, and forcing a new case
    /// onto an already-complex shared component for one visually-divergent control isn't worth it. Added to
    /// (never scales) the lit notes' own base velocity, clamped 1...127 at resolve (Router.swift).
    private func notesVelBar(_ idx: Int, _ line: EuclidLine, _ accent: Color) -> some View {
        let value = line.notesVelOffsetResolved
        let lo = -64.0, hi = 64.0
        return GeometryReader { geo in
            let size = geo.size
            let inset: CGFloat = 6
            let travel = max(1, size.width - inset * 2)
            // PLAIN `let` BINDINGS ONLY in this outer scope — a nested `func` declaration of any kind
            // (regardless of its own return style) is disallowed directly inside a `@ViewBuilder` closure
            // (this file's own standing pitfall). `pos`/`bar`/`edgeLine` move inside the `Canvas` closure
            // below instead, which is a plain `(GraphicsContext, CGSize) -> Void` closure, not ViewBuilder —
            // mirroring `EuclideousSlider`'s own identical local-func idiom exactly.
            let center = inset + CGFloat((0 - lo) / (hi - lo)) * travel
            let valuePos = inset + CGFloat((Double(value) - lo) / (hi - lo)) * travel
            ZStack {
                Canvas { ctx, sz in
                    func bar(_ a: CGFloat, _ b: CGFloat) -> CGRect { CGRect(x: min(a, b), y: 0, width: abs(b - a), height: sz.height) }
                    func edgeLine(_ p: CGFloat) -> CGRect { bar(p - 1, p + 1) }
                    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 6), with: .color(Color(hex: 0x22252C)))
                    ctx.fill(Path(bar(center, valuePos)), with: .color(accent.opacity(0.2)))
                    ctx.fill(Path(edgeLine(center)), with: .color(Color(hex: 0x3A3E47)))
                    ctx.fill(Path(edgeLine(valuePos)), with: .color(accent))
                }
                HStack {
                    // Same text-backing fix as EuclideousSlider (2026-10-14 fixes-after-build ferry §4,
                    // explicitly named: "this applies to... NOTES VEL") — the value line can sit right
                    // under either text depending on where the value/centre falls.
                    Text("NOTES VEL").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x22252C)))
                    Spacer()
                    Text(euclideousSigned(value)).font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x22252C)))
                }
                .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let clamped = max(inset, min(size.width - inset, g.location.x))
                        var f = Double((clamped - inset) / travel)
                        // CENTRE DETENT (~6% of travel), the same convention `euclideousTiltDetentFrac`
                        // already establishes for EuclideousSlider's own TILT case.
                        if abs(clamped - center) < travel * 0.06 { f = 0.5 }
                        let v = Int((lo + f * (hi - lo)).rounded())
                        edit(idx) { $0.notesVelOffset = max(-64, min(64, v)) }
                    }
            )
            .onTapGesture(count: 2) { edit(idx) { $0.notesVelOffset = 0 } }
        }
        .frame(height: 34)
        .euclideousHelp("Make the lit notes louder or quieter than the riff.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notes velocity, \(euclideousSigned(value))")
        .accessibilityAdjustableAction { direction in
            let cur = line.notesVelOffsetResolved
            let target = direction == .increment ? min(64, cur + 4) : max(-64, cur - 4)
            edit(idx) { $0.notesVelOffset = target }
        }
    }
    /// The whole NOTES tab — the strip (full height, left) beside keys+chips (120pt) · octave/TOP/TOP2
    /// (40pt) · NOTES VEL (34pt). Body opacity drops to 42% while `notesOn` is false (the strip itself never
    /// dims, matching the RIFF card's own "the on/off control never dims" rule).
    private func notesTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        let isOn = line.notesOnResolved
        let shadowing = line.listenPitchMode == .shadow
        return ZStack {
            HStack(spacing: sp4) {
                notesStrip(idx, line, accent, height: 210)
                VStack(spacing: sp4) {
                    notesKeysRow(idx, line, accent, keyHeight: 92, chipHeight: 24)
                    notesOctaveTopRow(idx, line, accent, height: 40)
                    notesVelBar(idx, line, accent)
                }
                .opacity(isOn ? 1.0 : 0.42)
            }
            .opacity(shadowing ? 0.42 : 1)
            .allowsHitTesting(!shadowing)
            listenShadowingOverlay(line)
        }
    }

    // MARK: - Per-lane EUCLID MASK (Paul 2026-10-07, §2.7 — pattern/transport; real effect added 2026-10-10
    // "modes and settings" ferry; step-bar fixed 2026-10-11, see `maskStepBar`'s own doc comment)

    /// The mask's own step-bar. REPLACES the shared, SELF-CLOCKED `EuclidCometBar` (Paul 2026-10-11 bug
    /// report: "Euclid mask was moving at the main rate, and not progressing on hits from Euclid lane as
    /// I'd expect"). ROOT CAUSE, confirmed by reading Router.swift, not guessed: the AUDIO side was always
    /// correct — `euclideousMaskOrd` only ever advances inside `runEuclidLine`'s `if isHit {}`, so the mask
    /// genuinely engages only on real sounding hits of the lane's own Euclid pattern. The bug was purely
    /// visual: this row fed `EuclidCometBar` a hardcoded `rate: .r1_16` against the page's shared `clock` —
    /// the SAME self-clocked sweep a plain, continuously-ticking Euclid lane uses, with zero relationship
    /// to the mask's real, hit-driven position. The exact "RATCHET PATTERN/DEST" class of bug this
    /// codebase's own history repeatedly names (the lit cell and what's actually heard disagreeing because
    /// the UI reads an unrelated clock instead of the engine's real state).
    ///
    /// FIX: draw the mask's own K/N pattern as a plain STATIC box row (no comet, no `TimelineView`) and
    /// highlight whichever box `maskPositions[idx]` (Router→Kernel→AU→VC, polled — never extrapolated,
    /// mirroring `riffPositions`' own precedent exactly) says is current. No animation between polls is
    /// deliberate, not a shortfall: the mask's position is a discrete jump once per real lane hit, not a
    /// continuous function of wall-clock time, so animating a sweep between two polled values would
    /// fabricate motion the engine never produces — the identical reasoning this codebase already applies
    /// to RIFF's own DRUNK indicator ("there's nothing smoother to extrapolate").
    ///
    /// Reuses `EuclidGesturePad` DIRECTLY (already a shared, non-private component — the per-button gesture
    /// pads elsewhere on this page construct it the same way) for the identical 1-/2-finger drag + pinch
    /// interaction `EuclidCometBar` itself used internally, so dragging/pinching this bar to edit HITS/
    /// ROTATE/STEPS is completely unchanged — only the DRAWING underneath it is new.
    private func maskStepBar(_ idx: Int, _ m: EuclidLineMask, _ accent: Color, rate: ArpRate, width: CGFloat, height: CGFloat) -> some View {
        let n = max(2, min(16, m.stepsResolved))
        let k = max(0, min(n, m.pulsesResolved))
        let rotate = m.rotate ?? 0
        let pos = idx < maskPositions.count ? maskPositions[idx] : -1
        let insetL: CGFloat = 6, insetR: CGFloat = 6
        // STEP GROUPS (2026-10-14 ferry §5, literal): "uses the same groups, gaps and rule [as the lane's
        // step row]... the same group size as its lane" — `rate` is the LANE's own resolved rate (passed by
        // `maskCometRow`), not a separate mask-level concept, so this bar can't land on a different group
        // size than the lane it belongs to. "The mask's timing is still deferred, and this does not decide
        // it" (the ferry's own disclosed scope limit) — only the STEP-ROW's visual grouping changes here.
        let groupSize = euclidStepGroupSize(forRate: rate)
        let usableW = max(1, width - insetL - insetR)
        let groupGeo = euclidGroupedBoxGeometry(n: n, g: groupSize, usableWidth: usableW)
        // SENSITIVITY, matching `EuclidCometBar`'s own convention exactly (Router.swift's box geometry, not
        // the gesture pad's SEPARATE 14pt visual padding below — that padding only shrinks the pad's own
        // touch area, it was never part of the box-pitch calculation EuclidCometBar itself uses either).
        let rotateStepPt: CGFloat = n > 1 ? (groupGeo.xs[n - 1] - groupGeo.xs[0]) / CGFloat(n - 1) : usableW / CGFloat(n)
        return ZStack {
            Canvas { ctx, size in
                var buf = [Bool](repeating: false, count: n)
                euclidPatternInto(&buf, pulses: k, steps: n, rotation: rotate)
                let midY = size.height / 2
                let localUsableW = max(1, size.width - insetL - insetR)
                let localGeo = euclidGroupedBoxGeometry(n: n, g: groupSize, usableWidth: localUsableW)
                let boxW = localGeo.stepW
                // RAISED 30→60 (Paul 2026-10-11, the PATTERN/MASK layout move — this bar now has real
                // extra height to use, where it used to sit capped inside a flat 36pt row regardless; a
                // judgment call on the new ceiling itself, not device-verified against how it actually
                // looks at the new, much taller container height.
                let boxH = min(60, size.height - 6)
                let corner = min(5, boxW / 2.2)
                for i in 0..<n {
                    let rect = CGRect(x: insetL + localGeo.xs[i], y: midY - boxH / 2, width: boxW, height: boxH)
                    let box = Path(roundedRect: rect, cornerRadius: corner)
                    let current = i == pos
                    if buf[i] {
                        ctx.fill(box, with: .color(accent.opacity(current ? 0.95 : 0.55)))
                        ctx.stroke(box, with: .color(.white.opacity(current ? 0.6 : 0.2)), lineWidth: current ? 1.5 : 1)
                    } else {
                        ctx.fill(box, with: .color(.white.opacity(0.09)))
                        ctx.stroke(box, with: .color(current ? accent : .white.opacity(0.16)), lineWidth: current ? 1.5 : 1)
                    }
                }
                // LEFTOVER RULE (ferry §3/§5) — drawn INSIDE this Canvas (unlike the RHYTHM tab's own comet
                // bar, this bar's boxes don't fill its whole height — `boxH` is capped well under `size.
                // height`, so there's real room below them for the rule within the same Canvas, no separate
                // overlay needed). A JUDGMENT CALL, flagged: the ferry gives no mask-specific pixel budget
                // ("my interpretation of how this applies to the mask") — at a very constrained real height
                // the 4pt the rule needs (2pt gap + 2pt bar) below `boxH`'s own bottom edge may be tighter
                // than this reasoning assumed; unverified off-device.
                if let rx = localGeo.ruleX, let rw = localGeo.ruleW {
                    let ruleY = min(size.height - 2, midY + boxH / 2 + 2)
                    let rule = CGRect(x: insetL + rx, y: ruleY, width: rw, height: 2)
                    ctx.fill(Path(roundedRect: rule, cornerRadius: 1), with: .color(accent))
                }
            }
            .allowsHitTesting(false)
            EuclidGesturePad(onRotateDelta: { d in euclideousApplyMaskX(idx, d) },
                             onHitsDelta: { d in euclideousApplyMaskY(idx, d) },
                             onStepsDelta: { d in editMask(idx) { let v = max(2, min(16, $0.stepsResolved + d)); $0.steps = v; if $0.pulsesResolved > v { $0.pulses = v } } },
                             onAllRotateDelta: { d in euclideousApplyAllMaskX(d) },
                             onAllHitsDelta: { d in euclideousApplyAllMaskY(d) },
                             onDragState: { point, allRows in
                                 guard let point else { dragHUDInfo = nil; return }
                                 dragHUDInfo = EuclidDragHUDInfo(label: allRows ? "ALL MASKS" : "LANE \(idx + 1) MASK",
                                                                  primary: "\(k) OF \(n)", secondary: "ROTATE \(rotate)", point: point)
                             },
                             rotateStepPt: rotateStepPt)
                .padding(.horizontal, 14)
        }
        .frame(width: width, height: height)
    }

    /// The play/stop + step-bar + count row, driven by the lane's own `mask` field — NOT `EuclidLaneBox`
    /// (that component's `selected`/`onSelect`/`trailingContent` machinery has no meaning for a mask).
    private func maskCometRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let m = line.maskResolved
        let steps = m.stepsResolved
        return HStack(spacing: sp4) {
            Image(systemName: m.enabledResolved ? "play.fill" : "stop.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(m.enabledResolved ? accent : .white.opacity(0.4))
                .frame(width: 36, height: max(36, height))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { editMask(idx) { $0.enabled = !$0.enabledResolved } }
            maskStepBar(idx, m, accent, rate: line.rate ?? .r1_16,
                        // 36(play)+36(step count)+2×sp4(the HStack's own gaps either side of this view)
                        width: max(1, width - 36 - 36 - sp4 * 2), height: max(36, height))
            Text("\(steps)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .frame(width: 36, height: max(36, height))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
        }
        .frame(height: max(36, height))
    }

    private func applyMaskRotate(_ m: inout EuclidLineMask, _ d: Int) { let steps = m.stepsResolved; m.rotate = (((m.rotate ?? 0) - d) % steps + steps) % steps }
    // HITS floor is 0, not 1 (ferry 2026-10-10 §1 table: "HITS | 0 to STEPS") — matches
    // `EuclidLineMask.pulsesResolved`'s own floor; this is the gesture-side mirror of that same clamp.
    private func applyMaskHits(_ m: inout EuclidLineMask, _ d: Int) { m.pulses = max(0, min(m.stepsResolved, m.pulsesResolved + d)) }
    private func euclideousApplyMaskX(_ idx: Int, _ d: Int) { editMask(idx) { applyMaskRotate(&$0, d) } }
    private func euclideousApplyMaskY(_ idx: Int, _ d: Int) { editMask(idx) { applyMaskHits(&$0, d) } }
    private func euclideousApplyAllMaskX(_ d: Int) { onEdit { lines in for i in lines.indices { var m = lines[i].mask ?? EuclidLineMask(); applyMaskRotate(&m, d); lines[i].mask = m } } }
    private func euclideousApplyAllMaskY(_ d: Int) { onEdit { lines in for i in lines.indices { var m = lines[i].mask ?? EuclidLineMask(); applyMaskHits(&m, d); lines[i].mask = m } } }

    // RHYTHM GESTURE CONTROLS (Paul 2026-10-14) — the main step-box row's own drag, re-wired onto this
    // lane's REAL pulses/rotate (not its mask's). Unlike MASK's direct `pulses+d`/`(rotate-d)%n` mutation,
    // the SINGLE-lane path routes through `euclideousSliderCommit` — the SAME function the RHYTHM tab's own
    // HITS/OFFSET sliders call — so a hand-edited (`customHits`) pattern rebuilds/round-trips identically
    // regardless of which control you drag, and OFFSET can't disagree with the slider's own just-fixed
    // drag-direction mirror (`euclideousSliderRange`/`Commit`'s `.offset` cases display/commit `(n-rotate)
    // %n`, not raw rotate — see those functions' own doc comments). `rhythmGestureSnapshot[idx]` is the line
    // as it stood at gesture-START (captured once by `euclideousRhythmDragState` below), so dragging back to
    // the start reproduces the exact original pattern, exactly like the slider's own touch-down snapshot.
    private func euclideousApplyRhythmX(_ idx: Int, _ d: Int) {
        let snap = rhythmGestureSnapshot[idx] ?? (idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all))
        rhythmOffsetAccum[idx] += d   // d > 0 = rightward drag (EuclidGesturePad's own established convention)
        let base = euclideousSliderRange(.offset, snap).value   // the snapshot's own DISPLAYED (mirrored) offset, not raw rotate
        edit(idx) { l in euclideousSliderCommit(.offset, &l, snapshot: snap, newValue: base + Double(rhythmOffsetAccum[idx])) }
    }
    private func euclideousApplyRhythmY(_ idx: Int, _ d: Int) {
        let snap = rhythmGestureSnapshot[idx] ?? (idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all))
        rhythmHitsAccum[idx] += d   // d > 0 = upward drag (matches MASK's own onHitsDelta convention exactly)
        edit(idx) { l in euclideousSliderCommit(.hits, &l, snapshot: snap, newValue: Double(snap.pulses + rhythmHitsAccum[idx])) }
    }
    // ALL-LANES 2-finger variants — mirror MASK's own SIMPLER, direct-mutation model (no edited-pattern
    // rebuild awareness here), a disclosed scope trade-off: a hand-edited lane caught by an all-lanes bump
    // keeps its OLD customHits shape, padded/truncated against the new pulse count by the existing render-
    // side `customHitsResolved` bounds-check rather than cleanly rebuilt — matching how every OTHER bulk/
    // all-lanes gesture on this page already treats `customHits` (none of them are rebuild-aware either).
    // A FOLLOWing lane's own OFFSET applies ON TOP of its partner's pattern, and the partner is in this "all lanes" set too — so
    // shifting both would shift the follower TWICE. A follower inherits the move through its partner instead.
    private func euclideousApplyAllRhythmX(_ d: Int) {
        onEdit { lines in for i in lines.indices where euclideousFollowPartner(lane: i, lines: lines) == nil { let n = max(2, min(16, lines[i].steps)); lines[i].rotate = ((lines[i].rotate - d) % n + n) % n } }
    }
    private func euclideousApplyAllRhythmY(_ d: Int) {
        onEdit { lines in for i in lines.indices { let n = max(2, min(16, lines[i].steps)); lines[i].pulses = max(0, min(n, lines[i].pulses + d)) } }
    }
    /// Captures the gesture-start snapshot ONCE (the first non-nil point of a NEW gesture — `onDragState`
    /// reports a non-nil point on every `.changed` tick, so a naive "always capture" would silently re-
    /// freeze the snapshot every tick, breaking the round-trip-to-start guarantee `euclideousSliderCommit`'s
    /// own HITS rebuild depends on) and clears all gesture state at gesture-end (nil point).
    /// `idx` is the lane being EDITED; `via` is the lane the finger is on when that is a FOLLOWer redirecting to its partner (the
    /// readout then says so, so it is clear whose numbers these are).
    private func euclideousRhythmDragState(_ idx: Int, via: Int? = nil, _ point: CGPoint?, _ allRows: Bool) {
        guard let point else {
            dragHUDInfo = nil
            rhythmGestureSnapshot[idx] = nil
            rhythmHitsAccum[idx] = 0; rhythmOffsetAccum[idx] = 0
            return
        }
        if rhythmGestureSnapshot[idx] == nil {
            rhythmGestureSnapshot[idx] = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
            rhythmHitsAccum[idx] = 0; rhythmOffsetAccum[idx] = 0
        }
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let n = max(2, min(16, line.steps))
        let displayedOffset = Int(euclideousSliderRange(.offset, line).value)
        let redirected = via != nil && via != idx
        dragHUDInfo = EuclidDragHUDInfo(label: allRows ? "ALL LANES" : (redirected ? "LANE \(idx + 1) · FOLLOWED" : "LANE \(idx + 1)"),
                                         primary: "\(line.pulses) OF \(n)", secondary: "OFFSET \(displayedOffset)", point: point)
    }

    /// MASK line 2 (Paul 2026-10-10, "Euclid mask, modes and settings" ferry §4) — REPLACES the deferred
    /// "EFFECT — NOT YET AVAILABLE" stub now that the mask has a real engine effect. MODE chip · up to 2
    /// parameter chips (empty slots stay genuinely empty, per §4's own "do not stretch the others") · CHANCE.
    /// SIMPLIFICATION, disclosed: parameter chips use a native SwiftUI `DragGesture` (vertical-only, so no
    /// axis-lock disambiguation is needed the way the two-axis `EuclideousXYPad` UIKit bridge requires) rather
    /// than that heavier bridge — functionally equivalent (relative vertical drag, 12pt/step for integers,
    /// 2pt/1% for CHANCE, double-tap resets to default) but a lighter-weight implementation for this ferry.
    private func maskLine2(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat, width: CGFloat) -> some View {
        let m = line.maskResolved
        let slotW = max(1, (width - sp4 * 3) / 4)   // MODE + up to 2 params + CHANCE, 4 equal columns
        return HStack(spacing: sp4) {
            // MODE chip — tap opens the 11-mode picker, grouped.
            VStack(spacing: 1) {
                Text("MODE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                Text(m.modeResolved.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white).lineLimit(1)
            }
            .frame(width: slotW, height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(lane20(accent)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lane100(accent), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { maskModePopupLane = idx }
            .euclideousHelp("How the mask changes this lane's hits")
            maskParamSlot1(idx, m, accent, rowH: rowH, width: slotW)
            maskParamSlot2(idx, m, accent, rowH: rowH, width: slotW)
            maskNumericChip(label: "CHANCE", value: "\(Int((m.chanceResolved * 100).rounded()))%", width: slotW, height: rowH,
                             ptPerStep: 2, onDrag: { d in editMask(idx) { $0.chance = max(0, min(1, m.chanceResolved + Double(d) / 100)) } },
                             onDoubleTap: { editMask(idx) { $0.chance = 1.0 } })
        }
        .frame(height: rowH)
    }
    /// The first parameter slot for the lane's current mode — 0, 1 or 2 slots per mode (§3's own table);
    /// an unused slot renders as a genuinely empty, fixed-width space, never stretched.
    @ViewBuilder private func maskParamSlot1(_ idx: Int, _ m: EuclidLineMask, _ accent: Color, rowH: CGFloat, width: CGFloat) -> some View {
        switch m.modeResolved {
        case .ratchet:
            maskNumericChip(label: "MIN", value: "\(m.ratchetMinResolved)", width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.ratchetMin = max(1, min(8, m.ratchetMinResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.ratchetMin = 2 } })
        case .repeatNote:
            maskNumericChip(label: "COUNT", value: "\(m.repeatCountResolved)", width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.repeatCount = max(1, min(4, m.repeatCountResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.repeatCount = 1 } })
        case .chord:
            maskNumericChip(label: "INTERVAL A", value: euclideousSigned(m.chordAResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.chordA = max(-7, min(7, m.chordAResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.chordA = 2 } })
        case .oct:
            maskNumericChip(label: "AMOUNT", value: "\(m.octAmountResolved)", width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.octAmount = max(1, min(2, m.octAmountResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.octAmount = 1 } })
        case .leap:
            maskNumericChip(label: "STEPS", value: euclideousSigned(m.leapStepsResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.leapSteps = max(-4, min(4, m.leapStepsResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.leapSteps = 2 } })
        case .climb:
            maskNumericChip(label: "STEP", value: euclideousSigned(m.climbStepResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.climbStep = max(-7, min(7, m.climbStepResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.climbStep = 1 } })
        case .accent:
            maskNumericChip(label: "AMOUNT", value: euclideousSigned(m.accentAmountResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.accentAmount = max(-64, min(64, m.accentAmountResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.accentAmount = 24 } })
        case .swell:
            maskNumericChip(label: "STEP", value: euclideousSigned(m.swellStepResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.swellStep = max(-32, min(32, m.swellStepResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.swellStep = 8 } })
        case .mute, .pause, .mirror:
            Color.clear.frame(width: width, height: rowH)
        }
    }
    /// The second parameter slot — only RATCHET/CHORD/OCT/CLIMB/SWELL have one; every other mode's slot
    /// stays empty.
    @ViewBuilder private func maskParamSlot2(_ idx: Int, _ m: EuclidLineMask, _ accent: Color, rowH: CGFloat, width: CGFloat) -> some View {
        switch m.modeResolved {
        case .ratchet:
            maskNumericChip(label: "MAX", value: "\(m.ratchetMaxResolved)", width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.ratchetMax = max(1, min(8, m.ratchetMaxResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.ratchetMax = 4 } })
        case .chord:
            maskNumericChip(label: "INTERVAL B", value: euclideousSigned(m.chordBResolved), width: width, height: rowH,
                             onDrag: { d in editMask(idx) { $0.chordB = max(-7, min(7, m.chordBResolved + d)) } },
                             onDoubleTap: { editMask(idx) { $0.chordB = 4 } })
        case .oct:
            maskEnumChip(label: "PATTERN", value: m.octPatternResolved.rawValue, width: width, height: rowH,
                         onTap: { editMask(idx) { $0.octPattern = euclideousNextMaskOctPattern(m.octPatternResolved) } },
                         onDoubleTap: { editMask(idx) { $0.octPattern = .up } })
        case .climb:
            maskEnumChip(label: "RANGE", value: m.climbRangeResolved.rawValue, width: width, height: rowH,
                         onTap: { editMask(idx) { $0.climbRange = euclideousNextMaskRange(m.climbRangeResolved) } },
                         onDoubleTap: { editMask(idx) { $0.climbRange = .wrap1 } })
        case .swell:
            maskEnumChip(label: "RANGE", value: m.swellRangeResolved.rawValue, width: width, height: rowH,
                         onTap: { editMask(idx) { $0.swellRange = euclideousNextMaskSwellRange(m.swellRangeResolved) } },
                         onDoubleTap: { editMask(idx) { $0.swellRange = .bounce } })
        case .mute, .pause, .mirror, .repeatNote, .leap, .accent:
            Color.clear.frame(width: width, height: rowH)
        }
    }
    /// A labelled, vertical-drag-to-change numeric chip — 12pt/step by default (§4's own literal "relative
    /// drag, 12pt per step for whole numbers"), overridable (CHANCE's own 2pt/1%). Dragging UP increases the
    /// value (screen-y is inverted relative to "up"), matching every other drag control's convention on this
    /// page. Double-tap resets to the mode's own stated default. Thin wrapper over `MaskDragChip`, which
    /// needs to be a real `View` struct (not a free function) so it can hold its own per-gesture `@State` —
    /// `DragGesture.onChanged` reports CUMULATIVE translation since the drag began, not a per-tick delta, so
    /// the chip must remember how many steps it has already applied THIS drag and report only the increment.
    private func maskNumericChip(label: String, value: String, width: CGFloat, height: CGFloat, ptPerStep: CGFloat = 12, onDrag: @escaping (Int) -> Void, onDoubleTap: @escaping () -> Void) -> some View {
        MaskDragChip(label: label, value: value, width: width, height: height, ptPerStep: ptPerStep, onDrag: onDrag, onDoubleTap: onDoubleTap)
    }
    /// A labelled, tap-to-cycle enum chip (PATTERN/RANGE) — the compact `euclideousNextOnRest`-style shape,
    /// used here (rather than a segmented row) specifically because this line has no room for 3-4 extra
    /// buttons per parameter the way the melody pop-up's own WALK section does.
    private func maskEnumChip(label: String, value: String, width: CGFloat, height: CGFloat, onTap: @escaping () -> Void, onDoubleTap: @escaping () -> Void) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
            Text(value).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(perform: onTap)
    }
    /// The real backing view for `maskNumericChip` — a dedicated struct so the drag gesture can hold its own
    /// `@State lastSteps`, tracking how many whole steps this ONE in-flight drag has already applied. Without
    /// this, `onChanged`'s cumulative translation would re-report the full step count on every tick and the
    /// value would run away (e.g. a drag sitting past the 2nd step boundary would re-apply +2 dozens of times
    /// a second, not once) — `lastSteps` makes each call report only the NEW increment since last reported,
    /// then resets to 0 at `.onEnded` so the next drag starts counting from zero again.
    private struct MaskDragChip: View {
        let label: String
        let value: String
        let width: CGFloat
        let height: CGFloat
        let ptPerStep: CGFloat
        let onDrag: (Int) -> Void
        let onDoubleTap: () -> Void
        @State private var lastSteps: Int = 0
        var body: some View {
            VStack(spacing: 1) {
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                Text(value).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
            }
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        let steps = Int((-g.translation.height / ptPerStep).rounded())
                        let delta = steps - lastSteps
                        if delta != 0 { lastSteps = steps; onDrag(delta) }
                    }
                    .onEnded { _ in lastSteps = 0 }
            )
            .onTapGesture(count: 2, perform: onDoubleTap)
        }
    }
    private func euclideousNextMaskOctPattern(_ p: MaskOctPattern) -> MaskOctPattern { switch p { case .up: return .down; case .down: return .alt; case .alt: return .up } }
    private func euclideousNextMaskRange(_ r: MaskRange) -> MaskRange { switch r { case .wrap1: return .wrap2; case .wrap2: return .bounce1; case .bounce1: return .bounce2; case .bounce2: return .wrap1 } }
    private func euclideousNextMaskSwellRange(_ r: MaskSwellRange) -> MaskSwellRange { r == .wrap ? .bounce : .wrap }
    /// The MODE picker (§4: "a picker of the 11 modes, grouped: Thinning... Thickening... Pitch... Dynamics").
    /// Same scrim+centred-card shape as `ratePopupCard` above.
    private func maskModePopupCard(_ idx: Int) -> some View {
        let accent = laneAccents[idx % laneAccents.count]
        let groups: [(String, [MaskMode])] = [
            ("THINNING", [.mute, .pause]),
            ("THICKENING", [.ratchet, .repeatNote, .chord]),
            ("PITCH", [.oct, .mirror, .leap, .climb]),
            ("DYNAMICS", [.accent, .swell]),
        ]
        let current = idx < lines.count ? lines[idx].maskResolved.modeResolved : .mute
        return VStack(alignment: .leading, spacing: 10) {
            Text("LANE \(idx + 1) MASK MODE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            ForEach(groups, id: \.0) { title, modes in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    HStack(spacing: 4) {
                        ForEach(modes, id: \.self) { mo in
                            let on = current == mo
                            Text(mo.rawValue).font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundColor(on ? .white : .white.opacity(0.6)).lineLimit(1)
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? lane20(accent) : Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                                .contentShape(Rectangle())
                                .onTapGesture { editMask(idx) { $0.mode = mo }; maskModePopupLane = nil }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - LISTEN TAB (ferry 2026-10-14, "the LISTEN tab (lane relationships)", RATIFIED) — §1-§4.
    // Three independent rows (RHYTHM/PITCH/LEVEL), each a row label + mode buttons + a partner button,
    // plus a 4-stepper details row. §3's own literal pixel layout is reproduced at the page's own 326pt
    // reference width (`fullWidth`) the same way every OTHER tab on this page already does (e.g.
    // `patternControlBlock`'s own literal `80`/`38` constants) — proportional only where the spec's own
    // numbers already express a width split (the mode-button group), fixed where the spec gives a fixed
    // width (the 13pt label, the 44pt partner button).

    private func listenModeButton(name: String, hint: String, lit: Bool, width: CGFloat, height: CGFloat, accent: Color, action: @escaping () -> Void) -> some View {
        // `.minimumScaleFactor` removed on both lines (adversarial-review fix) — this page's own standing
        // rule is "truncate, never shrink"; every name/hint pair here fits the 84.67pt/128.5pt button
        // widths at 11pt/10pt comfortably (the longest hint, "QUIETER WITH IT", is well under 128.5pt).
        VStack(spacing: 3) {
            Text(name).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
                .foregroundColor(lit ? patternSelectedText : patternUnselectedText).lineLimit(1)
            Text(hint).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(lit ? Color(hex: 0xDFE3EA) : Color(hex: 0x8A909A)).lineLimit(1)
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(lit ? lane20(accent) : patternUnselectedFill))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(lit ? lane100(accent) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
    /// §3's own ANY glyph: "a circle split into four quarters (red, blue, yellow, green, clockwise from
    /// the top)." Four quarter-pie wedges via `Path`, each a plain 90° arc from the lane's own accent.
    private func listenAnyDot(size: CGFloat) -> some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2), r = min(sz.width, sz.height) / 2
            for i in 0..<4 {
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .degrees(Double(i) * 90 - 90), endAngle: .degrees(Double(i + 1) * 90 - 90), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(laneAccents[i]))
            }
        }
        .frame(width: size, height: size)
    }
    /// §3's own partner button — 44×44, radius 9. Lit (this row has a mode on): the partner's identity
    /// (a dot + colour name, or the ANY glyph) over `#2a2d34`/`#3a3e47`-bordered fill; tapping opens the
    /// picker. Unlit (no mode on this row): a plain "—" over `#22252c`, not tappable.
    @ViewBuilder private func listenPartnerButton(idx: Int, row: EuclideousListenRow, width: CGFloat, height: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let hasMode: Bool = {
            switch row {
            case .rhythm: return line.listenRhythmMode != nil
            case .pitch: return line.listenPitchMode != nil
            case .level: return line.listenLevelMode != nil
            }
        }()
        if hasMode {
            let isAny = row == .pitch && line.listenPitchPartnerAnyResolved
            let partnerIdx: Int = {
                switch row {
                case .rhythm: return line.listenRhythmPartnerResolved
                case .pitch: return line.listenPitchPartnerResolved
                case .level: return line.listenLevelPartnerResolved
                }
            }()
            // LISTEN/SHADOW (§6, adversarial-review fix): "if the partner's riff is off, the shadow is
            // silent, and the PITCH row's partner button shows NO RIFF instead of the colour name."
            let partnerRiffOff = row == .pitch && line.listenPitchMode == .shadow && !isAny
                && partnerIdx < lines.count && !lines[partnerIdx].riffOnResolved
            VStack(spacing: 3) {
                if isAny { listenAnyDot(size: 18) }
                else { Circle().fill(laneAccents[partnerIdx % laneAccents.count]).frame(width: 18, height: 18) }
                // `.minimumScaleFactor` removed (adversarial-review fix) — this page's own standing rule,
                // stated repeatedly throughout its history, is "truncate, never shrink"; every name here
                // (RED/BLUE/YELLOW/GREEN/ANY/NO RIFF) fits this button's real width at 10pt regardless.
                Text(isAny ? "ANY" : (partnerRiffOff ? "NO RIFF" : listenLaneColourName(partnerIdx)))
                    .font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
            }
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x2A2D34)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { listenPartnerPopup = (idx, row) }
        } else {
            Text("—").font(.system(size: 13, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0x4A4E57))
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x22252C)))
        }
    }
    /// §4's own picker — "the other three lane colours, plus ANY when the row's mode is AVOID." Greyed
    /// (per `euclideousListenGreyedPartners`) entries are shown but not tappable. Reuses the SAME
    /// scrim+centred-card shell as `maskModePopupCard`, mounted at the overlay site above.
    private func listenPartnerPopupCard(lane: Int, row: EuclideousListenRow) -> some View {
        let accent = laneAccents[lane % laneAccents.count]
        let grey = euclideousListenGreyedPartners(lines, lane: lane, row: row)
        let line = lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all)
        let currentAny = row == .pitch && line.listenPitchPartnerAnyResolved
        func setPartner(_ p: Int?, any: Bool) {
            edit(lane) {
                switch row {
                case .rhythm: $0.listenRhythmPartner = p
                case .pitch: if let p { $0.listenPitchPartner = p }; $0.listenPitchPartnerAny = any   // ANY (p == nil) keeps the specific partner for when AVOID → SHADOW
                case .level: $0.listenLevelPartner = p
                }
            }
            listenPartnerPopup = nil
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("LANE \(lane + 1) PARTNER").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { p in
                    let isGrey = p == lane || grey.contains(p)
                    let isSel: Bool = {
                        switch row {
                        case .rhythm: return !currentAny && line.listenRhythmPartnerResolved == p && line.listenRhythmMode != nil
                        case .pitch: return !currentAny && line.listenPitchPartnerResolved == p && line.listenPitchMode != nil
                        case .level: return !currentAny && line.listenLevelPartnerResolved == p && line.listenLevelMode != nil
                        }
                    }()
                    VStack(spacing: 4) {
                        Circle().fill(laneAccents[p]).frame(width: 22, height: 22).opacity(isGrey ? 0.3 : 1)
                        Text(listenLaneColourName(p)).font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(isGrey ? Color(hex: 0x4A4E57) : .white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 6).fill(isSel ? lane20(accent) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSel ? lane100(accent) : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { if p != lane, !grey.contains(p) { setPartner(p, any: false) } }
                }
                if row == .pitch, line.listenPitchMode == .avoid {
                    VStack(spacing: 4) {
                        listenAnyDot(size: 22)
                        Text("ANY").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 6).fill(currentAny ? lane20(accent) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(currentAny ? lane100(accent) : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { setPartner(nil, any: true) }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    /// §3's own details-row stepper — fill `#2a2d34`, radius 7, 16pt ‹/› zones, label(10pt)/value(13pt
    /// heavy) centred 2pt apart. §3: "A stepper whose mode isn't lit is drawn at 42% opacity and doesn't
    /// respond."
    private func listenStepper(_ label: String, value: String, enabled: Bool, width: CGFloat, height: CGFloat, onDec: @escaping () -> Void, onInc: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Text("‹").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                .frame(width: 16, height: height)
                .contentShape(Rectangle()).onTapGesture { if enabled { onDec() } }
            VStack(spacing: 2) {
                Text(label).font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                // `.minimumScaleFactor` removed (adversarial-review fix) — every value this stepper shows
                // (UNISON/−7TH.../100%/MUTE/MOVE) fits its 79.25pt width at 13pt comfortably.
                Text(value).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            Text("›").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                .frame(width: 16, height: height)
                .contentShape(Rectangle()).onTapGesture { if enabled { onInc() } }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x2A2D34)))
        .opacity(enabled ? 1 : 0.42)
    }
    /// §6's own INTERVAL naming table — KEY source names it diatonically; CHORD/MIDI IN show the bare
    /// signed pool-step count.
    private func listenIntervalText(_ v: Int, keySource: Bool) -> String {
        guard keySource else { return v > 0 ? "+\(v)" : "\(v)" }
        let names = ["−OCT", "−7TH", "−6TH", "−5TH", "−4TH", "−3RD", "−2ND", "UNISON", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "OCT"]
        let idx = max(-7, min(7, v)) + 7
        return names[idx]
    }
    private func listenTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        let rowH: CGFloat = 44
        let labelW: CGFloat = 13
        let partnerW: CGFloat = 44
        let modeGroupW = max(1, fullWidth - labelW - 3 - partnerW - 6)
        let btn3W = max(1, (modeGroupW - 3 * 2) / 3)
        let btn2W = max(1, (modeGroupW - 3) / 2)
        func row<Content: View>(_ label: String, row: EuclideousListenRow, @ViewBuilder buttons: () -> Content) -> some View {
            HStack(spacing: 0) {
                melodyVerticalLabel(label, size: 10, color: Color(hex: 0x8A909A), width: labelW)
                Spacer().frame(width: 3)
                HStack(spacing: 3) { buttons() }
                Spacer().frame(width: 6)
                listenPartnerButton(idx: idx, row: row, width: partnerW, height: rowH)
            }
            .frame(width: fullWidth, height: rowH)
        }
        let detailsW = max(1, (fullWidth - 3 * 3) / 4)
        let shadowLit = line.listenPitchMode == .shadow
        let avoidLit = line.listenPitchMode == .avoid
        let levelLit = line.listenLevelMode != nil
        let keySource = line.sourceModeResolved == .key
        // LAYOUT (§2/§3, adversarial-review fix): a uniform 6pt VStack spacing put the details row at
        // y150, 4pt short of the spec's own y154 — RHYTHM(y0)→PITCH(y50)→LEVEL(y100) are each a 6pt gap
        // apart, but LEVEL(ends y144)→details(y154) is a 10pt gap, not 6. Explicit per-gap spacers
        // (0+6+6+10) reproduce the spec's own y-coordinates exactly and sum to the full 202pt budget
        // (44·3 + 6·2 + 10 + 48 = 202) with none left over as unintended trailing space.
        return VStack(spacing: 0) {
            row("RHYTHM", row: .rhythm) {
                listenModeButton(name: "FOLLOW", hint: "COPY HITS", lit: line.listenRhythmMode == .follow, width: btn3W, height: rowH, accent: accent) {
                    toggleListenRhythmMode(idx, .follow)
                }
                listenModeButton(name: "WITH", hint: "SHARED HITS", lit: line.listenRhythmMode == .with, width: btn3W, height: rowH, accent: accent) {
                    toggleListenRhythmMode(idx, .with)
                }
                listenModeButton(name: "GAPS", hint: "IN ITS GAPS", lit: line.listenRhythmMode == .gaps, width: btn3W, height: rowH, accent: accent) {
                    toggleListenRhythmMode(idx, .gaps)
                }
            }
            Spacer().frame(height: 6)
            row("PITCH", row: .pitch) {
                listenModeButton(name: "SHADOW", hint: "TAKE ITS NOTE", lit: shadowLit, width: btn2W, height: rowH, accent: accent) {
                    toggleListenPitchMode(idx, .shadow)
                }
                listenModeButton(name: "AVOID", hint: "NOT ITS NOTE", lit: avoidLit, width: btn2W, height: rowH, accent: accent) {
                    toggleListenPitchMode(idx, .avoid)
                }
            }
            Spacer().frame(height: 6)
            row("LEVEL", row: .level) {
                listenModeButton(name: "DUCK", hint: "QUIETER WITH IT", lit: line.listenLevelMode == .duck, width: btn2W, height: rowH, accent: accent) {
                    toggleListenLevelMode(idx, .duck)
                }
                listenModeButton(name: "ACCENT", hint: "LOUDER WITH IT", lit: line.listenLevelMode == .accent, width: btn2W, height: rowH, accent: accent) {
                    toggleListenLevelMode(idx, .accent)
                }
            }
            Spacer().frame(height: 10)
            HStack(spacing: 3) {
                listenStepper("INTERVAL", value: listenIntervalText(line.listenShadowIntervalResolved, keySource: keySource), enabled: shadowLit, width: detailsW, height: 48,
                              onDec: { edit(idx) { $0.listenShadowInterval = max(-7, $0.listenShadowIntervalResolved - 1) } },
                              onInc: { edit(idx) { $0.listenShadowInterval = min(7, $0.listenShadowIntervalResolved + 1) } })
                listenStepper("OCT", value: euclideousSigned(line.listenShadowOctaveResolved), enabled: shadowLit, width: detailsW, height: 48,
                              onDec: { edit(idx) { $0.listenShadowOctave = max(-2, $0.listenShadowOctaveResolved - 1) } },
                              onInc: { edit(idx) { $0.listenShadowOctave = min(2, $0.listenShadowOctaveResolved + 1) } })
                listenStepper("AVOID", value: line.listenAvoidActionResolved.rawValue, enabled: avoidLit, width: detailsW, height: 48,
                              onDec: { edit(idx) { $0.listenAvoidAction = $0.listenAvoidActionResolved == .mute ? .move : .mute } },
                              onInc: { edit(idx) { $0.listenAvoidAction = $0.listenAvoidActionResolved == .mute ? .move : .mute } })
                listenStepper("AMOUNT", value: "\(Int((line.listenLevelAmountResolved * 100).rounded()))%", enabled: levelLit, width: detailsW, height: 48,
                              onDec: { edit(idx) { $0.listenLevelAmount = max(0, $0.listenLevelAmountResolved - 0.05) } },
                              onInc: { edit(idx) { $0.listenLevelAmount = min(1, $0.listenLevelAmountResolved + 0.05) } })
            }
            .frame(width: fullWidth, height: 48)
        }
        .frame(width: fullWidth, height: contentAreaH, alignment: .top)
    }
    /// §4's own tap rule: "tapping an unlit mode lights it... tapping the lit mode turns it off, and that
    /// row goes back to the lane's own setting." / "when a mode is first lit, its partner is the next
    /// valid lane... if no lane is valid, the mode can't be lit." Three concrete functions, not one
    /// generic — a `EuclideousRhythmMode`/`PitchMode`/`LevelMode` are three genuinely different types with
    /// no shared protocol worth inventing just to force one call site, and three plain functions carry no
    /// risk of a mismatched-type crash the way a generic-plus-force-cast version would.
    // Each toggle is a pure function (Derivations.swift) so the "remember the partner" rule is tested: switching a mode off, or
    // swapping it for another mode in the same row, never clears the partner the lane picked.
    private func toggleListenRhythmMode(_ idx: Int, _ mode: EuclideousRhythmMode) {
        if let updated = euclideousListenToggleRhythm(lines, lane: idx, mode: mode) { edit(idx) { $0 = updated } }
    }
    private func toggleListenPitchMode(_ idx: Int, _ mode: EuclideousPitchMode) {
        if let updated = euclideousListenTogglePitch(lines, lane: idx, mode: mode) { edit(idx) { $0 = updated } }
    }
    private func toggleListenLevelMode(_ idx: Int, _ mode: EuclideousLevelMode) {
        if let updated = euclideousListenToggleLevel(lines, lane: idx, mode: mode) { edit(idx) { $0 = updated } }
    }

    // The I/O tab is MOOT (confirmed by reading, not assumed) — it was already retired entirely on
    // 2026-10-11 ("I want the io tab removed and for the output to be set in the pattern tab on the
    // bottom right"), well before this ferry arrived; `EuclideousLaneTab` has had only PATTERN/MASK ever
    // since. This ferry's own "I/O tab" section ("remove the emitter toggles from I/O... if I/O ends up
    // empty, keep the tab and report it") describes a prior state that no longer exists in this codebase
    // — there is no I/O tab left to empty or report on. The emitter toggles it asks to relocate were
    // ALREADY living in the PATTERN tab (exactly where this ferry wants them); `laneOutRow` (above,
    // beside `directionRow`/`invButton`/`patternControlBlock`) is simply its restyled replacement.
    // The OLD `laneOutRow` (circular dots + an "OUT" caption + a `compact:` flag + the dashed/hollow
    // "routed but muted" ring + a trailing "NO OUTPUT" warning, `laneOutSize`'s own sole user) is
    // REMOVED entire, superseded by the new equal-width version declared earlier in this file.

    // The RATE pop-up (`ratePopupCard`/`rateGroups`) is REMOVED entire (ratified PATTERN-tab-layout ferry,
    // 2026-10-12) — RATE is now the division×feel grid living directly in the tab (`patternControlBlock`,
    // below `tabContent`), no pop-up needed; "remove the RATE pop-up... leave no dead code," literal.

    // MARK: - The riff grid (Paul 2026-10-08, ferry §1: RESTORED to the original 8-column × 8-rank matrix —
    // supersedes the 2026-10-07 single-row/level-bar design entirely, not layered alongside it)

    /// The original riff editor: 8 step columns × 8 rank rows (rank 8 at the top, rank 1 at the bottom — "higher
    /// pitch reads higher on screen"). Tapping a cell sets that STEP's rank to THIS row; tapping the cell that's
    /// already selected for that step clears it to a rest (0) — the exact toggle `rr[col] = (rr[col] == rank ?
    /// 0 : rank)` the original popup used. Cells are a NEUTRAL colour (ferry §1 — not a lane colour, since the
    /// pattern is shared by every lane that has riff on, not owned by any one of them).
    ///
    /// SIZED FROM THE CALLER'S OWN `maxWidth`/`rowH` (this ferry §1.4 — landscape passes the 36%-of-container
    /// riff column's own width + a row height solved to fill the full column height; portrait passes the full
    /// container width + a row height solved from the panel's own, possibly-flexed, target height — see
    /// `portraitLayout`/`landscapeLayout`/`riffRowHForPanelHeight`).
    ///
    /// Per-lane position dots sit above the columns (ferry §2.3 originally, re-specified by this ferry's own
    /// §7.2 as a DOTS-ONLY row with no background cell drawn — see the row itself, below) — reads
    /// `riffPositions[i]` (Router→Kernel→AU→VC, polled on the fast ~30fps timer) against this column index for
    /// every useRiff-on lane. Still unverified on-device whether the dots are actually visible in practice.
    // ONE GLOBAL RIFF/NOTE SOURCE ferry (Paul 2026-10-12, second same-day ferry) — "Riff block layout"
    // rules 1-7: a 30pt note-name label column (REPLACES the old 18pt generic HIGH/LOW gutter entirely —
    // that gutter's own doc comment had already flagged its width as un-subtracted "genuinely extra" slack
    // of uncertain real-device margin; this ferry resolves that ambiguity explicitly, rule 6: "shrink the
    // riff cells to fit, keeping them square"), the grid, and 3 vertical source tabs. `sideOverhead` (30pt
    // label + 6pt gap + 6pt gap + 22pt tabs = 64pt) is SUBTRACTED from `maxWidth` before dividing by 8
    // columns, so the matrix's real rendered width can never exceed its stated budget the way the old
    // gutter's did.
    private let riffLabelColW: CGFloat = 30
    // (safe-subscript extension declared file-private at the bottom of this file — see `Array.subscript(safe:)`)
    /// The riff matrix's own cell width — ONE formula, shared by `riffGridView` and `slotRow` (§10.2:
    /// "the same cellW the grid draws with"), so the slot row's two tiles can never drift out of alignment
    /// with the 8-column grid underneath.
    private func riffCellW(maxWidth: CGFloat) -> CGFloat {
        let n = 8
        let gridW = max(1, maxWidth - (riffLabelColW + sp4))
        return max(1, (gridW - sp8 * 2 - sp4 * CGFloat(n - 1)) / CGFloat(n))
    }
    /// LOOP SLOTS §10: one pure function of a slot's state → its tile/ring/foot colours (§10.5) — the tile
    /// views below and any future state-dependent rendering share this, never re-deriving "what does an
    /// empty/ready/playing/queued/keeping slot look like."
    enum EuclideousSlotLook { case empty, ready, playing, queued, keeping }
    private func slotLook(_ i: Int) -> EuclideousSlotLook {
        if pendingKeepSlot == i { return .keeping }
        if queuedSlot == i { return .queued }
        if playingSlot == i { return .playing }
        return (i < loopSlots.count && loopSlots[i].isFilled) ? .ready : .empty
    }
    /// §10: the slot row — two tiles (keep ●, play ▶) over a length foot, per slot, aligned to the grid
    /// columns below (§10.2). Long-press ● opens COPY/PASTE/CLEAR (§8); tapping the foot opens the length
    /// picker (§10.6).
    private func slotRow(maxWidth: CGFloat) -> some View {
        let cellW = riffCellW(maxWidth: maxWidth)
        let slotW = cellW * 2 + sp4
        let ring: Color = Color(hex: 0xDFE3EA)
        let dim: Color = Color(hex: 0x4A4E57)
        let tileBG: Color = Color(hex: 0x2A2D34)
        return HStack(spacing: sp4) {
            Color.clear.frame(width: riffLabelColW)
            ForEach(0..<4, id: \.self) { i in
                let look = slotLook(i)
                let selected = look == .queued || look == .keeping   // §10.5: the selected-choice look, neutral variant (Decision 5)
                VStack(spacing: 0) {
                    HStack(spacing: sp4) {
                        // KEEP tile
                        ZStack {
                            Circle().fill(selected && look == .keeping ? ring.opacity(0.2) : Color.clear)
                                .overlay(Circle().stroke(look == .keeping ? ring : Color.clear, lineWidth: 1))
                            Circle().strokeBorder(look == .empty ? dim : Color.clear, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                            Circle().fill(look == .empty ? Color.clear : (look == .keeping ? ring.opacity(0.4) : ring)).frame(width: 11, height: 11)
                        }
                        .frame(width: cellW, height: 40)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tileBG))
                        .clipShape(.rect(topLeadingRadius: 6, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0))
                        .contentShape(Rectangle())
                        .onTapGesture { onKeepTap(i) }
                        .onLongPressGesture(minimumDuration: 0.5) { riffTabMenuLane = i }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Keep last \(Int(loopSlots[safe: i]?.length.bars ?? 4)) bars in slot \(i + 1)")
                        .accessibilityHint("Long-press for copy, paste and clear")
                        // PLAY tile
                        ZStack {
                            euclideousSlotRing(look: look, slot: i, size: min(28, cellW - 6), ringColor: ring, dim: dim)
                            EuclidPlayTriangle()
                                .fill(look == .empty ? dim : ring)
                                .frame(width: 9, height: 10)
                                .offset(x: 1)
                        }
                        .frame(width: cellW, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tileBG)
                                .overlay(look == .queued ? RoundedRectangle(cornerRadius: 6).fill(ring.opacity(0.2)).overlay(RoundedRectangle(cornerRadius: 6).stroke(ring, lineWidth: 1)) : nil)
                        )
                        .clipShape(.rect(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { onPlayTap(i) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(look == .empty ? "Slot \(i + 1), empty" : (look == .playing ? "Stop slot \(i + 1)" : (look == .queued ? "Slot \(i + 1) starts next bar" : "Play slot \(i + 1)")))
                    }
                    // FOOT
                    Text(euclideousSlotLengthLabel(i))
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.06 * 9)
                        .frame(maxWidth: .infinity).frame(height: 14)
                        .foregroundColor(look == .empty ? Color(hex: 0x6A7079) : (look == .playing ? Color(hex: 0x0D0F14) : Color(hex: 0xDFE3EA)))
                        .background(
                            Group {
                                if look == .empty { RoundedRectangle(cornerRadius: 0).strokeBorder(dim, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])) }
                                else { RoundedRectangle(cornerRadius: 0).fill(look == .playing ? ring : Color(hex: 0x3A3E47)) }
                            }
                        )
                        .clipShape(.rect(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { slotLengthPopoverLane = slotLengthPopoverLane == i ? nil : i }
                        .accessibilityLabel("Slot \(i + 1) length, \(Int(loopSlots[safe: i]?.length.bars ?? 4)) bars")
                }
                .frame(width: slotW)
            }
        }
    }
    @ViewBuilder private func euclideousSlotRing(look: EuclideousSlotLook, slot: Int, size: CGFloat, ringColor: Color, dim: Color) -> some View {
        let lengthBars = max(1, Int(loopSlots[safe: slot]?.length.bars ?? 4))
        if look == .empty {
            Circle().strokeBorder(dim, style: StrokeStyle(lineWidth: 3, dash: [2.5, 2.5])).frame(width: size, height: size)
        } else {
            let progress = look == .playing ? playingSlotProgress.position / max(1, playingSlotProgress.lengthBars) : 0
            Canvas { ctx, sz in
                let rect = CGRect(origin: .zero, size: sz).insetBy(dx: 1.5, dy: 1.5)
                for bar in 0..<lengthBars {
                    let gap: Double = 12
                    let barStart = Double(bar) / Double(lengthBars) * 360 - 90 + gap / 2
                    let barEnd = Double(bar + 1) / Double(lengthBars) * 360 - 90 - gap / 2
                    let played = progress * Double(lengthBars) >= Double(bar + 1)
                    let partial = !played && progress * Double(lengthBars) > Double(bar)
                    let end = partial ? (barStart + (barEnd - barStart) * (progress * Double(lengthBars) - Double(bar))) : barEnd
                    var p = Path(); p.addArc(center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: rect.width / 2, startAngle: .degrees(barStart), endAngle: .degrees(played || partial ? end : barStart), clockwise: false)
                    ctx.stroke(p, with: .color(dim), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    if played || partial {
                        var p2 = Path(); p2.addArc(center: CGPoint(x: sz.width / 2, y: sz.height / 2), radius: rect.width / 2, startAngle: .degrees(barStart), endAngle: .degrees(end), clockwise: false)
                        ctx.stroke(p2, with: .color(ringColor), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }
    private func euclideousSlotLengthLabel(_ i: Int) -> String {
        switch loopSlots[safe: i]?.length ?? .fourBars {
        case .oneBar: return "1 BAR"; case .twoBars: return "2 BARS"; case .fourBars: return "4 BARS"; case .eightBars: return "8 BARS"
        }
    }
    @State private var slotLengthPopoverLane: Int? = nil
    private func slotLengthPopoverCard(_ idx: Int) -> some View {
        let current = loopSlots[safe: idx]?.length ?? .fourBars
        return VStack(spacing: 8) {
            Text("BARS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.06 * 9).foregroundColor(Color(hex: 0xAAB0BA))
            HStack(spacing: sp4) {
                ForEach([EuclideousLoopBars.oneBar, .twoBars, .fourBars, .eightBars], id: \.self) { b in
                    let sel = b == current
                    Text("\(Int(b.bars))").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEditLoopSlots { s in guard idx < s.count else { return }; s[idx].length = b }
                            slotLengthPopoverLane = nil
                        }
                }
            }
        }
        .padding(sp8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
    }
    /// LOOP SLOTS §8: long-press ● opens COPY/PASTE/CLEAR on the WHOLE slot (length included).
    private func riffTabMenuCard(_ idx: Int) -> some View {
        func row(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .white.opacity(0.85) : .white.opacity(0.3))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { if enabled { action() } }
        }
        return VStack(spacing: 8) {
            Text("SLOT \(idx + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            row("COPY", enabled: idx < loopSlots.count && loopSlots[idx].isFilled) {
                loopSlotClipboard = idx < loopSlots.count ? loopSlots[idx] : nil
                riffTabMenuLane = nil
            }
            row("PASTE", enabled: loopSlotClipboard != nil) {
                guard let c = loopSlotClipboard else { return }
                onEditLoopSlots { s in guard idx < s.count else { return }; s[idx] = c }
                if playingSlot == idx { onPlayTap(idx); onPlayTap(idx) }   // §8.2: pasted into the PLAYING slot restarts it from its first bar at the next bar line (stop then re-queue)
                riffTabMenuLane = nil
            }
            row("CLEAR", enabled: idx < loopSlots.count && loopSlots[idx].isFilled) {
                if playingSlot == idx { onPlayTap(idx) }   // §8.2: clearing the playing slot stops it
                onEditLoopSlots { s in guard idx < s.count else { return }; s[idx] = .empty }
                riffTabMenuLane = nil
            }
        }
        .padding(16).frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    @State private var loopSlotClipboard: EuclideousLoopSlot? = nil
    private func riffGridView(maxWidth: CGFloat, rowH: CGFloat) -> some View {
        let n = 8
        let ranks = effectiveGridRanks
        // MIDI IN/CHORD/KEY moved to the header (2026-10-14) — the grid reclaims the width the old
        // vertical source tabs used to occupy; only the label column's own gap is left to account for.
        let cellW = riffCellW(maxWidth: maxWidth)
        // RULE 6, LITERAL: "keeping them square" — the cell is the smaller of its width-derived and
        // height-derived candidate, matching this page's own established "fit always wins over a target"
        // convention elsewhere (the lane grid/riff-panel split uses the identical idea).
        let cellH = min(max(1, rowH), cellW)
        let source = noteSource
        let pool = riffLivePool
        // LIVE STATE (rule, "Live states" §1): MIDI IN with nothing held — no tags anywhere on the grid. An empty
        // pool means NO rank can resolve a note at all, so the tags are suppressed outright below.
        let midiEmpty = source == .midi && pool.isEmpty
        // WALK TAGS (ferry 2026-10-15): `tagCfgs` is built once per body; the overlay re-derives every tag from it
        // each frame. `tagSeats` is the same plan evaluated now, used ONLY for the per-cell VoiceOver labels.
        let tagCfgs = walkTagConfigs(suppress: midiEmpty)
        let tagPlansNow = walkTagPlans(cfgs: tagCfgs, ranks: ranks, beat: walkTagBeat(at: Date()))
        let tagSeats: [WalkTagSeat] = (0..<4).compactMap { i in
            tagPlansNow[i].map { WalkTagSeat(lane: i, col: $0.seatStep, rank: $0.seatRank, facingRight: $0.facingRight) }
        }
        return VStack(alignment: .leading, spacing: sp4) {
            // LOOP SLOTS §10.1: the old title/4-tabs/NOT-PLAYING row and the column-number row are GONE —
            // replaced by the 54pt slot row (two tiles + a foot per slot, §10.3).
            slotRow(maxWidth: maxWidth)
            HStack(spacing: sp4) {
                riffNoteLabelColumn(pool: pool, source: source, cellH: cellH)
                // DRAGGABLE (see `riffDragLastCell`'s own doc comment above): the matrix VStack carries no
                // gesture of its own anymore — a single clear overlay, sized to its EXACT pixel footprint,
                // sits on top and owns the one gesture for the whole grid, matching `sliderLane`'s own
                // established "one gesture over the whole lane" shape.
                let gridW = cellW * CGFloat(n) + sp4 * CGFloat(max(0, n - 1))
                let gridH = cellH * 8 + sp4 * 7
                ZStack(alignment: .topLeading) {
                    VStack(spacing: sp4) {
                        ForEach((1...8).reversed(), id: \.self) { rank in
                            HStack(spacing: sp4) {
                                ForEach(0..<n, id: \.self) { col in
                                    riffGridCell(col: col, rank: rank, ranks: ranks, cellW: cellW, cellH: cellH, n: n, seats: tagSeats, jammed: jamRank(col) != nil)
                                }
                            }
                        }
                    }
                    // Overlay (not a ZStack sibling): its frame is deliberately a few points larger than the grid so a
                    // wrap thread's 2pt overshoot is never clipped, and an overlay's size can't change the layout.
                    .overlay(alignment: .topLeading) {
                        riffWalkTagOverlay(cfgs: tagCfgs, ranks: ranks, cellW: cellW, cellH: cellH, gridW: gridW, gridH: gridH)
                    }
                    Color.clear
                        .frame(width: gridW, height: gridH)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            let col = max(0, min(n - 1, Int(g.location.x / max(1, cellW + sp4))))
                            let rankRow = max(0, min(7, Int(g.location.y / max(1, cellH + sp4))))
                            let rank = 8 - rankRow
                            guard (col, rank) != (riffDragLastCell?.col ?? -1, riffDragLastCell?.row ?? -1) else { return }
                            riffSetRank(col: col, rank: rank, n: n, toggle: riffDragLastCell == nil)
                            riffDragLastCell = (col, rank)
                        }.onEnded { _ in riffDragLastCell = nil })
                    // §11.3: HOLD NOTES TO PLAY no longer takes its own row — it floats over the grid,
                    // non-hit-testable (the cells beneath still edit).
                    if midiEmpty {
                        Text("HOLD NOTES TO PLAY").font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(hex: 0xAAB0BA))
                            .padding(.horizontal, sp8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x15161A).opacity(0.9)))
                            .frame(width: gridW, height: gridH)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(sp8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }
    /// Rule 2, literal: one label per rank row, right-aligned, 11pt bold `#dfe3ea`, rank 8 at top (matching
    /// the grid's own `(1...8).reversed()` order so a label never lands beside the wrong rank). An empty
    /// pool (MIDI IN, nothing held) shows "–" in `#4A4E57` on every row (Live states §1) instead of a note
    /// name. "For MIDI IN and CHORD, spell flats by default" (rule 2) — only KEY keeps the existing
    /// root-driven sharp/flat choice (`euclideousKeyIsFlat`).
    private func riffNoteLabelColumn(pool: [UInt8], source: EuclideousLaneSource, cellH: CGFloat) -> some View {
        // DEAD-CODE FIX (2026-10-13 adversarial review): `euclideousGlobalPoolExtended` was built specifically
        // to feed THIS label column with the correct octave-extended note for ranks beyond the raw held-note
        // count, but was never actually wired in — every rank past `pool.count` showed a plain "–" even though
        // the real strike path (`riffResolve(wrap: .fold)`) will happily sound an octave-up copy of the pool
        // there. `extended` is empty exactly when `pool` is (nothing held, still shows "–"), else always 8
        // entries. Real-vs-copy dimming mirrors the MELODY tab's own established convention for the same
        // distinction.
        let extended = euclideousGlobalPoolExtended(sortedRaw: pool.map { Int($0) })
        return VStack(spacing: sp4) {
            ForEach((1...8).reversed(), id: \.self) { rank in
                let hasNote = rank >= 1 && rank <= extended.count
                let noteValue = hasNote ? UInt8(extended[rank - 1]) : 0
                let isReal = rank <= pool.count
                // FERRY (2026-10-14 §1): "for MIDI IN and CHORD, spell flats by default" is RETIRED — spell
                // relative to the actually-held chord instead (see `euclideousDisplayNoteName`'s own doc).
                let label: String = hasNote ? euclideousDisplayNoteName(noteValue, source: source, pool: pool, keyRoot: keyRoot, keyType: keyType) : "–"
                Text(label).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(hasNote ? (isReal ? Color(hex: 0xDFE3EA) : Color(hex: 0xDFE3EA).opacity(0.55)) : Color(hex: 0x4A4E57))
                    .frame(width: riffLabelColW, height: cellH, alignment: .trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hasNote ? "Rank \(rank), \(euclideousAccessibleDisplayNoteName(noteValue, source: source, pool: pool, keyRoot: keyRoot, keyType: keyType))" : "Rank \(rank), no note")
            }
        }
        .frame(width: riffLabelColW)
    }
    // riffSourceTabs REMOVED ENTIRE (Paul 2026-10-14: "move the midi in/chords/key control to the top
    // header bar and restyle") — superseded by `headerSourceGroup()` above; confirmed zero remaining call
    // sites before deleting. The shared `EuclideousRiffTabFramePreferenceKey` anchor mechanism survives,
    // now published by the header's own KEY chip instead.

    /// The one write path for the riff grid, shared by every cell the drag gesture crosses (see
    /// `riffDragLastCell`'s doc comment). `toggle: true` (the first cell of a gesture) reproduces the
    /// original tap behaviour exactly — set it, unless it's already this rank, in which case clear it to
    /// rest; `toggle: false` (every later cell in the same drag) always sets, so painting across the grid
    /// never accidentally clears a column it merely passes back over.
    private func riffSetRank(col: Int, rank: Int, n: Int, toggle: Bool) {
        // LOOP SLOTS §2.5/§6.2: with nothing playing, edits change the live grid and stick; while a slot
        // plays, the SAME gesture makes a JAM instead (temporary, never written to the slot itself).
        guard playingSlot == nil else {
            let newRank = (toggle && jamRank(col) == rank) ? 0 : rank
            onJam(col, newRank)
            return
        }
        onEditLiveGrid { r in
            var rr = (0..<n).map { k -> Int in let rv = r.ranksResolved; return k < rv.count ? rv[k] : 0 }
            if col < rr.count { rr[col] = (toggle && rr[col] == rank) ? 0 : rank }
            r.ranks = rr; r.steps = n
        }
    }

    // MARK: - WALK TAGS WITH THREADS (ferry 2026-10-15)
    //
    // Each riff-on lane draws an arrow-shaped TAG on the shared grid, in the lane's colour, pointing the way its walk
    // is about to move, with a THREAD to the seat it takes at its next advance; at each advance the tag travels the
    // thread and ARRIVES at the advance's scheduled time. This SUPERSEDES the 2026-10-13 per-cell corner chip +
    // triangle (the dark chip and its 7.5pt triangle are removed) — only the lane → corner mapping survives, as the
    // tag's seat inside each block (`euclideousTagRect`). All the maths lives in Derivations.swift
    // (`euclideousWalkTagPlan` / `euclideousTagDrawing`), pure and unit-tested; this section only decides WHICH lanes
    // show a tag and paints what those functions return.

    /// One lane's resting position, for the per-cell VoiceOver label only (the picture is the Canvas overlay below).
    private struct WalkTagSeat { let lane: Int; let col: Int; let rank: Int; let facingRight: Bool }

    /// When a lane shows a tag at all — the rules the old marker followed, unchanged: riff ON; not SHADOWing (its
    /// own riff is overridden entirely, LISTEN §6); and the grid must be showing the riff that is actually playing
    /// (editing another tab hides the tags, they'd be resolved against the wrong riff). MIDI-IN-with-nothing-held
    /// suppression is applied by the caller.
    private func walkTagShows(_ i: Int) -> Bool {
        // LOOP SLOTS: there is only ONE grid now (the effective grid, §11.1) — the old "is the editing
        // tab the one actually playing" disagreement this guarded against no longer exists.
        guard i < min(4, lines.count), lines[i].riffOnResolved, lines[i].listenPitchMode != .shadow else { return false }
        return true
    }
    private func walkTagConfigs(suppress: Bool) -> [EuclideousWalkLaneConfig?] {
        let cyc = clock.stepBeats * Double(max(1, clock.cols))
        return (0..<4).map { i in
            guard !suppress, walkTagShows(i) else { return nil }
            return euclideousWalkLaneConfig(lane: i, lines: lines, cyc: cyc, resetSpanBars: resetSpanBars,
                                            lanesSeqRate: lanesSeq.rate, lanesSeqLen: lanesSeq.len,
                                            swingPercent: clock.swing, stepBeats: clock.stepBeats, beatsPerBar: clock.beatsPerBar, tempo: clock.tempo)
        }
    }
    /// The UI clock's beat at `date` — the same `anchor + elapsed × tempo` extrapolation every other live view on
    /// this page uses (frozen at the anchor while the transport is stopped).
    private func walkTagBeat(at date: Date) -> Double {
        clock.playing ? clock.anchor + date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
    }
    private func walkTagPlans(cfgs: [EuclideousWalkLaneConfig?], ranks: [Int], beat: Double) -> [EuclideousWalkTagPlan?] {
        let spb = 60.0 / max(1.0, clock.tempo)
        return (0..<4).map { i in
            guard let cfg = cfgs[i], i < riffPositions.count, i < lines.count else { return nil }
            return euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: spb, polledStep: riffPositions[i],
                                         running: clock.playing && lines[i].enabledResolved)
        }
    }

    /// The tags + threads, drawn OVER the matrix and UNDER the (transparent) drag gesture overlay: blocks, then all
    /// threads, then all tags; within threads and within tags in lane order red, blue, yellow, green (green on top).
    /// One `TimelineView` for the whole overlay (the 2026-10-11 DSP lesson: never one per cell), paused while the
    /// transport is stopped — a stopped transport draws the tags once, with no threads (nothing is scheduled).
    private func riffWalkTagOverlay(cfgs: [EuclideousWalkLaneConfig?], ranks: [Int], cellW: CGFloat, cellH: CGFloat, gridW: CGFloat, gridH: CGFloat) -> some View {
        let pad: CGFloat = 8   // room for a wrap thread's 2pt overshoot past the grid's outer edges (and stroke widths)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.playing)) { tl in
            Canvas { ctx, _ in
                let beat = walkTagBeat(at: tl.date)
                let plans = walkTagPlans(cfgs: cfgs, ranks: ranks, beat: beat)
                let drawings: [EuclideousTagDrawing?] = (0..<4).map { i in
                    plans[i].map { euclideousTagDrawing(lane: i, plan: $0, cellW: cellW, cellH: cellH, gap: sp4) }
                }
                ctx.translateBy(x: pad, y: pad)
                for i in 0..<4 { if let t = drawings[i]?.thread { drawWalkThread(&ctx, lane: i, t) } }
                for i in 0..<4 { if let d = drawings[i] { drawWalkTag(&ctx, lane: i, d, cellW: cellW, cellH: cellH) } }
                #if DEBUG
                logWalkTagArrivals(plans)
                #endif
            }
            .frame(width: gridW + pad * 2, height: gridH + pad * 2)
        }
        .frame(width: gridW + pad * 2, height: gridH + pad * 2)
        .offset(x: -pad, y: -pad)
        .allowsHitTesting(false)
    }
    private func drawWalkThread(_ ctx: inout GraphicsContext, lane: Int, _ g: EuclideousThreadGeometry) {
        EuclideousWalkTagPainter.drawThread(&ctx, accent: laneAccents[lane % laneAccents.count], g)
    }
    private func drawWalkTag(_ ctx: inout GraphicsContext, lane: Int, _ d: EuclideousTagDrawing, cellW: CGFloat, cellH: CGFloat) {
        EuclideousWalkTagPainter.drawTag(&ctx, lane: lane, accent: laneAccents[lane % laneAccents.count], d, cellW: cellW, cellH: cellH)
    }

    #if DEBUG
    /// Device log for the timing check (ferry §6): "ARRIVE lane step t" when a tag lands and "HIT lane step t" at the
    /// note-on (lane and step 1-based; t in seconds on the CACurrentMediaTime timeline). ARRIVE's t is the tag's
    /// PREDICTED landing moment on the UI clock (now + the plan's landed offset). HIT's t is the note-on's moment as
    /// the ENGINE stamped it on the host clock (Kernel → Router → the NOTE VIEW event's `hostSeconds`), so
    /// ARRIVE − HIT is the UI-clock-vs-engine error the ferry's 17ms bar is about. Caveats: only hits that PLAY have a
    /// HIT (a rest raises no engine event); only the newest event per lane per poll is seen; a host that supplies no
    /// valid host time falls back to a UI-clock estimate, marked with "~" (and then the pair says nothing about the
    /// engine).
    final class EuclideousWalkTagLog {
        var lastLanded: [Int64?] = [nil, nil, nil, nil]
        var lastEvents: [Router.EuclideousNoteViewEventSnapshot?] = [nil, nil, nil, nil]
    }
    private func logWalkTagArrivals(_ plans: [EuclideousWalkTagPlan?]) {
        for i in 0..<4 {
            guard let p = plans[i], let tick = p.landedTick, let landed = p.landedSeconds else { walkTagLog.lastLanded[i] = nil; continue }
            if walkTagLog.lastLanded[i] != tick {
                walkTagLog.lastLanded[i] = tick
                print(String(format: "ARRIVE %d %d %.4f", i + 1, p.seatStep + 1, CACurrentMediaTime() + landed))
            }
        }
    }
    private func logWalkTagHits(_ evs: [Router.EuclideousNoteViewEventSnapshot?]) {
        let spb = 60.0 / max(1.0, clock.tempo)
        let beatNow = walkTagBeat(at: Date())
        for i in 0..<min(4, evs.count) {
            guard let ev = evs[i], ev.column >= 0, ev != walkTagLog.lastEvents[i] else { continue }
            walkTagLog.lastEvents[i] = ev
            if ev.hostSeconds > 0 {
                print(String(format: "HIT %d %d %.4f", i + 1, Int(ev.column) + 1, ev.hostSeconds))
            } else {
                print(String(format: "HIT~ %d %d %.4f", i + 1, Int(ev.column) + 1, CACurrentMediaTime() - (beatNow - ev.onsetBeat) * spb))
            }
        }
    }
    #endif

    /// One riff-grid matrix cell: the plain on/off fill and ambient border, plus the VoiceOver label for any lane
    /// whose tag currently sits here. The tags themselves are NOT drawn per cell any more — they travel between
    /// cells, so they live in `riffWalkTagOverlay`.
    private func riffGridCell(col: Int, rank: Int, ranks: [Int], cellW: CGFloat, cellH: CGFloat, n: Int, seats: [WalkTagSeat] = [], jammed: Bool = false) -> some View {
        let on = col < ranks.count && ranks[col] == rank
        let here = seats.filter { $0.col == col && $0.rank == rank }
        // §6.2/§11.2: a jammed cell's lit fill draws at 42% — the existing OFF-dim value — so it reads as
        // temporary; a column jammed to rest already shows a plain rest (on == false), no change needed.
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(on ? Color.white.opacity(jammed ? 0.42 : 0.85) : Color.white.opacity(0.08))
                // rule 5: "keeps its light selection border" — an ambient 1pt light border on every cell,
                // unconditionally.
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .frame(width: cellW, height: cellH)
        // The per-cell gesture is GONE — `riffGridView`'s own drag overlay owns tap AND drag for the whole matrix.
        // ACCESSIBILITY (ferry's own literal text: "Step 3, E♭, lane 1 here, next up"). The note name resolves
        // `riffLivePool` at this cell's own rank — omitted (bare "Step N") only when the pool doesn't currently reach
        // it. Routed through the shared `euclideousDisplayNoteName` dispatcher (2026-10-14 ferry §1: one name per note
        // everywhere, honouring the actual note source).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(here.isEmpty ? "" : {
            let noteName = (rank >= 1 && rank <= riffLivePool.count) ? euclideousDisplayNoteName(riffLivePool[rank - 1], source: noteSource, pool: riffLivePool, keyRoot: keyRoot, keyType: keyType) : nil
            let stepPart = noteName.map { "Step \(col + 1), \($0)" } ?? "Step \(col + 1)"
            return here.map { "\(stepPart), lane \($0.lane + 1) here, \($0.facingRight ? "next up" : "next down")" }.joined(separator: "; ")
        }())
    }


    // MARK: - SEQUENCER PANEL (2026-10-14 ferry) — REPLACES the NOTE VIEW panel above (same size/position at
    // both call sites, `portraitLayout`/`landscapeLayout` just swap which function they call). Two tabs:
    // LANES (which of the 4 lanes sounds each step) and RIFFS (which of the 4 riffs plays each step) — both
    // a small step-clock grid over its own ON/RATE/LEN controls. "The step clock always runs" (§4): the grid
    // and its live playhead highlight both read unconditionally from `lanesSeqStep`/`riffsSeqStep`,
    // independent of either sequencer's own ON state (ON only gates whether the engine actually MUTES/
    // SWITCHES — see Router.swift's own `lanesSeqMuted`/`playingRiffIdx`).
    //
    // PIXEL NOTE, flagged honestly (per this page's own standing disclosure convention): the ratified
    // ferry's own literal frame math did not survive verbatim into this implementation session — only a
    // distilled summary did, via the approved plan (an `x = 41.5+43c, y = 56+47r, w:40, h:44`-style absolute
    // formula, evidently anchored to one specific reference card width this session has no way to confirm).
    // Built instead with PROPORTIONAL cell sizing derived from the panel's own real available width/height —
    // the same "share the extra width across stretching items" convention this page's own other ferries
    // already fall back to when an exact pixel table isn't in hand — rather than reproducing an absolute
    // formula that could silently clip or float wrong at any width but the one it was written against.
    // DEVICE-OWED, as always for this page's pixel-level claims.
    // STUB (§10, open): "where do silence messages go" was explicitly left OPEN by the 2026-10-14 ferry —
    // raised back to the design channel 2026-10-14, do NOT implement without confirmation. The note-flow
    // panel this feature retired was the only surface that ever called `euclideousSilenceReason`
    // (Derivations.swift) — that pure function and its own tests are UNTOUCHED, just orphaned (zero UI call
    // sites now), ready to be wired into wherever §10 lands once it's answered. Not reused here as a guess.
    private func sequencerPanel(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let innerW = max(1, maxWidth - sp8 * 2)
        let innerH = max(1, maxHeight - sp8 * 2)
        let tabRowH: CGFloat = 20
        // Controls row was ~33pt against the ferry's own 44 (2026-10-14 fixes-after-build ferry §1) — the
        // ratio to the reference panel (307 total) is roughly 44/307 ≈ 0.143; applied proportionally here
        // rather than a literal 44, same convention as every other size on this page.
        let controlsRowH: CGFloat = max(1, innerH * 44 / 307)
        let gridH = max(1, innerH - tabRowH - controlsRowH - sp4 * 2)
        return VStack(spacing: sp4) {
            sequencerTabRow(width: innerW, height: tabRowH)
            Group {
                if sequencerTab == 0 { sequencerLanesGrid(width: innerW, height: gridH) }
                else { sequencerRiffsGrid(width: innerW, height: gridH) }
            }
            .frame(width: innerW, height: gridH)
            sequencerControlsRow(width: innerW, height: controlsRowH)
        }
        .padding(sp8)
        .frame(width: maxWidth, height: maxHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }
    /// Tab row (2026-10-14 ferry §1, corrected after a self-audit against the raw ferry text — the first
    /// build dropped the per-tab ON/OFF dot and the "STEP N OF LEN" status entirely): each tab shows its own
    /// name beside a dot (filled when that tab's sequencer is ON, hollow when OFF); a trailing status reads
    /// the CURRENTLY SELECTED tab's own live step/len (so it always describes whichever grid is on screen).
    private func sequencerTabRow(width: CGFloat, height: CGFloat) -> some View {
        let len = sequencerTab == 0 ? lanesSeq.len : riffsSeq.len
        let step = sequencerTab == 0 ? lanesSeqStep : riffsSeqStep
        // "TAP = RESTART" (2026-10-15 ferry §5): while any lane's RESET is held, this slot's own live step
        // readout is replaced by the hold's own status line, in the lowest-numbered held lane's colour ("if
        // several are held").
        let heldLane = restartEditLanes.min()
        return HStack(spacing: sp4) {
            ForEach(0..<2, id: \.self) { i in
                let sel = sequencerTab == i
                let on = i == 0 ? lanesSeq.on : riffsSeq.on
                HStack(spacing: 6) {
                    Text(i == 0 ? "LANES" : "RIFFS")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(sel ? .white : Color(hex: 0xAAB0BA))
                    Circle()
                        .fill(on ? Color(hex: 0xF2F4F7) : Color.clear)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(hex: 0xAAB0BA), lineWidth: on ? 0 : 1.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if sel { Rectangle().fill(Color.white).frame(height: 2) }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    sequencerTab = i
                    resetPopupLane = nil   // §6: "switching tabs closes it"
                }
            }
            if let heldLane {
                Text("TAP = RESTART")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(lane100(laneAccents[heldLane % laneAccents.count]))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text("STEP \(max(1, step + 1)) OF \(max(1, len))")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(Color(hex: 0x8A909A))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: width, height: height)
    }
    /// LANES grid (2026-10-14 ferry §1/§2 — REBUILT after a self-audit against the raw ferry text found 3
    /// real gaps in the first build): ALWAYS 8 fixed columns (not reflowed to LEN), so the column x-positions
    /// never shift and stay lined up under the main riff grid above — same leading-column/`cellW` formula
    /// `riffGridView` already uses, not independently re-derived, for exactly that reason; a step beyond LEN
    /// just dims to 30% rather than disappearing. The per-lane RESET box (§2) now lives HERE at the start of
    /// each row — moved off the RHYTHM tab, where the first build had wrongly placed it. Restart marks are
    /// real 3pt-wide bars (not a 3×3 dot), ink-coloured depending on whether that step is lit, bounded to LEN.
    private func sequencerLanesGrid(width: CGFloat, height: CGFloat) -> some View {
        let n = 8
        let len = max(1, min(8, lanesSeq.len))
        let headerH: CGFloat = 14
        // ROW GAPS (2026-10-14 fixes-after-build ferry §1): `VStack(spacing: 0)` between the 4 rows was the
        // actual cause of "rows merge" — reusing `sp4` here (not the ferry's own literal 3pt) is a deliberate,
        // disclosed judgment call: the ferry's own "3pt, the same as between columns" is a DESCRIPTIVE fact
        // about ITS OWN pixel table, not an instruction to retune this page's already-established `sp4`
        // column-gap token to a different value — reusing the one token keeps rows and columns provably
        // consistent with each other without introducing a second gap constant.
        let rowGap = sp4
        let rowsH = max(1, height - headerH - sp4)
        let cellH = max(1, (rowsH - rowGap * 3) / 4)
        let gridW = max(1, width - riffLabelColW - sp4)
        let cellW = max(1, (gridW - sp4 * CGFloat(n - 1)) / CGFloat(n))
        let cells = lanesSeq.cells
        let curStep = max(0, min(n - 1, lanesSeqStep))
        let seqOn = lanesSeq.on   // §5 (Paul to confirm): an OFF sequencer's own grid dims to 42%

        // 2026-10-15 ferry §2.3/§3/§5: marks now read the resolved MASK directly (one bit per step) instead
        // of re-deriving "is this a multiple of resetSteps" — the SAME data `euclideousMaskedResetOrigin`
        // resolves against in the engine, no second derivation. `editingThisLane` switches to the §5 edit-
        // mode visuals (bright bar / dashed "tap here" slot); outside edit mode this is BYTE-IDENTICAL to the
        // shipped visual (§5: "outside edit mode, marks look exactly as shipped... now drawn from the
        // resolved mask" — only the boolean test's SOURCE changed, not one shipped pixel value, since "where
        // source disagrees [with the ferry's own screenshot measurement], source wins").
        func restartBar(lane: Int, step: Int, lit: Bool, editingThisLane: Bool) -> some View {
            // §1.3: bits at/beyond LEN are drawn too (the enclosing cell's own existing beyond-LEN
            // `.opacity(within ? 1 : 0.3)` dims them, same as everything else in that cell) — NOT hidden,
            // so a mark never silently "disappears" when LEN is shrunk past it.
            let mask = lane < lines.count ? lines[lane].restartMaskResolved : 0
            let marked = (mask & (1 << step)) != 0
            return Group {
                if editingThisLane {
                    let barH = max(2, cellH - 8)
                    if marked {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: 0xF2F4F7))
                            .frame(width: 4, height: barH)
                    } else {
                        Path { p in p.move(to: CGPoint(x: 0.75, y: 0)); p.addLine(to: CGPoint(x: 0.75, y: barH)) }
                            .stroke(Color(hex: 0x5C626C), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 1.5, height: barH)
                    }
                } else if marked {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lit ? Color(hex: 0x0D0F14) : Color(hex: 0x5C626C))
                        .frame(width: 3, height: min(26, max(2, cellH - 10)))
                }
            }
            .frame(width: cellW, height: cellH, alignment: .topLeading)
            .padding(.leading, editingThisLane ? 2 : 4).padding(.top, editingThisLane ? 4 : 6)
            .allowsHitTesting(false)
        }

        // The CURRENT-STEP HIGHLIGHT now spans the FULL column — header row included (§1: "y 38, height
        // 205" covers the column-numbers row too, not just the 4 data rows) — so the header and the data
        // rows share ONE ZStack/VStack instead of the header sitting outside it.
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                .frame(width: cellW + sp4, height: height)
                .offset(x: riffLabelColW + sp4 + CGFloat(curStep) * (cellW + sp4) - sp4 / 2)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: sp4) {
                HStack(spacing: sp4) {   // header: "RESET" label (§2) + column numbers 1-8 (§1) — ALWAYS full
                    // strength (§5: "the step numbers... stay at full strength"), never dimmed by seqOn.
                    // TRUNCATION FIX (§2): letter-spacing removed + `.fixedSize` so "RESET" renders at its own
                    // natural width instead of being clipped by the frame proposing only `riffLabelColW`.
                    Text("RESET").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xAAB0BA))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: riffLabelColW, height: headerH, alignment: .center)
                    ForEach(0..<n, id: \.self) { col in
                        let isCur = col == curStep
                        let within = col < len
                        Text("\(col + 1)").font(.system(size: 10, weight: isCur ? .heavy : .regular, design: .monospaced))
                            .foregroundColor(isCur ? Color(hex: 0xF2F4F7) : (within ? Color(hex: 0x8A909A) : Color(hex: 0x4A4E57)))
                            .frame(width: cellW, height: headerH)
                    }
                }
                VStack(spacing: rowGap) {
                    ForEach(0..<4, id: \.self) { lane in
                        let accent = laneAccents[lane % laneAccents.count]
                        let editingThisLane = restartEditLanes.contains(lane)
                        let anyEditing = !restartEditLanes.isEmpty
                        HStack(spacing: sp4) {
                            sequencerResetBox(lane, width: riffLabelColW, height: cellH, cellW: cellW, gap: sp4)
                            ForEach(0..<n, id: \.self) { step in
                                let idx = step * 4 + lane
                                let lit = idx < cells.count ? cells[idx] : true
                                let within = step < len
                                let laneMask = lane < lines.count ? lines[lane].restartMaskResolved : 0
                                let marked = within && (laneMask & (1 << step)) != 0
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(editingThisLane && lit ? lane20(accent) : (lit ? lane100(accent) : Color(hex: 0x22252C)))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(editingThisLane && lit ? lane40(accent) : Color.clear, lineWidth: 1))
                                    .frame(width: cellW, height: cellH)
                                    .overlay(restartBar(lane: lane, step: step, lit: lit, editingThisLane: editingThisLane))
                                    .opacity(within ? 1 : 0.3)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if editingThisLane {
                                            // §4.3: a tap on the HELD lane's own step toggles its restart
                                            // mark; it never changes mute.
                                            edit(lane) { $0.restartMask = $0.restartMaskResolved ^ (1 << step) }
                                        } else if !anyEditing {
                                            // §4.3: "taps on other lanes' steps do nothing" while any RESET
                                            // is held — mute only toggles when nothing is being edited.
                                            onEditLanesSeq { s in
                                                guard idx < s.cells.count else { return }
                                                s.cells[idx].toggle()
                                            }
                                        }
                                    }
                                    // §4.9: VoiceOver can't do the hold — a custom action always offers the
                                    // mark toggle, independent of edit mode. "restarts here" is the cell's
                                    // VALUE (its current state), not part of its label — the literal split the
                                    // ferry draws, matching how a stateful control's label/value normally work.
                                    .accessibilityLabel("Lane \(lane + 1), step \(step + 1)")
                                    .accessibilityValue(marked ? "restarts here" : "")
                                    .accessibilityAction(named: "Toggle restart") {
                                        edit(lane) { $0.restartMask = $0.restartMaskResolved ^ (1 << step) }
                                    }
                            }
                        }
                        // §5: the HELD lane's own row shows at full strength even while LANES is OFF; every
                        // other row keeps the existing OFF-dim (42%) AND dims to the SAME 42% while a
                        // DIFFERENT lane is held, reusing the one existing dim value for both reasons.
                        .opacity(editingThisLane ? 1 : ((anyEditing || !seqOn) ? 0.42 : 1))
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
    /// RIFFS grid (2026-10-14 ferry §1/§3 — REBUILT after the same self-audit): ALWAYS 8 fixed columns,
    /// aligned with the riff grid above via the identical formula `sequencerLanesGrid` uses. RADIO per
    /// column (exactly one lit cell per step), same one-of-N-per-column shape `stateMatrixRadio` uses
    /// elsewhere, hand-built since the per-cell bar-chart preview doesn't fit that shared widget. Each row
    /// now carries a PERSISTENT leading label (riff number + mini-outline, §3) — entirely missing from the
    /// first build, which only showed the outline as a fading overlay on whichever cell happened to be lit.
    private func sequencerRiffsGrid(width: CGFloat, height: CGFloat) -> some View {
        let n = 8
        let len = max(1, min(8, riffsSeq.len))
        let headerH: CGFloat = 14
        let rowGap = sp4   // see sequencerLanesGrid's own doc comment on this choice
        let rowsH = max(1, height - headerH - sp4)
        let cellH = max(1, (rowsH - rowGap * 3) / 4)
        let gridW = max(1, width - riffLabelColW - sp4)
        let cellW = max(1, (gridW - sp4 * CGFloat(n - 1)) / CGFloat(n))
        let cells = riffsSeq.cells
        let curStep = max(0, min(n - 1, riffsSeqStep))
        let seqOn = riffsSeq.on

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                .frame(width: cellW + sp4, height: height)
                .offset(x: riffLabelColW + sp4 + CGFloat(curStep) * (cellW + sp4) - sp4 / 2)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: sp4) {
                HStack(spacing: sp4) {   // §3: "no reset boxes or marks on this tab" — leading slot stays blank
                    Color.clear.frame(width: riffLabelColW, height: headerH)
                    ForEach(0..<n, id: \.self) { col in
                        let isCur = col == curStep
                        let within = col < len
                        Text("\(col + 1)").font(.system(size: 10, weight: isCur ? .heavy : .regular, design: .monospaced))
                            .foregroundColor(isCur ? Color(hex: 0xF2F4F7) : (within ? Color(hex: 0x8A909A) : Color(hex: 0x4A4E57)))
                            .frame(width: cellW, height: headerH)
                    }
                }
                VStack(spacing: rowGap) {
                    ForEach(0..<4, id: \.self) { riffIdx in
                        HStack(spacing: sp4) {
                            // RIFFS tab row label (2026-10-14 "riff icon redesign" ferry, literal): "the riff
                            // number above the icon, 3pt apart, centred" — the bar-chart outline is gone,
                            // replaced by the same fixed mini-grid the tabs use, with this panel's own
                            // #15161A-background colours (notes #DFE3EA, dots #3A3E47).
                            VStack(spacing: 3) {
                                Text("\(riffIdx + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundColor(Color(hex: 0xDFE3EA))
                                // §5.6: the slot playing now shows its CURRENT (effective) ranks; the
                                // others show their start ranks; an empty slot shows the icon with no
                                // marks at 42% (the pervasive OFF-dim value).
                                riffMiniIcon(ranks: riffIdx == playingSlot ? effectiveGridRanks : (loopSlots[safe: riffIdx]?.startRanksResolved ?? []),
                                             noteColor: Color(hex: 0xDFE3EA), dotColor: Color(hex: 0x3A3E47))
                                    .opacity((loopSlots[safe: riffIdx]?.isFilled == true || riffIdx == playingSlot) ? 1 : 0.42)
                            }
                            .frame(width: riffLabelColW, height: cellH)
                            ForEach(0..<n, id: \.self) { step in
                                let sel = step < cells.count && cells[step] == riffIdx
                                let within = step < len
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(sel ? Color(hex: 0xDFE3EA) : Color(hex: 0x22252C))
                                    .frame(width: cellW, height: cellH)
                                    .opacity(within ? 1 : 0.3)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onEditRiffsSeq { cfg in
                                            guard step < cfg.cells.count else { return }
                                            cfg.cells[step] = riffIdx
                                        }
                                    }
                            }
                        }
                    }
                }
                .opacity(seqOn ? 1 : 0.42)   // §5: grid cells + row labels dim when RIFFS is off
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
    /// ON toggle + RATE + LEN, for whichever tab is currently selected — the controls apply to that
    /// sequencer only, matching the tab's own content directly below. RATE gets noticeably MORE width than
    /// LEN (182:142 in the ferry's own literal table — a 1.28:1 ratio, scaled here to whatever real width
    /// is actually available, same "share the extra width proportionally" convention this page already uses
    /// elsewhere) — found missing by a self-audit: the first build gave both the SAME fixed 69.5pt, which
    /// risks truncating RATE's own longer values ("¼ BAR", "4 BARS") against LEN's bare single digit.
    private func sequencerControlsRow(width: CGFloat, height: CGFloat) -> some View {
        let isLanes = sequencerTab == 0
        let on = isLanes ? lanesSeq.on : riffsSeq.on
        let rate = isLanes ? lanesSeq.rate : riffsSeq.rate
        let len = isLanes ? lanesSeq.len : riffsSeq.len
        let onW: CGFloat = 56
        let remaining = max(1, width - onW - sp8 * 2)
        let rateW = remaining * 182 / (182 + 142)
        let lenW = remaining - rateW
        return HStack(spacing: sp8) {
            // ON/OFF (§1: "ON: fill #dfe3ea, text INK. OFF: fill #2a2d34, text #aab0ba") — found missing by
            // the same self-audit: the first build never flipped the BACKGROUND, only the text colour, so
            // the on/off state read far less clearly than the ferry's own strong fill-flip intends.
            Text(on ? "ON" : "OFF")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(on ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .frame(width: onW, height: height)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture {
                    if isLanes { onEditLanesSeq { $0.on.toggle() } } else { onEditRiffsSeq { $0.on.toggle() } }
                }
            sequencerRateStepper(rate, width: rateW, height: height) { v in
                if isLanes { onEditLanesSeq { $0.rate = v } } else { onEditRiffsSeq { $0.rate = v } }
            }
            melodyStepper("LEN", value: len, range: 1...8, width: lenW) { v in
                if isLanes { onEditLanesSeq { $0.len = v } } else { onEditRiffsSeq { $0.len = v } }
            }
        }
        .frame(width: width, height: height)
    }
    /// A RATE stepper matching `melodyStepper`'s own visual shell exactly, but stepping through
    /// `EuclideousSeqRate.allCases` (an enum, not a plain Int range) by index. Takes an explicit `width` now
    /// (was a hardcoded 69.5, same as LEN) so it can be proportionally wider per `sequencerControlsRow`.
    private func sequencerRateStepper(_ rate: EuclideousSeqRate, width: CGFloat, height: CGFloat, onChange: @escaping (EuclideousSeqRate) -> Void) -> some View {
        let all = EuclideousSeqRate.allCases
        let idx = all.firstIndex(of: rate) ?? 2
        let arrowZone: CGFloat = 18
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34))
            HStack(spacing: 0) {
                Text("‹").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    .frame(width: arrowZone, height: height)
                VStack(spacing: 2) {
                    Text("RATE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    Text(rate.rawValue)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                Text("›").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                    .frame(width: arrowZone, height: height)
            }
        }
        .frame(width: width, height: height)
        .overlay(
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { onChange(all[max(0, idx - 1)]) }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { onChange(all[min(all.count - 1, idx + 1)]) }
            }
        )
    }
    /// THE MINI RIFF GRID (2026-10-14 ferry "riff icon redesign" — REPLACES the bar-chart outline entire, in
    /// both places it appeared: the riff-tab title row and the RIFFS-tab row labels). A literal fixed 31×23pt
    /// grid — NOT scaled to its container, unlike the bar-chart it replaces, since the ferry names this as a
    /// literal pixel asset (8 columns of steps, 4pt pitch; 8 rows of ranks 8-top/1-bottom, 3pt pitch) rather
    /// than a proportionally-resized abstraction. A step with a note at rank r draws a 3×2pt mark (radius
    /// 0.5) at that row; every OTHER row for that step gets a 1×1pt dot — so a rest (rank 0, or past the
    /// end of a short `ranks` array) is a full column of dots, and an empty riff is dots throughout. Shows
    /// the riff exactly as stored — no lane's INV/TRANS/octave applies, satisfied for free since `ranks` is
    /// already each riff's own `.ranksResolved` (a riff-level resolve, never a lane-level transform).
    private func riffMiniIcon(ranks: [Int], noteColor: Color, dotColor: Color) -> some View {
        Canvas { ctx, _ in
            for step in 0..<8 {
                let r = step < ranks.count ? ranks[step] : 0
                let noteRow = (r >= 1 && r <= 8) ? (8 - r) : -1   // row index 0...7 from the top; -1 = rest, no row matches, so every row below draws a dot
                let x = CGFloat(step) * 4
                for row in 0..<8 {
                    if row == noteRow {
                        let rect = CGRect(x: x, y: CGFloat(row) * 3, width: 3, height: 2)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(noteColor))
                    } else {
                        let rect = CGRect(x: x + 1, y: CGFloat(row) * 3 + 0.5, width: 1, height: 1)
                        ctx.fill(Path(rect), with: .color(dotColor))
                    }
                }
            }
        }
        .frame(width: 31, height: 23)
    }

    private func euclideousDragHUD(_ info: EuclidDragHUDInfo) -> some View {
        VStack(spacing: 5) {
            Text(info.label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text(info.primary)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(info.secondary)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.6)).lineLimit(1)   // matches `primary`'s own treatment above
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }
}
// LOOP SLOTS (FERRY "loop slots replace the riff tabs") — file-private, mirrors the identical (also
// file-private, so no conflict) extension in MacroAuthoring.swift.
private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
