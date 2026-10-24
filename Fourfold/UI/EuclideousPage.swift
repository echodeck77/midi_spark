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
    // RESTART CHAINS ferry §10: `.circle` (the old RHYTHM-tab OUT circle) is retired — kept only because
    // removing the case would also force touching every exhaustive switch below for no behavioural gain; no
    // caller constructs it any more (reported, not silently left reachable). `.tab` now rings the MIX tab
    // chip (unchanged geometry, still what the RHYTHM tab's own ring used); `.mixButton` is new, §10.2's own
    // "the button's rounded rectangle outset by 1pt (radius 7)".
    enum Kind { case circle, tab, mixButton }
    let kind: Kind
    let held: Bool
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    var body: some View {
        Group {
            switch kind {
            case .circle: Circle().stroke(Color(hex: 0xDFE3EA), lineWidth: 2)
            case .tab: RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xDFE3EA), lineWidth: 2).padding(4)
            case .mixButton: RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0xDFE3EA), lineWidth: 2).padding(-1)
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
    // RESTART CHAINS ferry §2.3: "the label-and-value row sits with its top 9 pt below the tile's top
    // instead of centred" — the component can only centre that row today (see `body`'s horizontal branch),
    // so this is the backward-compatible parameter the ferry's own text anticipates: default false keeps
    // every pre-existing call site byte-identical; only the RHYTHM tab's new OFFSET/TILT frames pass true.
    var topAlignLabelRow: Bool = false
    // §2.4: TILT's new EARLY/LATE end labels, drawn only when non-nil (every other field/call site stays
    // byte-identical). (leading, trailing) — RHYTHM tab passes ("EARLY", "LATE"); nothing else does.
    var endLabels: (String, String)? = nil
    // LANE LOCK (2026-10-22): handled INSIDE the control rather than by wrapping modifiers — a `ModifiedContent<EuclideousSlider, …>` temporary would hold this ~4 KB view by value on the 1 MB debug stack.
    // `lockActive` (its lane is locked) counts a finger on it as HELD (6.2); `lockOutline` (the lane colour) draws the dashed "differs from L" frame (5.4). Defaults leave the control exactly as it was.
    var lockActive: Bool = false
    var lockOutline: Color? = nil
    var onLockTouch: ((Bool) -> Void)? = nil
    // RHYTHM POLISH (2026-10-22) §2.1: non-nil (the caption colour) turns the VERTICAL value text into the hero — the number at 36 pt in the middle of the filled part with "OF n" under it (HITS only); every other slider leaves it nil.
    var heroCaption: Color? = nil

    @State private var lockDown = false
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
                let labelRow = HStack {
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
                                .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)   // §1.8: truncate, never shrink — no .minimumScaleFactor anywhere
                        )
                    }
                }
                .padding(.horizontal, 10)
                // §2.3: RHYTHM's new OFFSET/TILT frames pin this row 9pt below the tile's top instead of centring it.
                if topAlignLabelRow {
                    VStack(spacing: 0) { labelRow.padding(.top, 9); Spacer(minLength: 0) }
                } else {
                    labelRow
                }
                // §2.4: TILT's EARLY/LATE end labels — each on the tile's own opaque backing, 8pt in from the
                // tile's side, bottom 5pt above the tile's bottom edge. Visual only: never intercepts touches.
                if let (early, late) = endLabels {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack {
                            Text(early).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.8)
                                .foregroundColor(Color(hex: 0x8A909A))
                                .padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x22252C)))
                            Spacer()
                            Text(late).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.8)
                                .foregroundColor(Color(hex: 0x8A909A))
                                .padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x22252C)))
                        }
                        .padding(.horizontal, 8).padding(.bottom, 4)   // RHYTHM POLISH §1.5: 4 pt above the tile's bottom (was 5) now the rows are 38.67 tall
                    }
                    .allowsHitTesting(false)
                }
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
                    } else if heroCaption == nil {
                        backed(
                            Text(euclideousSliderValueText(field, effectiveLine))
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)   // §1.8: truncate, never shrink — no .minimumScaleFactor anywhere
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
                if let cap = heroCaption { heroBlock(cap, fill: curFrac) }
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
        .overlay { if let c = lockOutline { RoundedRectangle(cornerRadius: 10).stroke(c, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(-3).allowsHitTesting(false) } }
        .onDisappear { if lockDown { lockDown = false; onLockTouch?(false) } }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !edited, !listenFollowLocked else { return }   // ferry, literal: "touches elsewhere on a disabled TILT do nothing" / "[HITS/STEPS/TILT] can't be dragged" while following
                    if lockActive && !lockDown { lockDown = true; onLockTouch?(true) }
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
                    let f = frac(atTravel: horizontal ? g.location.x : g.location.y, length: len)
                    let v = euclideousSliderValueAtDetented(field, line, frac: f)   // RHYTHM POLISH §2.2: OFFSET snaps to a whole step within 0.08, TILT to 0 within 3 %
                    // "NO CHANGE, NO COMMIT" (ferry Touch behaviour §6) — a touch landing on (or staying
                    // within) the band of the value it started at writes nothing.
                    if v != lastCommitted, let snap = snapshot {
                        lastCommitted = v
                        onCommit { l in euclideousSliderCommit(field, &l, snapshot: snap, newValue: v) }
                    }
                }
                .onEnded { g in
                    if lockDown { lockDown = false; onLockTouch?(false) }
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
        .accessibilityValue(euclideousLockAppendSnapWords(edited ? "double-tap to revert" : euclideousSliderAccessibilityValueText(field, effectiveLine), outlined: lockOutline != nil))
        .accessibilityAdjustableAction { direction in
            guard !edited, !listenFollowLocked else { return }
            let cur = euclideousSliderRange(field, line).value
            let target = euclideousSliderAccessibilityTarget(field, current: cur, increment: direction == .increment)
            onCommit { l in euclideousSliderCommit(field, &l, snapshot: line, newValue: target) }
        }
    }

    /// RHYTHM POLISH §2.1 — the hero: the value at 36 pt, "OF n" 2 pt under it in the lightened lane colour, centred horizontally, the block centred on the filled part and clamped (`euclideousHitsHeroTop`). Built as an
    /// `AnyView` (the 1 MB extension stack — Docs/claude-playbook.md); never takes a touch.
    private func heroBlock(_ cap: Color, fill: Double) -> AnyView {
        let top = euclideousHitsHeroTop(tileH: height, fillFraction: fill)
        return AnyView(VStack(spacing: 0) {
            Color.clear.frame(height: top)
            VStack(spacing: EuclideousHitsHero.gap) {
                Text("\(effectiveLine.pulses)").font(.system(size: EuclideousHitsHero.numberSize, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1).frame(height: EuclideousHitsHero.numberSize)
                Text("OF \(effectiveLine.steps)").font(.system(size: EuclideousHitsHero.captionSize, weight: .heavy, design: .monospaced)).tracking(0.8)
                    .foregroundColor(cap).lineLimit(1).frame(height: EuclideousHitsHero.captionBox)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false))
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

/// RESTART CHAINS ferry §2.2 — the STEPS +/− stepper replacing the old STEPS slider. The value box opens
/// the picker on a plain tap and changes STEPS live (1 per 12pt of vertical travel) on a drag; every write
/// (a +/− tap, a drag tick, a picker choice) goes through `euclideousSliderCommit(.steps, ...)` — §2.5's
/// "one setter" — via `onCommit`, which mirrors `editStep`'s own (newStep, mutate) shape so a whole drag
/// coalesces into ONE undo step (`newStep: true` on its first value-changing write only).
struct EuclideousStepsStepper: View {
    let line: EuclidLine
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let onCommit: (_ newStep: Bool, _ mutate: @escaping (inout EuclidLine) -> Void) -> Void
    let onToggleValueBoxTap: () -> Void
    // LANE LOCK (2026-10-22): see EuclideousSlider — inside the control, not wrapping modifiers. `lockMomentary` (locked on the BEAT grid): + and − act at touch-down (6.9).
    var lockActive: Bool = false
    var lockMomentary: Bool = false
    var lockOutline: Color? = nil
    var onLockTouch: ((Bool) -> Void)? = nil

    @State private var lockDown = false
    @State private var dragStartLocation: CGPoint? = nil
    @State private var dragStartSteps: Int? = nil
    @State private var isDragging = false
    @State private var firstWriteDone = false

    private func commitSteps(_ target: Int) {
        guard target != line.steps else { return }
        onCommit(!firstWriteDone) { l in euclideousSliderCommit(.steps, &l, snapshot: l, newValue: Double(target)) }
        firstWriteDone = true
    }

    var body: some View {
        let plusEnabled = line.steps < 16
        let minusEnabled = line.steps > 2
        // §1.3: + at top (36 tall), the value box filling the rest, − at bottom (36 tall), sp4 apart.
        let btnH: CGFloat = 36, gap: CGFloat = 4
        let valueBoxH = max(1, height - btnH * 2 - gap * 2)
        VStack(spacing: gap) {
            stepButton("plus", enabled: plusEnabled, height: btnH) { commitSteps(line.steps < 2 ? 2 : min(16, line.steps + 1)) }
                .accessibilityLabel("More steps, now \(line.steps)")
            VStack(spacing: 2) {
                Text("\(line.steps)").font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
                HStack(spacing: 4) {
                    Text("STEPS").font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(0.85)
                        .foregroundColor(Color(hex: 0x8A909A))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy))
                        .foregroundColor(Color(hex: 0x8A909A))
                }
            }
            .frame(width: width, height: valueBoxH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x22252C)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if lockActive && !lockDown { lockDown = true; onLockTouch?(true) }
                        if dragStartLocation == nil {
                            dragStartLocation = g.location
                            dragStartSteps = line.steps
                            firstWriteDone = false
                        }
                        let dy = g.location.y - (dragStartLocation?.y ?? g.location.y)
                        if abs(dy) > 4 { isDragging = true }
                        guard isDragging, let base = dragStartSteps else { return }
                        let delta = Int((-dy / 12).rounded())   // §2.2: up = more, 1 per 12pt
                        commitSteps(max(2, min(16, base + delta)))
                    }
                    .onEnded { _ in
                        if lockDown { lockDown = false; onLockTouch?(false) }
                        // §2.2: "a touch that became a drag never opens the picker" — only a plain tap (never exceeded 4pt) does.
                        if !isDragging { onToggleValueBoxTap() }
                        dragStartLocation = nil; dragStartSteps = nil; isDragging = false; firstWriteDone = false
                    }
            )
            .accessibilityLabel(euclideousLockAppendSnapWords("Steps, \(line.steps)", outlined: lockOutline != nil))
            .accessibilityHint("Double-tap to pick a length")
            .accessibilityAdjustableAction { direction in
                // §6.2: each VoiceOver swipe is its own undo step, independent of firstWriteDone's
                // drag-gesture coalescing — mirrors the generic slider's own adjustable action.
                let target = direction == .increment ? min(16, line.steps + 1) : max(2, line.steps - 1)
                guard target != line.steps else { return }
                onCommit(true) { l in euclideousSliderCommit(.steps, &l, snapshot: l, newValue: Double(target)) }
            }
            stepButton("minus", enabled: minusEnabled, height: btnH) { commitSteps(line.steps > 16 ? 16 : max(2, line.steps - 1)) }
                .accessibilityLabel("Fewer steps, now \(line.steps)")
        }
        .frame(width: width, height: height)
        .overlay { if let c = lockOutline { RoundedRectangle(cornerRadius: 10).stroke(c, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(-3).allowsHitTesting(false) } }   // LANE LOCK 5.4
        .onDisappear { if lockDown { lockDown = false; onLockTouch?(false) } }
    }
    /// + / −: a plain Button on every lane that isn't locked; a locked lane gets a tap that counts the finger (6.2) — and on the BEAT grid acts at touch-down (6.9).
    @ViewBuilder private func stepButton(_ glyph: String, enabled: Bool, height btnH: CGFloat, action: @escaping () -> Void) -> some View {
        let face = Image(systemName: glyph).font(.system(size: 14, weight: .heavy))
            .foregroundColor(enabled ? Color(hex: 0xAAB0BA) : Color(hex: 0x4A4E57))
            .frame(width: width, height: btnH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
        if lockActive {
            face.contentShape(Rectangle())
                .modifier(EuclideousLaneTap(locked: true, momentary: lockMomentary, onTouch: { onLockTouch?($0) }, action: { if enabled { action() } }))
                .accessibilityAddTraits(.isButton)
        } else {
            Button(action: action) { face }.disabled(!enabled)
        }
    }
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
    // FOUR RIFFS (2026-10-18 ferry, "drop the loop functionality in favour of four riff tabs... with a
    // glyph of the grid showing how it's populated... setup multiple riffs and switch between them") —
    // RESTORES the pre-looper "four riffs, picked by tabs" model (2026-10-14 sequencer-panel ferry),
    // REPLACING the looper's own single `liveGrid`/mode/passes/events entirely. `riffs` is all four
    // stored patterns; `activeRiff` is which one is both EDITED (this grid) and SOUNDING (every lane
    // reads the same shared pattern — "ONE GLOBAL RIFF" ferry, 2026-10-12). The looper's own model
    // fields (`PluginState.euclideousLiveGrid`, `euclideousLooperEvents`) stay decode-only — this page
    // simply never reads or writes them again, matching this project's own "hide, don't delete" rule.
    let riffs: [EuclideousRiff]
    let activeRiff: Int
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
    // FX TAB (2026-10-18 ferry): the page-level FX rows (six rows × the riff's eight columns, per-row lane sets, PASSES / CC / BASE). Read-only here; every
    // edit goes through `onEditFX`, which the VC turns into one document write + one republish.
    let fx: EuclideousFX
    let lanesSeqStep: Int
    let riffsSeqStep: Int
    // RIFF-CELL WIPES (Paul 2026-10-10 ferry) — each lane's latest wipe-eligible event (column/rank >= 0).
    // The SIBLING NOTE VIEW panel state this queue used to ALSO feed (noteViewLastEvent/RestFlash) was
    // removed along with that panel (2026-10-14 sequencer-panel ferry) — this one survives, feeding the
    // riff grid's own walk-arrow markers, a genuinely separate feature.
    let wipeEvents: [Router.EuclideousNoteViewEventSnapshot?]
    // FOURFOLD HEADER (§4.8): each lane's latest real strike of any kind — read ONLY by the output rings' flare.
    let strikeEvents: [Router.EuclideousNoteViewEventSnapshot?]
    // PULSE ferry (2026-10-20): the retained strike feed (velocities, display-clock onsets) every strike effect reads, and the PULSE level (0 OFF · 1 SUBTLE · 2 FULL).
    let pulseFeed: EuclideousPulseFeed
    let pulseLevel: Int
    // PAGE REWORK (Paul 2026-10-07): the new global reset-span/key/source-mode/main-out config (§2.2-§2.4).
    let resetSpanBars: Int
    let keyRoot: Int
    let keyType: ScaleType
    // SWING (2026-10-17, "put the swing control onto the header"): the SAME scene-wide `SceneState.swing`
    // (AUParameter 1, 50 straight … 75) the main workbench's own ArrangementBar slider already edits — this
    // is a second UI surface onto EXISTING live model, not new document state. Default stays 50 (the
    // minimum of its range, i.e. straight/no-warp) — this page doesn't touch that default, it just gives it
    // somewhere to be seen/changed without leaving Euclideous (diagnosed 2026-10-17: swing warps every row,
    // including Euclideous's, via the row's own `S`/`a`, not this lane's own RHYTHM rate — see the status log).
    let swing: Int
    let onSetSwing: (Int) -> Void
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the per-lane
    // sourceMode entirely (the 2026-10-08 comment this replaces described per-lane I/O as the live model;
    // it no longer is). One page-level choice, same live-mirror/onSet convention as resetSpanBars/keyRoot
    // above.
    let noteSource: EuclideousLaneSource
    let onSetNoteSource: (EuclideousLaneSource) -> Void
    // HOLD/LATCH (Paul 2026-10-20): two mutually-exclusive header buttons beside the key pill, same live-
    // mirror/onSet convention as `noteSource` above. nil = off (plain live MIDI, today's behaviour). Only
    // meaningful against MIDI IN — the buttons themselves dim when `noteSource != .midi`.
    let holdLatchMode: EuclideousHoldLatchMode?
    let onSetHoldLatchMode: (EuclideousHoldLatchMode?) -> Void
    let mainOutMask: UInt8
    // LANE SOLO (2026-10-21): the latched solo mask (saved) and the held one (a finger down; UI only). `soloEffective` is what every dim and the engine use.
    let soloMask: UInt8
    let soloHeld: UInt8
    // CHORDS GRID ferry (Paul 2026-10-24): 4 independently-stored progressions ("tabs"), replacing the single
    // grid the CHORDS BUTTON ferry (2026-10-08) first added. `activeChordSet` is BOTH which tab plays AND
    // which tab this popup edits — Paul: "I only want the chords tab to be switched manually when a user
    // clicks it" (no queue-to-next-column-boundary). `onEditChordSet` mutates one set by index; `onSwitchChordSet`
    // changes which one is active, immediately.
    let chordSets: [MachineParams]
    let activeChordSet: Int
    let onEditChordSet: (Int, @escaping (inout MachineParams) -> Void) -> Void
    let onSwitchChordSet: (Int) -> Void
    let clock: EuclidLiveClock
    let onEdit: (@escaping (inout [EuclidLine]) -> Void) -> Void
    // RANDOM MODE ferry (§6): the live pending-roll array (AudioUnitViewController's own @State, never the
    // document) — read-only here; `onSetPendingRolls` queues a new one or clears a landed one. The commit
    // into `lines` itself happens on the VC's 4 Hz resync loop once a roll's landingBeat has passed.
    var pendingRolls = EuclideousPendingRollSlots()
    var onSetPendingRolls: (EuclideousPendingRollSlots) -> Void = { _ in }
    // §5.6: the hold's own higher-priority override, same shape, separate channel.
    var holdOverrides = EuclideousPendingRollSlots()
    var onSetHoldOverrides: (EuclideousPendingRollSlots) -> Void = { _ in }
    // §7.2: random mode finished — the ordered, already-filtered list of kept card-tabs to record as undo
    // steps (one each). Only AVC owns `euclideousUndo`/`euclideousSnapshot`, so it builds the actual
    // `EuclideousUndoSnapshot` sequence and pushes it.
    var onRandomFinish: ([EuclideousRandomUndoEntry]) -> Void = { _ in }
    // LANE LOCK ferry (2026-10-21): the four lanes' locks (the document's, mirrored by the VC), when each card last rang (a snap landed / a capture), which lanes a finger is on, and the two ways back to the VC —
    // a lock command (lock / capture / unlock / grid: document writes, no undo) and a finger down / up on a lock-field control (the HELD word the render thread reads). Defaults leave the page exactly as before.
    var locks: [EuclideousLaneLock] = Array(repeating: EuclideousLaneLock(), count: 4)
    var lockRingStart: [Date?] = [nil, nil, nil, nil]
    var lockHeld: [Bool] = [false, false, false, false]
    var onLockCommand: (Int, EuclideousLockCommand) -> Void = { _, _ in }
    var onLockHeld: (Int, Bool) -> Void = { _, _ in }
    // LANE LOCK §1.1: page-local, ephemeral — not in the document, not an undo step, not saved. Never on together with random mode.
    @State private var euclideousLockMode = false
    // MIX TAB (2026-10-18 §4.3): a lane edit that records ONE undo step per TOUCH. `onEdit`'s fixed coalesce key merges consecutive edits
    // across different touches into one step; a pad instead passes `newStep: true` on the first value-changing write of a touch (the VC
    // takes a `coalesceKey: nil` checkpoint) and `false` for the rest, so dragging is one step and two pads never flood the stack.
    let onEditStep: (Bool, @escaping (inout [EuclidLine]) -> Void) -> Void
    // FOUR RIFFS (2026-10-18 ferry) — `onEditRiffs` is the ONE write path for every grid edit (a tap,
    // each cell a drag-paint crosses) AND for the tab row's COPY/PASTE/CLEAR menu: a closure over the
    // whole `[EuclideousRiff]` array, one undo step per edit. `onSetActiveRiff` switches which of the
    // four is both edited and sounding (a discrete action, its own undo step — not routed through the
    // generic per-lane `onEdit` funnel, same reasoning as `onSetKeyRoot`).
    let onEditRiffs: (@escaping (inout [EuclideousRiff]) -> Void) -> Void
    let onSetActiveRiff: (Int) -> Void
    let onEditLanesSeq: (@escaping (inout EuclideousLanesSeq) -> Void) -> Void
    /// FX TAB: like `onEditStep` — `newStep: true` takes a `coalesceKey: nil` undo checkpoint (the first value-changing write of a tap / stroke / drag / toggle),
    /// `false` writes into the step already open (the rest of the stroke, a double-tap's second tap).
    let onEditFX: (Bool, @escaping (inout EuclideousFX) -> Void) -> Void
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
    /// LANE SOLO §3: a finger lands on lane i's SOLO button / lifts off it (`latchToggles` = it was a tap).
    let onSoloDown: (Int) -> Void
    let onSoloUp: (Int, Bool) -> Void
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
    let onSetPulseLevel: (Int) -> Void   // PULSE §7.1: the settings sheet's STRIKE PULSE row (a device preference — `pulseLevel` above)
    let onOpenPresets: () -> Void   // (Paul 2026-10-11: "add a preset button on the euclidius page" — presets
                                     // were only reachable by leaving this page; opens the SAME browser overlay
                                     // the main header already uses, which the VC renders as a sibling z-above
                                     // this one, so it's reachable without ever closing Euclideous.
    /// FOURFOLD REEL LINK (2026-10-23): the tape icon in UTILITIES. `reelRecording` = the 8×8 header's own rule (host playing and not replaying); the VC mounts the pass browser above this page.
    let reelRecording: Bool
    let onOpenReel: () -> Void
    // UNDO/REDO (usability ferry §7.1): disabled (40% opacity) when there's nothing to undo/redo — driven by
    // the VC's own EuclideousUndoSnapshot stack (AudioUnitViewController.swift), not persisted here.
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    /// The view's bottom safe-area inset (the home-indicator zone), read from the root `GeometryReader` in `DiagView` and passed in because the page is laid out on the
    /// view's FULL height (it ignores the bottom safe area, and a view whose frame sits inside the safe area reads its own inset as 0). The page's bottom margin is
    /// `max(16, inset)` (`EuclideousPageMetrics.bottomMargin`), so no box sits in that zone. 0 = nothing to avoid (the default).
    var pageBottomInset: CGFloat = 0
    /// false (the standalone Fourfold app): hides the settings sheet's "WHEN THE HOST STOPS" row — the app's own transport is the clock.
    var showsHostStopBehavior: Bool = true

    // FOUR RIFFS (2026-10-18 ferry): the grid shows `riffs[activeRiff]` directly — no looper, no
    // beat-dependent derivation. Every lane reads this SAME array via `activeRiff`, so editing the
    // grid here is editing exactly what's sounding ("ONE GLOBAL RIFF" ferry, 2026-10-12).
    var effectiveGridRanks: [Int] {
        riffs[max(0, min(3, activeRiff))].ranksResolved
    }

    // SEQUENCER PANEL (2026-10-14 ferry §1; MIX ferry 2026-10-18 §1.5): which tab is showing — MIX first and the DEFAULT, LANES second,
    // RIFFS hidden — purely ephemeral, never persisted (so a fresh page always opens on MIX).
    @State private var sequencerTab: EuclideousSeqTab = .default
    // LANES GRID (2026-10-18): the per-lane cache of the roll feed (recomputed only when its inputs or its
    // window change, never per frame). RESTART CHAINS ferry §8: the panel's own MUTE/RESTART sub-tab state
    // (`lanesSubTab`) is retired along with the RESTART view itself — the panel is mute-only now.
    @State private var lanesRollCache = EuclideousLanesRollCache()
    @State private var pulseSettleTick = 0   // PULSE §9.1: see `pulseLive`
    @State private var notesPickerOpen: Set<Int> = []   // NOTES tab ferry §4.5: the lanes whose PLAY AS picker is open — not saved, not an undo step
    @State private var riffReadoutCache = EuclideousRiffReadoutCache()   // the riff readout / never-play set, memoised per lane on its inputs (RIFF WALK §7.2)
    // FX TAB (2026-10-18 §12.1/§12.5/§12.9): exactly one row selected (RATCH first; switching tabs never changes it), each row's brush (its default when the page
    // opens, changed only by value drags), the NOTE cell touched last (the strip's preview), the double-tap memory, and whether this touch has opened its undo step.
    @State private var fxSelectedRow = 0
    @State private var fxBrushes: [Int] = EuclideousFXRow.allCases.map { $0.defaultValue }
    @State private var fxNotePreviewCol: Int? = nil
    @State private var fxLastTap: (row: Int, col: Int, time: Double)? = nil
    @State private var fxStepOpen = false
    @State private var fxTouchDownTime = 0.0   // when the touch in flight began — a double-tap's second tap is measured from the first tap's LIFT to this touch-DOWN (§12.3)
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
    // RANDOM MODE ferry (§1.1): page-local, ephemeral — not in the document, not an undo step, not saved.
    @State private var euclideousRandomMode = false
    // The card's own tab while in random mode (RHYTHM/RIFF/NOTES only — LISTEN maps to RHYTHM, §3.3).
    @State private var euclideousRandomTab: [EuclideousRandomTab] = [.rhythm, .rhythm, .rhythm, .rhythm]
    // Per (lane, tab) bookkeeping — indexed [lane][tab.rawValue]. `original` non-nil ⇒ an undecided roll.
    @State private var euclideousRandomRolls: [[EuclideousRandomRollState]] = Array(repeating: Array(repeating: EuclideousRandomRollState(), count: 3), count: 4)
    // The RNG seed for the NEXT throw/tweak — reseeded (not reused) after every press so repeats differ.
    @State private var euclideousRandomSeed: UInt64 = UInt64(Date().timeIntervalSinceReferenceDate * 1000)
    // §5.6: the lane currently held (showing its original), nil when nothing is held.
    @State private var euclideousRandomHeldLane: Int? = nil
    // The deployment target (iOS 16) has no two-parameter `.onChange`, so the handler below diffs against
    // this itself to detect a slot's non-nil → nil landing transition.
    @State private var euclideousRandomPrevPendingRolls = EuclideousPendingRollSlots()
    // §5.6: the beat each in-flight hold's own override is scheduled to START at, keyed by pending-slot —
    // read back on release to decide "did the hold even start yet" (if not, cancel outright, nothing switches).
    @State private var euclideousRandomHoldStartBeat: [Int: Double] = [:]
    // §7.2: the order KEEP was pressed this session, (lane, tab) pairs — reset when a fresh session starts.
    @State private var euclideousRandomKeepOrder: [(lane: Int, tab: EuclideousRandomTab)] = []
    // §7.2: non-nil while finish() is waiting on one or more still-queued BACKs to land before the undo
    // recording (and the bookkeeping reset) can happen — the slots still outstanding.
    @State private var euclideousRandomAwaitingFinishSlots: Set<Int>? = nil
    // §7.3: when each lane's return highlight started (visual only — no state, no undo).
    @State private var euclideousRandomReturnHighlightStart: [Int: Date] = [:]
    // §6.8: the previous render's `lines`, to tell "our own landing wrote this field" apart from "something
    // else did" — same two-parameter-`.onChange`-workaround idiom as `euclideousRandomPrevPendingRolls` above.
    @State private var euclideousRandomPrevLines: [EuclidLine] = []

    // MARK: RANDOM MODE — actions (§5-§7). §7's full finishing/undo/return sequence is a later ferry step
    // (the status log/pending-tasks note which); `euclideousRandomFinish` here is §7.1's own drop/keep rule
    // only — no undo recording, no return highlights yet.

    private func euclideousRandomOtherLanes(except lane: Int) -> [EuclideousRandomOtherLane] {
        (0..<4).filter { $0 != lane }.map { i in
            let l = lines[i]
            let stepBeats = l.rate?.beats ?? 0.5
            return EuclideousRandomOtherLane(steps: l.steps, hits: l.pulses,
                                              offset: euclideousRandomDisplayedOffset(rotate: l.rotate, steps: l.steps),
                                              stepBeats: stepBeats, participates: l.riffOnResolved || euclideousNotesLayerIsOn(l),
                                              riffOn: l.riffOnResolved, riffDir: l.riffDirResolved,
                                              riffAdvanceStep: l.riffAdvanceStepResolved, riffAdvanceEvery: l.riffAdvanceEveryResolved,
                                              riffStride: l.riffStrideResolved, riffShift: l.riffShiftRequestedResolved)
        }
    }

    private func euclideousRandomNextSeed() -> UInt64 {
        var rng = EuclideousRandomRNG(seed: euclideousRandomSeed)
        euclideousRandomSeed = rng.next()
        return euclideousRandomSeed
    }

    /// §9.1: TWEAK (and a repeated press of either button) starts from what's PLAYING — this tab's own
    /// still-queued-or-landed roll if one exists, not necessarily the live document (which still shows the
    /// pre-roll state until a queued roll actually lands). Reuses the commit-write's own field overlay
    /// (Phase 3) as a non-destructive preview merge on a throwaway copy — never writes `lines`.
    private func euclideousRandomEffectiveLine(lane: Int) -> EuclidLine {
        var l = lines[lane]
        let tab = euclideousRandomTab[lane]
        let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
        if slot < pendingRolls.count, let roll = pendingRolls[slot] {
            euclideousRandomCommitPendingRoll(roll, into: &l)
        }
        return l
    }

    /// §6.1/§6.3: queues a roll for `lane`/`tab`, landing at the next bar/beat. Captures this tab's
    /// "original" on its first roll this session (§6.6) and bumps GOES (not for BACK, which doesn't start a
    /// new roll — it resolves the existing one).
    private func euclideousRandomQueue(lane: Int, tab: EuclideousRandomTab, waiting: EuclideousRandomRollState.Waiting, tag: String,
                                        fill: (inout EuclideousPendingRoll) -> Void) {
        let nowBeat = clock.playing ? clock.anchor + Date().timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
        let margin = euclideousRandomLandingMarginBeats(tempo: clock.tempo)
        let landingBeat = euclideousRandomQueuedLandingBeat(running: clock.playing, currentBeat: nowBeat, barBeats: clock.beatsPerBar, marginBeats: margin)
        var roll = EuclideousPendingRoll(tab: tab, landingBeat: landingBeat)
        fill(&roll)
        var rolls = pendingRolls
        rolls[euclideousRandomPendingSlot(lane: lane, tab: tab)] = roll
        onSetPendingRolls(rolls)
        var state = euclideousRandomRolls[lane][tab.rawValue]
        if state.decided { state.original = lines[lane]; state.decided = false }   // §6.6: a fresh roll's original is whatever was last decided (KEEP's own state, or the pre-session baseline)
        if state.sessionBaseline == nil { state.sessionBaseline = lines[lane] }     // §7.2: the ONE pre-session baseline, captured once, held for the whole session
        // GOES increments on LANDING (`euclideousRandomHandlePendingRollsChange`), not here — §6.6: "each
        // landing increments its GOES count." A second throw queued before the first lands only ever
        // contributes one landing, so it must only ever contribute one GOES.
        state.tag = tag
        state.waiting = waiting
        euclideousRandomRolls[lane][tab.rawValue] = state
    }

    /// §5.4: a throw/tweak that found nothing legal to change — stamps `decidedAt` too (even when the tab
    /// was already decided, the common case) so the caption's short display window picks it up either way.
    private func euclideousRandomMarkNothingToChange(lane: Int, tab: EuclideousRandomTab) {
        euclideousRandomRolls[lane][tab.rawValue].tag = "NOTHING TO CHANGE"
        euclideousRandomRolls[lane][tab.rawValue].decidedAt = Date()
    }

    private func euclideousRandomThrow(lane: Int) {
        let tab = euclideousRandomTab[lane]
        let l = lines[lane]
        // LISTEN REBUILT §7.3: "nothing writes the lane's own rhythm or riff settings while borrowed: not
        // the tab, not random mode, not MIDI or automation." THROW on a borrowed RHYTHM/RIFF/NOTES tab
        // no-ops (§0's own research found no such guard existed under the old model — this is new).
        let borrowed = euclideousListenBorrowedTabs(rhythm: l.listenRhythmResolved, pitch: l.listenPitchResolved, notesReadsRiff: true)
        if (tab == .rhythm && borrowed.rhythm) || (tab == .riff && borrowed.riff) || (tab == .notes && borrowed.notes) {
            euclideousRandomMarkNothingToChange(lane: lane, tab: tab)
            return
        }
        switch tab {
        case .rhythm:
            let stepBeats = l.rate?.beats ?? 0.5
            let current = (steps: l.steps, hits: l.pulses, offset: euclideousRandomDisplayedOffset(rotate: l.rotate, steps: l.steps), stepBeats: stepBeats)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            let r = euclideousRandomThrowRhythm(current: current, others: euclideousRandomOtherLanes(except: lane), rng: &rng)
            euclideousRandomQueue(lane: lane, tab: .rhythm, waiting: .throwing, tag: r.tag) { roll in
                roll.steps = r.steps; roll.pulses = r.hits
                roll.rotate = euclideousRandomRotateFromDisplayed(offset: r.offset, steps: r.steps)
            }
        case .riff:
            let writtenRanks = effectiveGridRanks
            let role = euclideousRandomRole(hits: l.pulses, steps: l.steps, stepBeats: l.rate?.beats ?? 0.5)
            let current = (dir: l.euclideousRiffDirResolved, advanceStep: l.riffAdvanceStepResolved, advanceEvery: l.riffAdvanceEveryResolved,
                           invert: l.riffInvertResolved, onRest: l.riffOnRestResolved, stride: l.riffStrideResolved,
                           shift: l.riffShiftRequestedResolved, length: l.riffLengthResolved, hits: l.pulses, role: role)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            guard let r = euclideousRandomThrowRiff(current: current, writtenRanks: writtenRanks, others: euclideousRandomOtherLanes(except: lane), rng: &rng) else {
                euclideousRandomMarkNothingToChange(lane: lane, tab: tab)
                return
            }
            euclideousRandomQueue(lane: lane, tab: .riff, waiting: .throwing, tag: r.tag) { roll in
                roll.riffDir = r.dir; roll.riffInvert = r.invert; roll.riffAdvanceEvery = r.advanceEvery
                roll.riffAdvanceStep = r.advanceStep; roll.riffOnRest = r.onRest; roll.riffRotate = r.shift; roll.riffStride = r.stride
            }
        case .notes:
            let writtenRanks = effectiveGridRanks
            let role = euclideousRandomRole(hits: l.pulses, steps: l.steps, stepBeats: l.rate?.beats ?? 0.5)
            let current = (litOrder: l.litOrderResolved, when: l.notesWhenResolved, chance: l.notesChanceResolved, playAs: l.notesPlayAsResolved)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            guard let r = euclideousRandomThrowNotes(role: role, current: current, riffOn: l.riffOnResolved, writtenRanks: writtenRanks,
                                                      length: l.riffLengthResolved, receivedOnly: l.notesReceivedOnlyResolved,
                                                      receivedCount: 0, rng: &rng) else {
                euclideousRandomMarkNothingToChange(lane: lane, tab: tab)
                return
            }
            euclideousRandomQueue(lane: lane, tab: .notes, waiting: .throwing, tag: r.tag) { roll in
                roll.notesLitOrder = r.litOrder; roll.notesWhen = r.when; roll.notesChance = r.chance; roll.notesPlayAs = r.playAs
            }
        }
    }

    private func euclideousRandomTweak(lane: Int) {
        let tab = euclideousRandomTab[lane]
        let l = euclideousRandomEffectiveLine(lane: lane)
        // LISTEN REBUILT §7.3: same borrowed-tab guard as THROW above.
        let borrowed = euclideousListenBorrowedTabs(rhythm: l.listenRhythmResolved, pitch: l.listenPitchResolved, notesReadsRiff: true)
        if (tab == .rhythm && borrowed.rhythm) || (tab == .riff && borrowed.riff) || (tab == .notes && borrowed.notes) {
            euclideousRandomMarkNothingToChange(lane: lane, tab: tab)
            return
        }
        switch tab {
        case .rhythm:
            let stepBeats = l.rate?.beats ?? 0.5
            let current = (steps: l.steps, hits: l.pulses, offset: euclideousRandomDisplayedOffset(rotate: l.rotate, steps: l.steps), stepBeats: stepBeats, tilt: l.tiltResolved)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            let r = euclideousRandomTweakRhythm(current: current, others: euclideousRandomOtherLanes(except: lane), rng: &rng)
            guard !r.tag.isEmpty else { euclideousRandomMarkNothingToChange(lane: lane, tab: tab); return }
            euclideousRandomQueue(lane: lane, tab: .rhythm, waiting: .tweaking, tag: r.tag) { roll in
                roll.steps = r.steps; roll.pulses = r.hits
                roll.rotate = euclideousRandomRotateFromDisplayed(offset: r.offset, steps: r.steps)
            }
        case .riff:
            let writtenRanks = effectiveGridRanks
            let current = (dir: l.euclideousRiffDirResolved, advanceStep: l.riffAdvanceStepResolved, advanceEvery: l.riffAdvanceEveryResolved,
                           invert: l.riffInvertResolved, onRest: l.riffOnRestResolved, stride: l.riffStrideResolved,
                           shift: l.riffShiftRequestedResolved, length: l.riffLengthResolved, hits: l.pulses)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            guard let r = euclideousRandomTweakRiff(current: current, writtenRanks: writtenRanks, rng: &rng) else {
                euclideousRandomMarkNothingToChange(lane: lane, tab: tab); return
            }
            euclideousRandomQueue(lane: lane, tab: .riff, waiting: .tweaking, tag: r.tag) { roll in
                roll.riffDir = r.dir; roll.riffInvert = r.invert; roll.riffAdvanceEvery = r.advanceEvery
                roll.riffAdvanceStep = r.advanceStep; roll.riffOnRest = r.onRest; roll.riffRotate = r.shift; roll.riffStride = r.stride
            }
        case .notes:
            let writtenRanks = effectiveGridRanks
            let role = euclideousRandomRole(hits: l.pulses, steps: l.steps, stepBeats: l.rate?.beats ?? 0.5)
            let allowed = euclideousRandomAllowedNotesPositions(role: role, riffOn: l.riffOnResolved, writtenRanks: writtenRanks,
                                                                 length: l.riffLengthResolved, receivedOnly: l.notesReceivedOnlyResolved, receivedCount: 0)
            let current = (litOrder: l.litOrderResolved, when: l.notesWhenResolved, chance: l.notesChanceResolved, playAs: l.notesPlayAsResolved)
            var rng = EuclideousRandomRNG(seed: euclideousRandomNextSeed())
            guard let r = euclideousRandomTweakNotes(role: role, current: current, allowed: allowed, riffOn: l.riffOnResolved,
                                                      writtenRanks: writtenRanks, length: l.riffLengthResolved, rng: &rng) else {
                euclideousRandomMarkNothingToChange(lane: lane, tab: tab); return
            }
            euclideousRandomQueue(lane: lane, tab: .notes, waiting: .tweaking, tag: r.tag) { roll in
                roll.notesLitOrder = r.litOrder; roll.notesWhen = r.when; roll.notesChance = r.chance; roll.notesPlayAs = r.playAs
            }
        }
    }

    /// §5.2: BACK — asks for the tab's original, landing like any other roll, replacing anything waiting.
    private func euclideousRandomBack(lane: Int) {
        let tab = euclideousRandomTab[lane]
        let state = euclideousRandomRolls[lane][tab.rawValue]
        guard state.isUndecided, let original = state.original else { return }
        let nowBeat = clock.playing ? clock.anchor + Date().timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
        let margin = euclideousRandomLandingMarginBeats(tempo: clock.tempo)
        let landingBeat = euclideousRandomQueuedLandingBeat(running: clock.playing, currentBeat: nowBeat, barBeats: clock.beatsPerBar, marginBeats: margin)
        var roll = EuclideousPendingRoll(tab: tab, landingBeat: landingBeat)
        switch tab {
        case .rhythm:
            roll.steps = original.steps; roll.pulses = original.pulses; roll.rotate = original.rotate
        case .riff:
            roll.riffDir = original.euclideousRiffDirResolved; roll.riffInvert = original.riffInvertResolved
            roll.riffAdvanceEvery = original.riffAdvanceEveryResolved; roll.riffAdvanceStep = original.riffAdvanceStepResolved
            roll.riffOnRest = original.riffOnRestResolved; roll.riffRotate = original.riffRotateResolved; roll.riffStride = original.riffStrideResolved
        case .notes:
            roll.notesLitOrder = original.litOrderResolved; roll.notesWhen = original.notesWhenResolved
            roll.notesChance = original.notesChanceResolved; roll.notesPlayAs = original.notesPlayAsResolved
        }
        var rolls = pendingRolls
        rolls[euclideousRandomPendingSlot(lane: lane, tab: tab)] = roll
        onSetPendingRolls(rolls)
        var newState = state
        newState.waiting = .back
        newState.tag = ""
        euclideousRandomRolls[lane][tab.rawValue] = newState
    }

    /// §5.3: KEEP — decided at once; the sound doesn't change, anything waiting on this tab is dropped.
    private func euclideousRandomKeep(lane: Int) {
        let tab = euclideousRandomTab[lane]
        var rolls = pendingRolls
        rolls[euclideousRandomPendingSlot(lane: lane, tab: tab)] = nil
        onSetPendingRolls(rolls)
        var state = euclideousRandomRolls[lane][tab.rawValue]
        state.decided = true   // `original`/`sessionBaseline` stay — §6.6 needs the former for a later roll, §7.2 needs the latter at finish
        state.waiting = nil
        state.decidedAt = Date()
        euclideousRandomRolls[lane][tab.rawValue] = state
        euclideousRandomKeepOrder.append((lane, tab))   // §7.2: "tabs kept with KEEP, in the order KEEP was pressed"
    }

    /// §5.6: touch-down on the picture — asks for the original, from the next beat. Only while the selected
    /// tab has an undecided roll; a decided tab offers no hold (the picture view gates the gesture on this
    /// via `state.isUndecided`, but this guards too in case a stray event slips through).
    private func euclideousRandomHoldBegan(lane: Int) {
        let tab = euclideousRandomTab[lane]
        let state = euclideousRandomRolls[lane][tab.rawValue]
        guard state.isUndecided, let original = state.original else { return }
        let nowBeat = clock.playing ? clock.anchor + Date().timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
        let margin = euclideousRandomLandingMarginBeats(tempo: clock.tempo)
        let startBeat = euclideousRandomQueuedHoldBeat(running: clock.playing, currentBeat: nowBeat, marginBeats: margin)
        var roll = EuclideousPendingRoll(tab: tab, landingBeat: startBeat)
        switch tab {
        case .rhythm:
            roll.steps = original.steps; roll.pulses = original.pulses; roll.rotate = original.rotate
        case .riff:
            roll.riffDir = original.euclideousRiffDirResolved; roll.riffInvert = original.riffInvertResolved
            roll.riffAdvanceEvery = original.riffAdvanceEveryResolved; roll.riffAdvanceStep = original.riffAdvanceStepResolved
            roll.riffOnRest = original.riffOnRestResolved; roll.riffRotate = original.riffRotateResolved; roll.riffStride = original.riffStrideResolved
        case .notes:
            roll.notesLitOrder = original.litOrderResolved; roll.notesWhen = original.notesWhenResolved
            roll.notesChance = original.notesChanceResolved; roll.notesPlayAs = original.notesPlayAsResolved
        }
        let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
        euclideousRandomHoldStartBeat[slot] = startBeat
        var overrides = holdOverrides
        overrides[slot] = roll
        onSetHoldOverrides(overrides)
        euclideousRandomHeldLane = lane
    }

    /// §5.6: release — asks for the current state again, from the next beat; if the hold's OWN start beat
    /// hadn't passed yet, cancels outright ("if the touch lifts before the beat, nothing switches").
    private func euclideousRandomHoldEnded(lane: Int) {
        guard euclideousRandomHeldLane == lane else { return }
        euclideousRandomHeldLane = nil
        let tab = euclideousRandomTab[lane]
        let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
        let startBeat = euclideousRandomHoldStartBeat.removeValue(forKey: slot)
        let nowBeat = clock.playing ? clock.anchor + Date().timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
        if let startBeat, nowBeat < startBeat {
            var overrides = holdOverrides
            overrides[slot] = nil
            onSetHoldOverrides(overrides)
            return
        }
        guard clock.playing, clock.tempo > 0 else {
            var overrides = holdOverrides
            overrides[slot] = nil
            onSetHoldOverrides(overrides)
            return
        }
        let margin = euclideousRandomLandingMarginBeats(tempo: clock.tempo)
        let endBeat = euclideousRandomQueuedHoldBeat(running: true, currentBeat: nowBeat, marginBeats: margin)
        let delaySeconds = max(0, (endBeat - nowBeat) * 60.0 / clock.tempo)
        // ONE-SHOT, main-thread-only (the same idiom this file's own PULSE settle-tick already uses) — not a
        // render-thread mechanism; the render thread has nothing to clear, it just stops being handed an
        // override at the beat the UI itself determined.
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [self] in
            var overrides = holdOverrides
            overrides[slot] = nil
            onSetHoldOverrides(overrides)
        }
    }

    /// ONE reconciliation step, called from BOTH `.onChange(of: pendingRolls)` and `.onChange(of: lines)` —
    /// deliberately idempotent and order-independent (two separate onChange closures on different tracked
    /// values have no documented relative firing order within the same SwiftUI update, so this must give
    /// the same result no matter which one calls it, or calls it twice): it reads only the CURRENT prop
    /// values (always fresh for this render, regardless of which onChange triggered it) against the single
    /// pair of snapshots it alone owns and advances at the end, so a redundant second call in the same
    /// render is a safe no-op (old == new on both by then).
    ///
    /// Two jobs: (1) a roll landing — its slot transitioning non-nil → nil in `pendingRolls`, which AVC's
    /// resync loop does once it commits — clears `waiting`, bumps GOES (§6.6: on the landing, not the
    /// press), and decides a landed BACK; (2) §6.8 — if a tab's own fields changed in `lines` WITHOUT that
    /// landing mechanism (no slot was in flight for it before or after), something else wrote them (host
    /// automation, MIDI learn, …) — that tab becomes decided at once, dropping anything waiting on it.
    private func euclideousRandomReconcile() {
        let oldPending = euclideousRandomPrevPendingRolls
        let newPending = pendingRolls
        let oldLines = euclideousRandomPrevLines
        let newLines = lines

        var anyLanded = false
        var landedSlots: Set<Int> = []
        for lane in 0..<4 {
            for tab in EuclideousRandomTab.allCases {
                let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
                guard slot < oldPending.count, slot < newPending.count, oldPending[slot] != nil, newPending[slot] == nil else { continue }
                landedSlots.insert(slot)
                var state = euclideousRandomRolls[lane][tab.rawValue]
                switch state.waiting {
                case .back: state.decided = true; state.decidedAt = Date()
                case .throwing, .tweaking: state.goes += 1   // §6.6: GOES counts the landing, not the press
                case nil: break
                }
                state.waiting = nil
                euclideousRandomRolls[lane][tab.rawValue] = state
                anyLanded = true
            }
        }

        if oldLines.count == 4, newLines.count == 4 {
            for lane in 0..<4 where oldLines[lane] != newLines[lane] {
                for tab in EuclideousRandomTab.allCases {
                    let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
                    guard !landedSlots.contains(slot) else { continue }   // that field change IS the landing just processed above
                    var state = euclideousRandomRolls[lane][tab.rawValue]
                    guard state.isUndecided else { continue }
                    guard slot >= newPending.count || newPending[slot] == nil else { continue }   // something's queued for it right now — let it land normally
                    guard !euclideousRandomTabFieldsEqual(oldLines[lane], newLines[lane], tab: tab) else { continue }   // only THIS tab's own fields matter
                    if euclideousRandomHeldLane == lane { euclideousRandomHoldEnded(lane: lane) }
                    state.decided = true
                    state.decidedAt = Date()
                    state.waiting = nil
                    euclideousRandomRolls[lane][tab.rawValue] = state
                }
            }
        }

        euclideousRandomPrevPendingRolls = newPending
        euclideousRandomPrevLines = newLines
        // §7.2: a finish deferred on one or more waiting BACKs completes once they've all landed.
        if anyLanded, euclideousRandomAwaitingFinishSlots != nil { euclideousRandomCheckAwaitingFinish() }
    }

    /// §7.2's own ordered kept-tab list — KEEP's press order, then every other touched tab (lane, then
    /// RHYTHM/RIFF/NOTES), each kept only if its final state still differs from the session baseline (a
    /// landed BACK records nothing). Reads live state, so it's safe to call either at finish time (for
    /// tabs with nothing still waiting) or later, once a deferred BACK has landed.
    private func euclideousRandomBuildFinishEntries() -> [EuclideousRandomUndoEntry] {
        var order = euclideousRandomKeepOrder
        for lane in 0..<4 {
            for tab in EuclideousRandomTab.allCases where euclideousRandomRolls[lane][tab.rawValue].sessionBaseline != nil {
                if !order.contains(where: { $0.lane == lane && $0.tab == tab }) { order.append((lane, tab)) }
            }
        }
        return order.compactMap { (lane, tab) -> EuclideousRandomUndoEntry? in
            guard let baseline = euclideousRandomRolls[lane][tab.rawValue].sessionBaseline else { return nil }
            guard !euclideousRandomTabFieldsEqual(baseline, lines[lane], tab: tab) else { return nil }   // a landed BACK: no net change
            return EuclideousRandomUndoEntry(lane: lane, tab: tab, original: baseline)
        }
    }

    /// §7.3: visual only — no state, no undo. One Date per changed lane; the card reads it to show the
    /// ring pulse + "KEPT · UNDO TO GO BACK" tag for two bars (4 s if not running), then it's inert.
    private func euclideousRandomMarkReturnHighlights(_ entries: [EuclideousRandomUndoEntry]) {
        let now = Date()
        for lane in Set(entries.map { $0.lane }) { euclideousRandomReturnHighlightStart[lane] = now }
    }

    private func euclideousRandomCheckAwaitingFinish() {
        guard let awaiting = euclideousRandomAwaitingFinishSlots else { return }
        let stillWaiting = awaiting.filter { pendingRolls[$0] != nil }
        guard stillWaiting.isEmpty else { euclideousRandomAwaitingFinishSlots = stillWaiting; return }
        euclideousRandomAwaitingFinishSlots = nil
        let entries = euclideousRandomBuildFinishEntries()
        euclideousRandomMarkReturnHighlights(entries)
        onRandomFinish(entries)
        euclideousRandomRolls = Array(repeating: Array(repeating: EuclideousRandomRollState(), count: 3), count: 4)
        euclideousRandomKeepOrder = []
    }

    /// §7.1: drop every still-waiting THROW/TWEAK; keep every waiting BACK (it lands on its own bar); end
    /// any hold. §7.2's undo recording hands off to AVC (only it owns `euclideousUndo`/`euclideousSnapshot`)
    /// — immediately if nothing's still waiting on a BACK, else deferred until every one has landed.
    private func euclideousRandomFinish() {
        if let held = euclideousRandomHeldLane { euclideousRandomHoldEnded(lane: held) }
        var rolls = pendingRolls
        var awaitingSlots: Set<Int> = []
        for lane in 0..<4 {
            for tab in EuclideousRandomTab.allCases {
                let slot = euclideousRandomPendingSlot(lane: lane, tab: tab)
                guard slot < rolls.count else { continue }
                if euclideousRandomRolls[lane][tab.rawValue].waiting == .back { awaitingSlots.insert(slot) } else { rolls[slot] = nil }
            }
        }
        onSetPendingRolls(rolls)
        euclideousRandomMode = false

        if awaitingSlots.isEmpty {
            let entries = euclideousRandomBuildFinishEntries()
            euclideousRandomMarkReturnHighlights(entries)
            onRandomFinish(entries)
            euclideousRandomRolls = Array(repeating: Array(repeating: EuclideousRandomRollState(), count: 3), count: 4)
            euclideousRandomKeepOrder = []
        } else {
            // Deferred: keep the bookkeeping alive (sessionBaseline etc.) until every waiting BACK lands.
            euclideousRandomAwaitingFinishSlots = awaitingSlots
        }
    }
    // headerResetChip/resetSpanPopupOpen/resetSpanPopupCard RETIRED (2026-10-14 sequencer-panel ferry §3:
    // "RESET becomes per-lane... replacing the old machine-wide header RESET control") — the struct's own
    // `resetSpanBars`/`onSetResetSpanBars` properties stay in place, unreachable from any new UI, matching
    // how `euclideousReceiver` was handled when ITS control was dropped (decode-safety + the real migration
    // SOURCE `EuclidLine.resetStepsResolved` reads, per Models.swift's own doc comment there).
    @State private var resetPopupLane: Int? = nil
    @State private var resetChipFrames: [Int: CGRect] = [:]
    // FOUR RIFFS (restored 2026-10-18): a long press on a riff tab opens COPY/PASTE/CLEAR for that tab;
    // `riffClipboard` is the one-slot clipboard it shares across all four tabs.
    @State private var riffTabMenuLane: Int? = nil
    @State private var riffClipboard: EuclideousRiff? = nil
    // FOURFOLD SETTINGS (2026-10-15 ferry): `settingsTab` is explicitly NOT saved ("the sheet reopens on the
    // tab it was left on, in memory, MIDI IN the first time," §2.6) — plain ephemeral @State, same convention
    // as `laneTab` above.
    @State private var settingsOpen = false
    @State private var settingsTab = 0
    // SWING (2026-10-17): the global, scene-wide SWING control (AUParameter 1 — shared with the rest of the
    // 8×8 grid, not Euclideous-specific data) gets its own anchored popover off a third UTILITIES icon, the
    // same "one overlay at a time" family as `settingsOpen`/`keyPopupOpen`/`chordsPopupOpen` below.
    @State private var swingPopupOpen = false
    // RESTART CHAINS (ferry 2026-10-19 §1.6): "Which is open is UI state: not saved, not undoable" — exactly
    // one of the STEPS picker (§3) and the restart editor (§6.2) open at a time, per lane; opening either
    // closes the other on that SAME lane (both close on a tab switch too, handled where `laneTab` is set).
    @State private var stepsPickerLane: Int? = nil
    @State private var restartEditorLane: Int? = nil
    // FOUR RIFFS — the tab row's own long-press COPY/PASTE/CLEAR menu (2026-10-14 ferry §7). No precedent
    // for a long-press CONTEXT MENU anywhere in this codebase (grepped first) — built as a 5th instance of
    // the scrim+centred-card family this page already uses 4 times (RESET/MASK MODE/CHORDS/KEY), not an
    // anchored popover like the per-lane RESET above, matching the plan's own "small 3-row scrim+card
    // popup" reading, not the anchored one.
    @State private var keyPopupOpen = false
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry): the KEY tab's own captured
    // on-screen frame (via EuclideousRiffTabFramePreferenceKey above), letting the picker open as a
    // popover anchored near the tab instead of centre-screen — nil until the tab has rendered at least
    // once, in which case the popup falls back to centre (handled at the render site).
    @State private var riffKeyTabFrame: CGRect? = nil
    @State private var chordsPopupOpen = false
    // CHORDS GRID ferry (2026-10-24) §4.6: the riff tabs' own long-press COPY/PASTE/CLEAR pattern, mirrored
    // for the 4 chord-set tabs (`riffTabMenuLane`/`riffClipboard` are the riff tabs' own separate state).
    @State private var chordsTabMenuIndex: Int? = nil
    @State private var chordsClipboard: MachineParams? = nil
    // Holding a finger on a grid cell shows that column's pool instead of the playing one (§7.3).
    @State private var chordsHeldColumn: Int? = nil
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
    // LISTEN REBUILT (2026-10-23): `listenPartnerPopup` deleted — no popup in the new design.
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


    /// Edits ONE line by index — the shared mutation path every per-lane control below goes through.
    private func edit(_ idx: Int, _ mutate: @escaping (inout EuclidLine) -> Void) {
        onEdit { lines in guard idx >= 0, idx < lines.count else { return }; mutate(&lines[idx]) }
    }
    /// `edit`, but with the MIX pad's explicit per-touch undo checkpoint (`newStep`).
    private func editStep(_ idx: Int, _ newStep: Bool, _ mutate: @escaping (inout EuclidLine) -> Void) {
        onEditStep(newStep) { lines in guard idx >= 0, idx < lines.count else { return }; mutate(&lines[idx]) }
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
            // cached/fixed assumption. Landscape = strictly wider than tall (`euclideousPageLayout` owns the chooser).
            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.055, blue: 0.07).ignoresSafeArea()
                    // PULSE §9.1: when the page stops playing, bump a tick once the 1.5 s settle window is over so the strike views re-evaluate and pause (they idle from then on)
                    .onChange(of: clock.playing) { playing in
                        if !playing { DispatchQueue.main.asyncAfter(deadline: .now() + euclideousPulseMaxAge + 0.1) { pulseSettleTick &+= 1 } }
                    }
                    // RANDOM MODE ferry: detect a roll's landing (its slot going non-nil → nil) to clear
                    // `waiting` and, for a landed BACK, decide the tab (§6.6/§5.2); and §6.8, an external
                    // write deciding an undecided tab. Both triggers share ONE idempotent reconciliation
                    // function — see its own doc comment for why.
                    .onChange(of: pendingRolls) { _ in euclideousRandomReconcile() }
                    .onChange(of: lines) { _ in euclideousRandomReconcile() }
                    // §1.4: the view closing (or the host tearing it down) ends random mode as if finished,
                    // keeping whatever's currently playing — the same path the dice-off tap uses.
                    .onDisappear { if euclideousRandomMode { euclideousRandomFinish() } }
                pageBody(geo.size)
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
                // LISTEN REBUILT (2026-10-23): the old partner pop-up is gone — §2.1's FOLLOW row picks the
                // one shared source inline (chips), no anchored popup needed.
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
                // FOUR RIFFS (restored 2026-10-18): long-press a riff tab opens COPY/PASTE/CLEAR, same
                // dimming scrim+centred-card shape as the old riff-tab menu it's restoring.
                if let lane = riffTabMenuLane {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { riffTabMenuLane = nil }
                        .zIndex(3)
                    riffTabMenuCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // CHORDS GRID ferry §4.6: the chord-set tabs' own long-press menu, same shape as the riff tabs'.
                if let idx = chordsTabMenuIndex {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { chordsTabMenuIndex = nil }
                        .zIndex(3)
                    chordsTabMenuCard(idx).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
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
                // inside this page). `headerH`/`containerW` recomputed via the SAME `pageGeometry` call the
                // two layout functions already use (one formula, not a parallel derivation).
                // SWING POPOVER (2026-10-17): anchored under the metronome icon — the UTILITIES group's
                // second (index 1 of 4) touch target. No frame-preference tracker needed (unlike the KEY
                // pill, which can land in several places): UTILITIES' own x and the icons' shared `target`
                // width are already the ONE formula every other header view draws from.
                if swingPopupOpen {
                    Color.clear.contentShape(Rectangle()).onTapGesture { swingPopupOpen = false }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(3)
                    let hdr = pageGeometry(geo.size).hdr
                    let target = hdr.compact ? HM.compactTarget : HM.target
                    let anchorX = sp16 + hdr.utilities.x + target
                    let anchorY = HM.topMargin + hdr.height
                    swingPopupCard
                        .offset(x: min(max(anchorX, sp8), max(sp8, geo.size.width - 200 - sp8)), y: anchorY + sp4)
                        .zIndex(4)
                }
                if settingsOpen {
                    let pg = pageGeometry(geo.size)
                    let containerW = pg.containerW, hdr = pg.hdr
                    EuclideousSettingsSheet(
                        tab: $settingsTab, containerW: containerW, containerH: geo.size.height,
                        headerBottomY: HM.topMargin + hdr.height,
                        onCloseSheet: { settingsOpen = false },
                        midiInMask: midiInChannelMask, onSetMidiInMask: onSetMidiInChannelMask,
                        ignoreAllNotesOff: ignoreAllNotesOff, onSetIgnoreAllNotesOff: onSetIgnoreAllNotesOff,
                        laneMasks: euclideousLaneMasks(lines), mainOutMask: mainOutMask, soloSilenced: (0..<4).map { soloSilenced($0) }, busChannels: busChannels,
                        outputNames: outputNames, allOutputName: allOutputName, onSetBusChannel: onSetBusChannel,
                        onAllNotesOff: onAllNotesOff,
                        hostStopBehavior: hostStopBehavior, onSetHostStopBehavior: onSetHostStopBehavior, showsHostStopBehavior: showsHostStopBehavior,
                        pulseLevel: pulseLevel, onSetPulseLevel: onSetPulseLevel
                    )
                    .padding(.horizontal, sp16)
                    .zIndex(5)
                }
            }
            .coordinateSpace(name: "euclideousXY")
            #if DEBUG
            .onAppear {
                let pg = euclideousPageLayout(size: geo.size, bottomInset: pageBottomInset)
                print("EUCLIDEOUS page size \(geo.size) bottomInset \(pageBottomInset) geo.safeAreaInsets \(geo.safeAreaInsets) → box \(pg.box) floors \(pg.floors)")
            }
            .onChange(of: geo.size) { sz in
                let pg = euclideousPageLayout(size: sz, bottomInset: pageBottomInset)
                print("EUCLIDEOUS page size \(sz) bottomInset \(pageBottomInset) geo.safeAreaInsets \(geo.safeAreaInsets) → box \(pg.box) floors \(pg.floors)")
            }
            #endif
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

    // (The riff panel's height pair now lives in Derivations.swift — `euclideousRiffPanelHeight` / `euclideousRiffRowH`, PAGE LAYOUT ferry 2026-10-19.
    // The looper's 40pt loop row it used to budget was never built; the tab row it really draws is 29.)

    // --- LANE CARD'S OWN FIXED-HEIGHT ROWS — hoisted to struct level (not re-declared inside `laneCard`),
    // read by `laneCard` itself for its internal row math. ---
    // EXACT DIMENSIONS (2026-10-13, "lane card, exact dimensions" ferry — device-mocked, measured from the
    // real mockup): the card frame is 346×306 at reference size; an outer 10pt inset (a 2pt border, visible
    // only when selected, PLUS 8pt padding — modelled as one flat `cardInset` padding since a cosmetic
    // overlay stroke doesn't itself consume layout space in SwiftUI, and toggling selection must never shift
    // where the content sits) puts the content at 326×286. Three rows — step row (44) · tab row (28) · tab
    // content (202) — separated by two 6pt gaps: 44+6+28+6+202 = 286, matching exactly.
    private let cardInset: CGFloat = EuclideousLaneCardMetrics.inset   // PAGE LAYOUT ferry: the four lane-card rows live in Derivations.swift now,
    private let cardRowGap: CGFloat = EuclideousLaneCardMetrics.rowGap // so the page's floor list and the card draw from the same numbers
    private let cometRowH: CGFloat = EuclideousLaneCardMetrics.cometRowH
    private let tabRowH: CGFloat = EuclideousLaneCardMetrics.tabRowH

    // MARK: - THE PAGE (PAGE LAYOUT ferry, ratified 2026-10-19: "six equal boxes in both orientations, portrait fits the view, MIX fills in portrait")
    //
    // ONE arrangement for both orientations, entirely from `euclideousPageLayout` (Derivations.swift): the view's own size in, six boxes of ONE size out —
    // the four lane cards, the riff panel and the MIX | LANES | FX panel — landscape three columns by two rows, portrait two by three. SUPERSEDES the
    // landscape 36% column split and portrait's content-derived heights (the riff panel's 248 target and the lane cards' fixed-overhead floor): nothing
    // measured from content changes a box's size any more, and every panel lays itself out in its box with its own existing formulas. No ScrollView, nothing
    // clipped, no minimumScaleFactor: a box under some panel's floor is drawn at the formula's values and listed in `page.floors` (device/size reporting).
    //
    // Why `pageGeometry` exists: the body, the swing popover and the settings sheet all need the header's layout, which needs the page's riff-panel x and
    // lane-gutter x — so there is exactly ONE derivation of (container width, header layout, page layout), here.
    private func pageGeometry(_ size: CGSize) -> (containerW: CGFloat, hdr: EuclideousHeaderLayout, page: EuclideousPageLayout) {
        let containerW = size.width - sp16 * 2
        let page = euclideousPageLayout(size: size, bottomInset: pageBottomInset)
        let hdr = euclideousHeaderLayout(containerW: containerW, isLandscape: page.isLandscape,
                                         riffLeadingX: page.riffLeadingX, laneCentreX: page.laneCentreX)
        return (containerW, hdr, page)
    }
    private func pageBody(_ size: CGSize) -> some View {
        let g = pageGeometry(size)
        let page = g.page, box = page.box
        return ZStack(alignment: .topLeading) {
            fourfoldHeader(g.hdr, containerW: g.containerW)
                .offset(x: sp16, y: HM.topMargin)
            // The overlays go on BEFORE the `.offset` (a SwiftUI `.offset` moves only the drawing: an overlay added after it is laid out at the UN-offset position — the "RANDOM" badge and its border
            // appeared at the page's top-left, over the header, instead of on the riff grid; the lock dim had the same fault).
            riffGridView(box: box)
                .frame(width: box.width, height: box.height)
                .overlay(euclideousRandomPanelDim(cornerRadius: 12))
                .overlay(euclideousRandomRiffGridOverlay(cornerRadius: 12))
                .allowsHitTesting(!euclideousLockMode)
                .offset(x: page.riff.minX, y: page.riff.minY)
            sequencerPanel(maxWidth: box.width, maxHeight: box.height, fxAvailable: true)   // FX in portrait too: its columns match the riff grid's (same width)
                .overlay(euclideousRandomPanelDim(cornerRadius: 12))
                .allowsHitTesting(!euclideousLockMode)
                .offset(x: page.seq.minX, y: page.seq.minY)
            // LANE LOCK §1.3: a tap ANYWHERE outside the four lane cards (header incl. the padlock, margins,
            // gutters, the dimmed panels above) finishes lock mode — sits above the header/panels but below
            // the lane cards in z-order, so a card's own controls still get first claim on their own area.
            // Random mode no longer finishes this way (lane-box buttons ferry, 2026-10-22).
            modeFinishLayer(size)
            // AnyView on each laneCard call (2026-10-13 crash fix, see the comment inside laneCard itself): the device crash named the frames "closure #1
            // in closure #1 in landscapeLayout/portraitLayout" resolving 4 laneCard copies' combined type — erasing here keeps each one independently resolvable.
            AnyView(laneCard(0, width: box.width, height: box.height)).offset(x: page.lanes[0].minX, y: page.lanes[0].minY)
            AnyView(laneCard(1, width: box.width, height: box.height)).offset(x: page.lanes[1].minX, y: page.lanes[1].minY)
            AnyView(laneCard(2, width: box.width, height: box.height)).offset(x: page.lanes[2].minX, y: page.lanes[2].minY)
            AnyView(laneCard(3, width: box.width, height: box.height)).offset(x: page.lanes[3].minX, y: page.lanes[3].minY)
            modeHint(size)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: lockOverlayMask) { new in
            for lane in 0..<4 {
                let now = (new >> lane) & 1 == 1
                if now != lockOverlayHeld[lane] { lockOverlayHeld[lane] = now; onLockHeld(lane, now) }
            }
        }
    }

    /// LANE LOCK §1.3: a tap ANYWHERE outside the four lane cards (header incl. the padlock, margins, gutters, the dimmed panels) finishes lock mode — sits above the header/panels but below the lane cards in z-order,
    /// so a card's own controls still get first claim on their own area. Lane-box buttons ferry (2026-10-22): RANDOM MODE no longer finishes this way — Paul wants the riff grid/MIX/LANES/FX reachable while rolling, so
    /// this layer (and the dim wash / hit-test block below) is lock-mode-only now; the dice itself is the only way to end random mode.
    private func modeFinishLayer(_ size: CGSize) -> AnyView {
        guard euclideousLockMode else { return AnyView(EmptyView()) }
        return AnyView(Color.clear.contentShape(Rectangle()).frame(width: size.width, height: size.height)
            .onTapGesture { euclideousFinishActiveMode() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Finish lock mode")
            .accessibilityAddTraits(.isButton))
    }
    /// The page-bottom hint for lock mode (1.5's words) — random mode no longer shows one (it has nothing
    /// to say now that tapping away doesn't finish it).
    private func modeHint(_ size: CGSize) -> AnyView {
        guard euclideousLockMode else { return AnyView(EmptyView()) }
        return AnyView(Text("TAP OFF THE LANE CARDS TO FINISH")
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.85)
            .foregroundColor(Color(hex: 0x8A909A)).lineLimit(1).truncationMode(.tail)
            .frame(width: size.width, height: 14)
            .position(x: size.width / 2, y: size.height - 1 - 7)
            .allowsHitTesting(false))
    }

    /// §1.2: the riff panel + bottom-right panel sit under this wash while LOCK mode is on. Lane-box buttons
    /// ferry (2026-10-22): random mode no longer dims or blocks these panels at all — see
    /// `euclideousRandomRiffGridOverlay` for its own, non-blocking indicator on the riff grid only.
    @ViewBuilder private func euclideousRandomPanelDim(cornerRadius: CGFloat) -> some View {
        if euclideousLockMode {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color(red: 12.0/255, green: 14.0/255, blue: 18.0/255, opacity: 0.62))
                .allowsHitTesting(false)
        }
    }

    /// Lane-box buttons ferry (2026-10-22): a light, NON-blocking indicator that random mode is on, over
    /// the riff grid only (Paul: "Add a randomization mode/overlay to the riff grid") — a judgment call on
    /// the exact look (a thin border + a small badge, in the dice's own "on" colours) since no design was
    /// given; flag if it should look different.
    @ViewBuilder private func euclideousRandomRiffGridOverlay(cornerRadius: CGFloat) -> some View {
        if euclideousRandomMode {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color(hex: 0xDFE3EA).opacity(0.4), lineWidth: 1.5)
                .allowsHitTesting(false)
                .overlay(alignment: .topLeading) {
                    Text("RANDOM").font(.system(size: 8.5, weight: .heavy)).tracking(0.85)
                        .foregroundColor(Color(hex: 0x0D0F14)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xDFE3EA)))
                        .padding(8)
                        .allowsHitTesting(false)
                }
        }
    }

    // MARK: - FOURFOLD HEADER (ferry "Fourfold header", approved by Paul 2026-10-15) — replaces the old one-row-or-two
    // header (title · undo/redo · MIDI IN/CHORD/KEY chips · CHORDS chip · MAIN OUT circles · ON · presets · close) with four
    // GROUPS that each sit over what they control: BRAND (mark, FOURFOLD, undo/redo) · OUTPUTS (the four output rings) ·
    // NOTES (the source control + the key pill) · UTILITIES (presets, close). ON is gone — the page always runs.
    //
    // ONE FORMULA: every position/size below comes from `euclideousHeaderLayout` / `EuclideousHeaderMetrics`
    // (Derivations.swift, unit-tested) — the layout (A one row / B two rows / C compact two rows) is CHOSEN from the same
    // numbers the views are DRAWN with, and `pageBody` reads this header's kind and takes the header's positional inputs (the
    // riff panel's x, the lane gutter's x) from `euclideousPageLayout`, so the body and the header can never disagree. No ScrollView, no
    // `.minimumScaleFactor` (house rules): text that doesn't fit truncates.
    private typealias HM = EuclideousHeaderMetrics
    private var headerInk: Color { Color(hex: 0x0D0F14) }
    private var headerText: Color { Color(hex: 0xF2F4F7) }
    private var headerMuted: Color { Color(hex: 0xAAB0BA) }
    private var headerDim: Color { Color(hex: 0x8A909A) }

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
            // RANDOM MODE ferry §2: the dice, sp8 after redo.
            Color.clear.frame(width: HM.sp8, height: 1)
            euclideousRandomDice(target: target)
            // LANE LOCK ferry §2: the padlock, sp8 after the dice.
            Color.clear.frame(width: HM.sp8, height: 1)
            euclideousLockPadlock(target: target)
        }
    }

    // MARK: LANE LOCK — the padlock (§2) and the mode (§1)
    private func euclideousLockPadlock(target: CGFloat) -> AnyView {
        let on = euclideousLockMode
        let lockedLanes = (0..<4).filter { $0 < locks.count && locks[$0].isLocked }
        let any = !lockedLanes.isEmpty
        let glyph = on || any ? "lock.fill" : "lock.open"
        let glyphColor: Color = on ? Color(hex: 0x0D0F14) : (any ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
        return AnyView(ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(on ? Color(hex: 0xDFE3EA) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.clear : Color(hex: 0x3A3E47), lineWidth: 1))
                .frame(width: 36, height: 36)
            Image(systemName: glyph).font(.system(size: 18, weight: .regular)).foregroundColor(glyphColor)
        }
        .frame(width: target, height: HM.rowH)
        .contentShape(Rectangle())
        .onTapGesture { euclideousLockMode = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lock mode")
        .accessibilityValue((on ? "on" : "off") + (any ? ", " + euclideousLockedLanesPhrase(lockedLanes) : ""))
        .accessibilityHint("Shows the lane locks")
        .accessibilityAddTraits(.isButton)
        .ringToggleTrait())
    }
    /// §1.6: finishing changes nothing in the document — every lock change was made when it was tapped.
    /// Lane-box buttons ferry (2026-10-22): random mode no longer uses this at all — tapping away from
    /// the lane cards used to finish it, but Paul wants the riff grid/MIX/LANES/FX still reachable while
    /// rolling, so only the dice itself (`euclideousRandomToggle`) ends random mode now.
    private func euclideousFinishActiveMode() {
        euclideousLockMode = false
    }

    // MARK: RANDOM MODE — the dice (§2)
    private func euclideousRandomDice(target: CGFloat) -> some View {
        let on = euclideousRandomMode
        return ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(on ? Color(hex: 0xDFE3EA) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.clear : Color(hex: 0x3A3E47), lineWidth: 1))
                .frame(width: 36, height: 36)
            Image(systemName: "die.face.4")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(on ? Color(hex: 0x0D0F14) : headerMuted)
            // A moving dotted ("marching ants") line around the dice while random mode is on — purely
            // decorative, so a plain wall-clock TimelineView is fine (not the render/engine path
            // architecture invariants govern; this never reaches the document or the snapshot).
            if on {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3], dashPhase: euclideousMarchingAntsPhase(tl.date)))
                        .foregroundColor(Color(hex: 0xDFE3EA))
                        .frame(width: 40, height: 40)
                }
            }
        }
        .frame(width: target, height: HM.rowH)
        .contentShape(Rectangle())
        .onTapGesture { euclideousRandomToggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Random mode")
        .accessibilityValue(on ? "on" : "off")
        .accessibilityHint("Turns the lane cards into throw and tweak")
        .accessibilityAddTraits(.isButton)
    }

    /// The dice's marching-ants dash offset: one full [3,3] dash cycle (6pt) every half-second.
    private func euclideousMarchingAntsPhase(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.5) / 0.5) * -6
    }

    private func euclideousRandomToggle() {
        if euclideousRandomMode {
            euclideousRandomFinish()
        } else {
            // §3.3: each card opens on its own normal tab (LISTEN maps to RHYTHM — rawValues 0/1/2 agree,
            // 3 has no counterpart) rather than always defaulting to RHYTHM regardless of what was showing.
            euclideousRandomTab = laneTab.map { EuclideousRandomTab(rawValue: $0.rawValue) ?? .rhythm }
            euclideousRandomMode = true
        }
    }

    // MARK: OUTPUTS — "OUT" + the four output rings (MAIN OUT A–D)
    private func headerOutputs(_ layout: EuclideousHeaderLayout) -> some View {
        let compact = layout.compact
        let pitch = compact ? HM.compactRingPitch : HM.ringPitch
        let naturalPitch = compact ? HM.compactRingNaturalPitch : HM.ringNaturalPitch
        return HStack(spacing: 0) {
            if !compact {
                Text("OUT").font(.system(size: HM.captionSize, weight: .bold, design: .monospaced))
                    .tracking(HM.captionTracking * HM.captionSize).foregroundColor(headerDim).lineLimit(1)
                    .frame(width: HM.captionWidth, alignment: .leading)
                Color.clear.frame(width: HM.sp4, height: 1)
            }
            // One TimelineView for the four rings (never one per ring — the page's standing DSP rule): it only ticks while
            // the transport runs, because the only thing animating here is a strike's pulse (PULSE §6; it keeps running for 1.5 s after a stop, then idles).
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pulseLive)) { tl in
                let now = tl.date.timeIntervalSinceReferenceDate
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { b in outputRing(b, pitch: pitch, naturalPitch: naturalPitch, now: now) }
                }
            }
        }
    }

    /// PULSE §6: a quarter's flash f — its lane routes to this output, the output is ON, and that lane's latest strike of EITHER layer (riff or notes) has happened: f = the flash envelope of the velocity it
    /// played (the louder layer), `now` seconds after its onset, scaled by P. Nothing animates when nothing strikes, and the strike decays by itself after a stop.
    private func ringFlare(_ b: Int, masks: [UInt8], now: Double) -> [Double] {
        let p = euclideousPulseScale(level: pulseLevel)
        guard p > 0, (mainOutMask >> UInt8(b)) & 1 != 0 else { return [0, 0, 0, 0] }
        return (0..<4).map { lane -> Double in
            guard (masks[lane] >> UInt8(b)) & 1 != 0, let s = pulseFeed.latest(lane: lane, where: { $0.onsetAt <= now }) else { return 0 }
            let env = euclideousPulseEnvelopes(velocity: euclideousPulseRingVelocity(riffVel: Int(s.riffVel), notesVel: Int(s.notesVel)), seconds: now - s.onsetAt, scale: p)
            return env.f
        }
    }

    private func outputRing(_ b: Int, pitch: CGFloat, naturalPitch: CGFloat, now: Double) -> some View {
        let masks = euclideousLaneMasks(lines)
        let state = euclideousOutputRingState(output: b, laneMasks: masks, mainOutMask: mainOutMask)
        let held = heldOutput == b
        let flare = ringFlare(b, masks: masks, now: now)
        let ringDim = EuclideousLaneDimLevels((0..<4).map { heldOutput != nil && !held ? false : soloSilenced($0) })
        return EuclideousRingPressable(
            onTap: { toggleMainOut(b); pulseOutput(b) },
            onHold: { began in
                // A hold NEVER toggles. Only the ring that is currently the traced one may clear the trace.
                if began { heldOutput = b } else if heldOutput == b { heldOutput = nil }
            }
        ) {
            // The ring's own canvas renders at its NATURAL size (its hardcoded radius-17 circle needs that room —
            // shrinking the view's own frame instead of scaling the finished render would clip it before the scale
            // ever applied). `.scaleEffect` shrinks the already-complete render to 75%, then the outer `.frame`
            // reclaims only that much row space — same technique as EuclideousSettingsSheet's `mainOutRow`.
            EuclideousOutputRing(letter: ["A", "B", "C", "D"][b], state: state, laneColours: laneAccents, held: held,
                                 flare: flare, dim: ringDim, width: naturalPitch, height: HM.rowH)   // LANE SOLO §6.6: a solo-silenced lane's quarter at 42 % (not while the whole ring is already at 42 % for a trace — never stacked)
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: ringDim)
                .scaleEffect(HM.outputRingScale)
                .frame(width: pitch, height: HM.rowH * HM.outputRingScale)
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
            headerHoldLatch()
        }
    }
    /// HOLD/LATCH (Paul 2026-10-20): two fixed-width chips, mutually exclusive by construction (one optional
    /// field) — tapping the active one again turns it off; tapping the other switches. Only meaningful
    /// against MIDI IN (CHORDS/KEY already generate a fixed algorithmic pool with no physical note-on/off to
    /// freeze or toggle) — dimmed and non-interactive otherwise, same "visible but inert" treatment as every
    /// other source-gated control on this page.
    private func headerHoldLatch() -> some View {
        let enabled = noteSource == .midi
        return HStack(spacing: HM.sp4) {
            headerHoldLatchChip(.hold, label: "HOLD", width: HM.holdLatchChipWidths[0], enabled: enabled)
            headerHoldLatchChip(.latch, label: "LATCH", width: HM.holdLatchChipWidths[1], enabled: enabled)
        }
    }
    private func headerHoldLatchChip(_ mode: EuclideousHoldLatchMode, label: String, width: CGFloat, enabled: Bool) -> some View {
        let active = enabled && holdLatchMode == mode
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(active ? Color(hex: 0xDFE3EA) : Color.clear).frame(height: 24)
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
                .foregroundColor(!enabled ? headerMuted.opacity(0.4) : (active ? headerInk : headerMuted)).lineLimit(1)
        }
        .frame(width: width, height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            onSetHoldLatchMode(holdLatchMode == mode ? nil : mode)
        }
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityHint(enabled ? "" : "Only available for MIDI In")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(active ? .isSelected : [])
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
            else if src == .chords { settingsOpen = false; swingPopupOpen = false; chordsPopupOpen = true }   // §2.1: opening it closes the sheet first
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
        .onTapGesture { settingsOpen = false; swingPopupOpen = false; keyPopupOpen = true }   // §2.1: opening it closes the sheet first
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key, \(euclideousKeySpokenName(root: keyRoot, type: keyType))")
        .accessibilityHint("Double-tap to change")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: UTILITIES — presets, swing, reel, settings (outline icons, one family with undo/redo)
    private func headerUtilities(_ layout: EuclideousHeaderLayout) -> some View {
        let target = layout.compact ? HM.compactTarget : HM.target
        return HStack(spacing: 0) {
            Image(systemName: "folder").font(.system(size: 18)).foregroundColor(headerDim)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture { settingsOpen = false; swingPopupOpen = false; onOpenPresets() }   // §2.1: opening it closes the other overlays first
                .accessibilityLabel("Presets").accessibilityAddTraits(.isButton)
            // SWING (2026-10-17): a third icon, same selected-state styling as the gear just below. Tinted
            // when swing is away from its 50 (straight) default, so a non-neutral value stays visible at a
            // glance even with the popover closed — the whole point of putting this control where it's seen.
            Image(systemName: "metronome")
                .font(.system(size: 18))
                .foregroundColor(swingPopupOpen ? Color(hex: 0x0D0F14) : (swing == 50 ? headerDim : Color(hex: 0x4FD1E8)))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(swingPopupOpen ? Color(hex: 0xDFE3EA) : Color.clear))
                .animation(.easeInOut(duration: 0.15), value: swingPopupOpen)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture {
                    if !swingPopupOpen { closeAllOtherOverlays(); settingsOpen = false }
                    swingPopupOpen.toggle()
                }
                .accessibilityLabel("Swing, \(swing == 50 ? "straight" : "\(swing)")").accessibilityAddTraits(.isButton).accessibilityAddTraits(swingPopupOpen ? .isSelected : [])
            // REEL (2026-10-23): the pass browser / MIDI recorder. Sits after SWING so presets and SWING keep their slots
            // (the swing popover's anchor below is unchanged); the gear stays last.
            reelHeaderButton(target: target)
            // FOURFOLD SETTINGS (2026-10-15 ferry §1): the × (xmark) LEAVES the header — its old job (back to
            // the workbench) moves to the sheet footer's WORKBENCH link (§7.1). UTILITIES is now 4 icons (SWING joined
            // it 2026-10-17, REEL 2026-10-23 — `euclideousHeaderGroupWidths` carries the real count).
            Image(systemName: "gearshape").font(.system(size: 18)).foregroundColor(settingsOpen ? Color(hex: 0x0D0F14) : headerDim)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(settingsOpen ? Color(hex: 0xDFE3EA) : Color.clear))
                .animation(.easeInOut(duration: 0.15), value: settingsOpen)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture {
                    if !settingsOpen { closeAllOtherOverlays(); swingPopupOpen = false }
                    settingsOpen.toggle()
                }
                .accessibilityLabel("Settings").accessibilityAddTraits(.isButton).accessibilityAddTraits(settingsOpen ? .isSelected : [])
        }
    }
    /// The REEL icon + its touch target. An `AnyView`-returning leaf like the page's other additions: it kept `headerUtilities`' DEBUG frame flat on the 1 MB extension stack (+0.6 KB inline, measured).
    private func reelHeaderButton(target: CGFloat) -> AnyView {
        AnyView(
            EuclideousReelIcon(recording: reelRecording)
                .frame(width: target, height: HM.rowH).contentShape(Rectangle())
                .onTapGesture { closeAllOtherOverlays(); settingsOpen = false; onOpenReel() }   // §2.1: opening it closes the other overlays first
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reelRecording ? "Reel, recording" : "Reel")
                .accessibilityHint("Opens the pass browser to hear and save what Fourfold played")
                .accessibilityAddTraits(.isButton)
        )
    }
    /// SWING popover (2026-10-17): the SAME compact scrim-less anchored-card chrome as `resetPopupCard`
    /// (reused, not reinvented). Range 50...75 matches `SceneState.swing` exactly (§4 v2.3) — dragging to
    /// the slider's own minimum IS "straight," so the readout names it rather than showing a bare "50".
    private var swingPopupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SWING").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.04).foregroundColor(Color(hex: 0xAAB0BA))
                Spacer()
                Text(swing == 50 ? "STRAIGHT" : "\(swing)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xF2F4F7))
            }
            .frame(height: 14)
            Slider(value: Binding(get: { Double(swing) }, set: { onSetSwing(Int($0.rounded())) }), in: 50...75)
                .tint(Color(hex: 0x4FD1E8))
            HStack {
                Text("STRAIGHT").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                Spacer()
                Text("MAX").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
            }
        }
        .padding(8).frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    /// §2.1: "one overlay at a time: opening the key pill, the chord grid or presets closes the sheet first,
    /// and opening the sheet closes them" — this half of that rule (closing the OTHER three before the sheet
    /// opens); the sibling trigger points (key pill, chords segment, the folder/presets icon) each call this
    /// too before opening their own overlay. No existing "one overlay at a time" coordination to extend —
    /// every pop-up on this page toggles fully independently today, confirmed by reading each one first.
    private func closeAllOtherOverlays() {
        keyPopupOpen = false; chordsPopupOpen = false; resetPopupLane = nil; swingPopupOpen = false; riffTabMenuLane = nil
        chordsTabMenuIndex = nil
    }

    // MARK: LANE SIDE of the output cues (§10) — pulse (after a tap) and trace (while held)
    /// What lane `lane`'s CARD shows right now (dim only, §10.3 — the ring moved to MIX/the MIX tab, below):
    /// nil when nothing is pulsing/held or this lane isn't involved.
    private func outputCue(forLane lane: Int) -> EuclideousOutputCueInfo? {
        let mode: EuclideousOutputCueMode, output: Int, token: Int
        if let h = heldOutput { mode = .trace; output = h; token = 0 }
        else if let p = outputPulse { mode = .pulse; output = p.output; token = p.token }
        else { return nil }
        let cue = euclideousOutputCues(output: output, laneMasks: euclideousLaneMasks(lines), mode: mode)[lane]
        return cue == .none ? nil : EuclideousOutputCueInfo(output: output, held: mode == .trace, token: token, cue: cue)
    }
    /// §10.2/§10.3/§10.5 — where the active output's ring goes, if any: the bottom-right panel's own MIX OUT
    /// buttons (one per routed lane) when it's showing MIX, else once around the MIX tab chip — nil entirely
    /// while the panel isn't on screen (the one caller that can't show the panel never calls this).
    private func outputRingTargets(panelShowsMix: Bool) -> (output: Int, held: Bool, token: Int, targets: [EuclideousOutputRingTarget])? {
        let held: Bool, output: Int, token: Int
        if let h = heldOutput { held = true; output = h; token = 0 }
        else if let p = outputPulse { held = false; output = p.output; token = p.token }
        else { return nil }
        let targets = euclideousOutputRingTargets(output: output, laneMasks: euclideousLaneMasks(lines), panelShowsMix: panelShowsMix)
        return targets.isEmpty ? nil : (output, held, token, targets)
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
    /// CHORDS GRID ferry (Paul 2026-10-24): rebuilt from the single-grid pop-up (CHORDS BUTTON ferry,
    /// 2026-10-08) per claude/ferry-chords-grid.md — four progression tabs (§4), borrowed-chord + colour rows
    /// (§3), a playhead + chord name (§6) and a pool strip (§7). Every frame comes from
    /// `euclideousChordsPopupLayout` (Derivations.swift) — nothing here re-derives a size. Tapping a tab
    /// switches it immediately (Paul, 2026-10-24: "I only want the chords tab to be switched manually when a
    /// user clicks it") — no queue-to-next-column-boundary, so "shown" and "playing" are always the same tab.
    private var chordsActiveSet: Int { max(0, min(3, activeChordSet)) }
    private var chordsActive: MachineParams { let i = chordsActiveSet; return i < chordSets.count ? chordSets[i] : MachineParams() }
    private func chordsPopupCard(_ size: CGSize) -> some View {
        let chords = chordsActive
        let steps = chords.chordsStepsResolved
        let degrees = chords.chordsDegreesResolved16()
        let colours = chords.chordsColoursResolved16()
        let minorKey = euclideousScaleIsMinor(keyType.intervals)
        let maxW = min(640, size.width - 32)
        let contentBox = CGSize(width: maxW - 40, height: (size.height - 60) - 40)
        let layout = euclideousChordsPopupLayout(box: contentBox, steps: steps)
        return ZStack(alignment: .topLeading) {
            chordsTitleRow(chords: chords, degrees: degrees, colours: colours, steps: steps, minorKey: minorKey)
                .frame(width: contentBox.width, height: EuclideousChordsPopupMetrics.titleRowH, alignment: .leading)
            chordsTabRow()
                .frame(width: contentBox.width, height: EuclideousChordsPopupMetrics.tabRowH)
                .offset(y: layout.tabRowTop)
            chordsStepsRateRow(chords: chords, steps: steps)
                .frame(height: EuclideousChordsPopupMetrics.stepsRateRowH, alignment: .leading)
                .offset(y: layout.stepsRateRowTop)
            chordsGrid(layout: layout, chords: chords, degrees: degrees, colours: colours, steps: steps, minorKey: minorKey)
                .frame(width: layout.gridWidth, height: layout.gridH, alignment: .topLeading)
                .offset(y: layout.gridTop)
            chordsPlayheadBar(layout: layout, chords: chords, steps: steps)
                .frame(width: layout.gridWidth, height: EuclideousChordsPopupMetrics.playheadBarH, alignment: .leading)
                .offset(y: layout.playheadBarTop)
            chordsPoolStrip(layout: layout, chords: chords, degrees: degrees, colours: colours, steps: steps, minorKey: minorKey)
                .frame(width: layout.gridWidth, height: EuclideousChordsPopupMetrics.poolStripH, alignment: .leading)
                .offset(y: layout.poolStripTop)
        }
        .frame(width: contentBox.width, height: contentBox.height, alignment: .topLeading)
        .padding(20)
        .frame(width: maxW)
        // CHORDS GRID ferry §2.2: top-align — a `.frame(maxHeight:)` with no `alignment:` defaults to .center,
        // which is what pushed the title down inside the near-full-height box (Paul's screenshot).
        .frame(maxHeight: size.height - 60, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    /// §6.1/§6.3: the title row — "CHORDS", the live chord name, and the close button. §6.1's own rule: read
    /// `euclideousChordsPlayingColumn` ONLY, never a second derivation. §6.4: stopped, no wash/bar and the
    /// name shows the column the next PLAY would start on (the same formula, at the frozen anchor beat).
    private func chordsTitleRow(chords: MachineParams, degrees: [Int], colours: [Int], steps: Int, minorKey: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.playing)) { tl in
            let beat = walkTagBeat(at: tl.date)
            let col = chordsPlayingColumn(beat: beat, chords: chords, steps: steps)
            let (name, _) = chordsNameAndIsRest(column: col, degrees: degrees, colours: colours, steps: steps, minorKey: minorKey)
            HStack(spacing: 0) {
                Text("CHORDS").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                Text(" \u{00B7} ").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Text(name).font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
                Spacer()
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    .contentShape(Rectangle()).onTapGesture { chordsPopupOpen = false }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chords, \(name)")
        }
    }
    /// §6.1: beat → column, via the ONE shared formula (`euclideousChordsPlayingColumn`). §6.4's "the column
    /// the next play would start on" IS the beat-floor formula's own answer when stopped (the frozen anchor
    /// beat still floors to a column) — no second branch needed for the stopped case.
    private func chordsPlayingColumn(beat: Double, chords: MachineParams, steps: Int) -> Int {
        let rotate = ((chords.chordsRotate ?? 0) % max(1, steps) + max(1, steps)) % max(1, steps)
        let col = euclideousChordsPlayingColumn(beat: beat, rateBeats: chords.chordsRateResolved.beats)
        return ((col + rotate) % max(1, steps) + max(1, steps)) % max(1, steps)
    }
    /// The chord NAME at a given on-screen COLUMN (not the carry-resolved engine column — the grid is the
    /// authored score, so this reads the column's own bright/faint value exactly like `chordsMatrixCell`
    /// does for the cells themselves), plus whether that column is a rest (§3.3/§6.3's "REST" display).
    private func chordsNameAndIsRest(column c: Int, degrees: [Int], colours: [Int], steps: Int, minorKey: Bool) -> (String, Bool) {
        guard steps > 0 else { return ("REST", true) }
        let (deg, rest) = chordsDegreeAt(step: c, degrees: Array(degrees.prefix(steps)), rotate: 0)
        if rest { return ("REST", true) }
        guard let src = chordsSourceStepAt(step: c, degrees: Array(degrees.prefix(steps)), rotate: 0) else { return ("REST", true) }
        let colour = src < colours.count ? colours[src] : 0
        let tones = euclideousChordTones(degree: deg, colour: colour, scaleTones: keyType.intervals, rootNote: 48 + keyRoot, minorKey: minorKey, spread: .close)
        let flat: Bool
        if deg >= 8 { flat = euclideousBorrowedRowForcesFlat(row: deg - 8, minorKey: minorKey) }
        else { flat = euclideousKeyIsFlat(((keyRoot % 12) + 12) % 12, scaleType: keyType) }
        let rootNote: Int
        if deg >= 8 { rootNote = (48 + keyRoot) + euclideousBorrowedTriad(row: deg - 8, minorKey: minorKey)[0] }
        else { let n = keyType.intervals.count; rootNote = n > 0 ? (48 + keyRoot) + keyType.intervals[((deg % n) + n) % n] : 48 + keyRoot }
        return (euclideousChordName(tones: tones, rootNote: rootNote, flatSpelling: flat), false)
    }

    /// §4.1-§4.3: four chord-set tabs, the exact riff-tab look (`riffTabRow`'s own sizing/fills/colours).
    /// §4.2: playing triangle (only the active tab has one, since switching is immediate) · number · chord
    /// icon · step count. §4.4: tap switches immediately; §4.6: long-press opens COPY/PASTE/CLEAR.
    private func chordsTabRow() -> some View {
        HStack(spacing: EuclideousRiffPanelMetrics.tabGap) {
            ForEach(0..<4, id: \.self) { i in
                let sel = i == chordsActiveSet
                let ink = Color(hex: 0x0D0F14)
                let set = i < chordSets.count ? chordSets[i] : MachineParams()
                HStack(spacing: 0) {
                    if sel {
                        RiffPlayTriangle().fill(ink).frame(width: 5, height: 6)
                        Color.clear.frame(width: 3, height: 1)
                    }
                    Text("\(i + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? ink : Color(hex: 0xAAB0BA))
                    Color.clear.frame(width: 4, height: 1)
                    chordsTabIcon(degrees: set.chordsDegreesResolved16(), steps: set.chordsStepsResolved,
                                  color: sel ? ink : Color(hex: 0xDFE3EA))
                    Color.clear.frame(width: 6, height: 1)
                    Text("\(set.chordsStepsResolved)").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xAAB0BA))
                }
                .frame(maxWidth: .infinity).frame(height: EuclideousChordsPopupMetrics.tabRowH)
                .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture { onSwitchChordSet(i) }
                .onLongPressGesture(minimumDuration: 0.5) { chordsTabMenuIndex = i }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Progression \(i + 1), \(set.chordsStepsResolved) steps\(sel ? ", playing" : "")")
            }
        }
    }
    /// §4.3: 22x12, one mark per column at its chord row (0...11 — `euclideousChordsTabIconRow`; REST draws
    /// nothing; colour rows aren't drawn here at all, this icon shows DEGREE only).
    private func chordsTabIcon(degrees: [Int], steps: Int, color: Color) -> some View {
        let n = max(1, steps)
        let colPitch: CGFloat = 22.0 / CGFloat(n)
        return Canvas { ctx, _ in
            for c in 0..<n where c < degrees.count {
                guard let row = euclideousChordsTabIconRow(degrees[c]) else { continue }
                let rect = CGRect(x: CGFloat(c) * colPitch, y: CGFloat(row) * 1.0, width: max(1, colPitch - 0.4), height: 0.8)
                ctx.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: 22, height: 12)
    }
    private func chordsTabMenuCard(_ idx: Int) -> some View {
        func row(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .white.opacity(0.85) : .white.opacity(0.3))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { if enabled { action() } }
        }
        return VStack(spacing: 8) {
            Text("PROGRESSION \(idx + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            row("COPY") {
                chordsClipboard = idx < chordSets.count ? chordSets[idx] : nil
                chordsTabMenuIndex = nil
            }
            row("PASTE", enabled: chordsClipboard != nil) {
                guard let c = chordsClipboard else { return }
                onEditChordSet(idx) { $0 = c }
                chordsTabMenuIndex = nil
            }
            row("CLEAR") {
                onEditChordSet(idx) { $0 = MachineParams() }
                chordsTabMenuIndex = nil
            }
        }
        .padding(16).frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private func chordsStepsRateRow(chords: MachineParams, steps: Int) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Text("STEPS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                chordsStepStepper("\u{2212}") { onEditChordSet(chordsActiveSet) { $0.chordsSteps = max(1, steps - 1) } }
                Text("\(steps)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)).frame(minWidth: 20)
                chordsStepStepper("+") { onEditChordSet(chordsActiveSet) { $0.chordsSteps = min(16, steps + 1) } }
            }
            HStack(spacing: 6) {
                Text("RATE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                HStack(spacing: 2) {
                    ForEach(StepRate.allCases, id: \.self) { r in
                        let on = chords.chordsRateResolved == r
                        Text(r.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.7)).lineLimit(1)
                            .frame(width: 34, height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                            .onTapGesture { onEditChordSet(chordsActiveSet) { $0.chordsRate = r } }
                    }
                }
            }
        }
    }
    private func chordsStepStepper(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    /// §2.4/§3: 18 rows (7 diatonic + 4 borrowed + REST, a divider, then 6 colour rows) x `steps` columns.
    /// §3.1: chord rows (0...11) are an unconditional write, as the plain CHORDS processor's own matrix
    /// already does. §3.3: colour rows (12...17) light-and-clear-others / tap-again-to-clear; in a REST
    /// column they draw at 42% but stay tappable and keep their stored value.
    private func chordsGrid(layout: EuclideousChordsPopupLayout, chords: MachineParams, degrees: [Int], colours: [Int], steps: Int, minorKey: Bool) -> some View {
        let gridTop = layout.gridTop
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.playing)) { tl in
            let beat = walkTagBeat(at: tl.date)
            let playingCol = clock.playing ? chordsPlayingColumn(beat: beat, chords: chords, steps: steps) : -1
            ZStack(alignment: .topLeading) {
                if playingCol >= 0 && playingCol < steps {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(width: layout.cellW, height: layout.rowTop(11) + layout.rowH - gridTop)
                        .offset(x: layout.columnLeft(playingCol))
                }
                // §2.4: the 1pt divider line, across the cell columns only (not the label column).
                Rectangle().fill(Color(hex: 0x2A2D34))
                    .frame(width: layout.gridWidth - EuclideousChordsPopupMetrics.labelW - EuclideousChordsPopupMetrics.sp4, height: 1)
                    .offset(x: EuclideousChordsPopupMetrics.labelW + EuclideousChordsPopupMetrics.sp4, y: layout.dividerY - gridTop)
                // Row LABELS, drawn once (their own loop; not part of §8.4's column-ordered traversal).
                ForEach(0..<18, id: \.self) { r in
                    let label = euclideousChordsRowLabel(row: r, scaleTones: keyType.intervals, minorKey: minorKey)
                    Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
                        .frame(width: EuclideousChordsPopupMetrics.labelW, height: layout.rowH, alignment: .leading)
                        .offset(x: 0, y: layout.rowTop(r) - gridTop)
                }
                // §8.4: VoiceOver reads the grid BY COLUMN — column-outer, row-inner (purely an iteration-order
                // choice; every cell's own POSITION still comes from its absolute layout.columnLeft/rowTop, so
                // this reorder changes nothing visually).
                ForEach(0..<steps, id: \.self) { c in
                    ForEach(0..<18, id: \.self) { r in
                        let rowY = layout.rowTop(r) - gridTop
                        chordsCell(row: r, column: c, degrees: degrees, colours: colours, steps: steps, isPlayingColumn: c == playingCol)
                            .frame(width: layout.cellW, height: layout.rowH)
                            .offset(x: layout.columnLeft(c), y: rowY)
                            // §7.3: a finger down on ANY cell shows that column's pool instead of the playing one.
                            .onLongPressGesture(minimumDuration: 0.001, maximumDistance: 50,
                                                pressing: { pressing in chordsHeldColumn = pressing ? c : (chordsHeldColumn == c ? nil : chordsHeldColumn) },
                                                perform: {})
                    }
                }
            }
        }
    }
    @ViewBuilder private func chordsCell(row r: Int, column c: Int, degrees: [Int], colours: [Int], steps: Int, isPlayingColumn: Bool) -> some View {
        let isColourRow = r >= 12
        let (_, isRest) = chordsDegreeAt(step: c, degrees: Array(degrees.prefix(max(1, steps))), rotate: 0)
        let playingSuffix = isPlayingColumn ? ", playing" : ""
        if isColourRow {
            let colourVal = r - 11   // row 12 -> ChordColour.seventh(1) ... row 17 -> .sus4(6)
            let on = c < colours.count && colours[c] == colourVal
            RoundedRectangle(cornerRadius: 4)
                .fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : 0.12), lineWidth: 1))
                .opacity(isRest ? 0.42 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    onEditChordSet(chordsActiveSet) { p in
                        var a = p.chordsColoursResolved16()
                        if c < a.count { a[c] = (a[c] == colourVal ? 0 : colourVal) }
                        p.chordsColours = a
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Column \(c + 1), \(euclideousChordsRowLabel(row: r, scaleTones: keyType.intervals, minorKey: euclideousScaleIsMinor(keyType.intervals))), \(on ? "on" : "off")\(playingSuffix)")
        } else if let deg = euclideousChordsRowDegree(r) {
            let cell = chordsMatrixCell(Array(degrees.prefix(16)), step: c, steps: steps)
            let on = cell.bright == deg
            let dimOn = !on && cell.faint == deg
            RoundedRectangle(cornerRadius: 4)
                .fill(on ? Color.white.opacity(0.9) : (dimOn ? Color.white.opacity(0.22) : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(on ? 0.9 : 0.12), lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture {
                    // Matches the regular CHORDS processor's own set: an unconditional write, no
                    // tap-again-to-clear (REST is its own explicit row) — §3.1, literal.
                    onEditChordSet(chordsActiveSet) { p in
                        var a = p.chordsDegreesResolved16()
                        if c < a.count { a[c] = deg }
                        p.chordsDegrees = a
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Column \(c + 1), \(euclideousChordsRowLabel(row: r, scaleTones: keyType.intervals, minorKey: euclideousScaleIsMinor(keyType.intervals))), \(on ? "selected" : "not selected")\(playingSuffix)")
        } else {
            EmptyView()
        }
    }

    /// §6.2/§6.4: the playing-column wash (drawn by the grid itself reading the SAME column) + the 3pt bar
    /// underneath. No wash/bar while stopped.
    private func chordsPlayheadBar(layout: EuclideousChordsPopupLayout, chords: MachineParams, steps: Int) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.playing)) { tl in
            let beat = walkTagBeat(at: tl.date)
            let col = clock.playing ? chordsPlayingColumn(beat: beat, chords: chords, steps: steps) : -1
            ZStack(alignment: .topLeading) {
                if col >= 0 && col < steps {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0xDFE3EA))
                        .frame(width: layout.cellW, height: EuclideousChordsPopupMetrics.playheadBarH)
                        .offset(x: layout.columnLeft(col))
                }
            }
        }
    }

    /// §7: eight rank chips splitting the grid's width, showing the pool of the PLAYING column (or the held
    /// column, §7.3, while a finger is down on a grid cell).
    private func chordsPoolStrip(layout: EuclideousChordsPopupLayout, chords: MachineParams, degrees: [Int], colours: [Int], steps: Int, minorKey: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.playing)) { tl in
            let beat = walkTagBeat(at: tl.date)
            let playingCol = clock.playing ? chordsPlayingColumn(beat: beat, chords: chords, steps: steps) : chordsPlayingColumn(beat: clock.anchor, chords: chords, steps: steps)
            let shownCol = chordsHeldColumn ?? playingCol
            let (deg, rest) = steps > 0 ? chordsDegreeAt(step: shownCol, degrees: Array(degrees.prefix(steps)), rotate: 0) : (0, true)
            let src = steps > 0 ? chordsSourceStepAt(step: shownCol, degrees: Array(degrees.prefix(steps)), rotate: 0) : nil
            let colour = (src.map { $0 < colours.count ? colours[$0] : 0 }) ?? 0
            let tones = rest ? [] : euclideousChordTones(degree: deg, colour: colour, scaleTones: keyType.intervals, rootNote: 48 + keyRoot, minorKey: minorKey, spread: .close)
            let pool = euclideousGlobalPoolExtended(sortedRaw: tones)
            let chipW = (layout.gridWidth - EuclideousMixMetrics.sp4 * 7) / 8
            let rootPc = tones.isEmpty ? -1 : ((tones[0] % 12) + 12) % 12
            HStack(spacing: EuclideousMixMetrics.sp4) {
                ForEach(0..<8, id: \.self) { i in
                    let rank = i + 1
                    let note = i < pool.count ? UInt8(max(0, min(127, pool[i]))) : nil
                    let isRoot = note.map { Int($0) % 12 == rootPc } ?? false
                    let isColourTone = note != nil && i >= 3 && colour != 0   // the 3-note triad's own ranks are 1-3; anything added by a colour is rank 4+
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        if let note {
                            VStack(spacing: 2) {
                                Text("\(rank)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 3)
                                Spacer()
                                Text(euclideousDisplayNoteName(note, source: .chords, pool: pool.map { UInt8(max(0, min(127, $0))) }, keyRoot: keyRoot, keyType: keyType))
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                                Spacer()
                            }
                        } else {
                            Text("\u{2013}").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if isRoot {
                            Rectangle().fill(Color(hex: 0xDFE3EA)).frame(height: 2)
                                .padding(.horizontal, 4)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        if isColourTone {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundColor(Color(hex: 0xAAB0BA))
                        }
                    }
                    .frame(width: chipW, height: EuclideousChordsPopupMetrics.poolStripH)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rest ? "Pool, rest" : "Pool, column \(shownCol + 1)")
        }
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
    /// THE LANE STRIP's plan (LANE STRIP ferry 2026-10-21 — replaces the footer bands, the NOTES-tab pips and the grey fill; the footers' own per-hit functions now drive the riff track and the key
    /// row). Worked out per body: the rhythm's hits and the pass the footers show (`euclideousFooterPass` — the lap that contains the UI clock at this body's evaluation, whose riff columns come from the
    /// engine's own walk), the footers' states for it (`euclideousFooterStates`), then `euclideousStripHits` turns them into chips, gaps and keys. A FOLLOW lane plays its PARTNER's pattern and step count,
    /// so everything is predicted from that — the same finished buffer the engine and the step bar use (`euclideousEffectivePattern`).
    private func laneStripPlan(_ idx: Int, _ line: EuclidLine) -> EuclideousStripPlan {
        // LISTEN REBUILT (2026-10-23): SHADOW and ECHO both pause RIFF+NOTES whole (§7, §9.9's `borrowedTabs`) —
        // so the strip's own riff/notes track is ignored under either, not SHADOW alone.
        let shadowed = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
        let layerOn = euclideousNotesLayerIsOn(line) && !shadowed   // a borrowing lane's own riff and lit notes are ignored entirely (LISTEN §6)
        let playsRiff = euclideousLanePlaysRiff(line)
        let grey = !shadowed && euclideousNotesGreyFooters(riffOn: line.riffOnResolved, notesLayerOn: layerOn, when: line.notesWhenResolved)
        let follow = euclideousEffectivePattern(lane: idx, lines: lines).flatMap { $0.followsPartner ? $0 : nil }
        let steps = follow?.n ?? max(2, min(16, line.steps))
        let walkCfg = riffWalkConfig(idx)
        // RHYTHM POLISH: a lane with a fractional OFFSET and/or a fine TILT is predicted from the engine's TICK-SPACE layout (the walk config's), each hit in the box its start time falls in
        let timed = walkCfg.flatMap { $0.timing.isNone ? nil : $0 }
        let hitSteps = timed.map { euclideousLapHitSteps(layoutCells: $0.buf, n: steps, dir: line.directionResolved) }
            ?? follow.map { euclideousLapHitSteps(buf: Array($0.buf.prefix($0.n)), dir: line.directionResolved) }
            ?? euclideousLapHitSteps(pulses: line.pulses, steps: steps, rotate: line.rotate,
                                      tilt: line.tiltResolved, patternMiss: line.patternMissResolved,
                                      customHits: line.customHitsResolved(steps), dir: line.directionResolved)
        let cfg = (playsRiff || grey || layerOn) ? walkCfg : nil   // the walk's facts: the pass, REPEAT's lookback and the keys' count k need them; a plain lane needs none
        var prediction: [Int]? = nil
        var lapStartTick: Int64? = nil
        if playsRiff || grey {
            let ws = idx < riffWalkState.count ? riffWalkState[idx] : Int64(0)
            let pass = euclideousFooterPass(line: line, cfg: cfg, hitSteps: hitSteps, lapSteps: steps, liveOrd: ws, nowBeat: lanesMusicalBeat(real: walkTagBeat(at: Date())))
            prediction = pass.prediction; lapStartTick = pass.lapStartTick
        } else if layerOn, let cfg {
            lapStartTick = euclideousLapStart(cfg: cfg, beat: lanesMusicalBeat(real: walkTagBeat(at: Date())))?.lapStartTick   // the keys' count k needs the pass's ticks even with the riff off
        }
        // riff off with nothing lit: every step is a `.miss` ("nothing will sound"); a hit an FX TIE cell applies to reads as a hit on a tied rest
        let ranks = effectiveGridRanks
        var pattern = [Bool](repeating: false, count: steps)
        for hs in hitSteps where hs.bufIdx >= 0 && hs.bufIdx < steps { pattern[hs.bufIdx] = true }
        let notes: EuclideousStripNotes? = layerOn
            ? EuclideousStripNotes(layerOn: true, when: line.notesWhenResolved, chance: line.notesChanceResolved, way: line.notesPlayAsResolved, list: notesPlayList(line), lane: idx) : nil
        let legs = euclideousStripLegs(pattern: pattern, hitSteps: hitSteps, prediction: prediction, lapSteps: steps, ranks: ranks, anyLit: layerOn, fxTieColumns: euclideousFXTieColumns(fx, line: line, lane: idx),
                                       pingPong: line.directionResolved == .pingpong, riffPlays: playsRiff, grey: grey, onRest: line.riffOnRestResolved, cfg: cfg, lapStartTick: lapStartTick,
                                       notes: notes, name: stripNoteName)
        // VoiceOver (§6): read the sweep the lane is on at this body (PING-PONG has two); the note at a written rank is the riff grid's row name, a pitch is spoken as the NOTES tab's keys speak it
        var nowLeg = 0
        if legs.count > 1, let cfg, let lapStartTick { nowLeg = euclideousStripLegIndex(raw: Double(Int64((lanesMusicalBeat(real: walkTagBeat(at: Date())) / cfg.sub).rounded(.down)) - lapStartTick), n: steps, legCount: legs.count) }
        let pool = riffLivePool
        let extended = euclideousGlobalPoolExtended(sortedRaw: pool.map { Int($0) })
        let phrase = euclideousStripHitsPhrase(hits: legs[min(nowLeg, legs.count - 1)].hits,
                                               spokenRank: { r in
                                                   guard r >= 1, r <= extended.count, (0...127).contains(extended[r - 1]) else { return nil }
                                                   return euclideousAccessibleDisplayNoteName(UInt8(extended[r - 1]), source: noteSource, pool: pool, keyRoot: keyRoot, keyType: keyType)
                                               },
                                               spokenPitch: { p in
                                                   (0...127).contains(p) ? euclideousAccessibleDisplayNoteName(UInt8(p), source: noteSource, pool: pool, keyRoot: keyRoot, keyType: keyType) : "no note"
                                               })
        return EuclideousStripPlan(legs: legs, sweepLength: steps, cfg: cfg, lapStartTick: lapStartTick, riffPlays: playsRiff && !(noteSource == .midi && pool.isEmpty), shadowed: shadowed, hitsPhrase: phrase)
    }
    /// A pitch named the way the riff grid names its rows (`riffNoteLabelColumn`): C4, A♭3 — spelled relative to what is held for MIDI IN / CHORDS, from the key for KEY.
    private func stripNoteName(_ p: Int) -> String {
        guard (0...127).contains(p) else { return "\u{2013}" }
        return euclideousDisplayNoteName(UInt8(p), source: noteSource, pool: riffLivePool, keyRoot: keyRoot, keyType: keyType)
    }
    /// The lane's play list (6.5) against the pool the riff grid's name column reads — what the NOTES tab's keys and the strip's key labels both name.
    private func notesPlayList(_ line: EuclidLine) -> EuclideousNotesList {
        let pool = riffLivePool
        return euclideousNotesPlayList(order: line.litOrderResolved, poolCount: pool.count, receivedOnly: line.notesReceivedOnlyResolved) { rank in
            riffResolve(rank: rank, oct: 0, n: pool.count, wrap: .fold, asc: { Int(pool[$0]) })
        }
    }
    /// 1.4 / 1.6: which step's chip is lane `idx`'s current one at UI beat `beat` — the chip of the hit its riff arrow shows (the same walk plan the arrow reads, per frame; TIE stays on the tied note).
    /// nil while the lane or the transport is stopped, before its first hit of the pass, with the riff off, and while MIDI IN holds nothing (the arrows are suppressed then too).
    private func stripCurrentStep(_ idx: Int, plan: EuclideousStripPlan, beat: Double) -> EuclideousStripCurrent? {
        guard plan.riffPlays, let cfg = plan.cfg, idx < lines.count, idx < riffPositions.count, clock.playing, lines[idx].enabledResolved else { return nil }
        let ord: Int64? = idx < riffWalkState.count ? riffWalkState[idx] : nil
        guard let tp = euclideousWalkTagPlan(cfg: cfg, ranks: effectiveGridRanks, beat: beat, secondsPerBeat: 60.0 / max(1.0, clock.tempo), polledStep: riffPositions[idx], running: true,
                                             polledOrdinal: ord) else { return nil }
        let arrow = euclideousLaneArrowState(lane: idx, cfg: cfg, plan: tp, polledOrdinal: ord ?? 0)
        return euclideousStripCurrentStep(cfg: cfg, landedTick: tp.landedTick, passLapStartTick: plan.lapStartTick, arrowStaysOnTiedNote: tp.seatIsRest && !arrow.hollow, legs: plan.legs)
    }

    @ViewBuilder private func laneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        if euclideousRandomMode {
            euclideousRandomLaneCard(idx, width: width, height: height)
        } else if euclideousLockMode {
            euclideousLockLaneCard(idx, width: width, height: height)
        } else {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        let tab = idx < laneTab.count ? laneTab[idx] : .rhythm
        let stripPlan = laneStripPlan(idx, line)   // LANE STRIP ferry: the riff track and the key row, from the footers' own per-hit functions
        // ONE INNER WIDTH FOR EVERY ROW — every row below is built from THIS one width, never the raw card
        // `width` (W = 326 at the ferry's own reference 346pt card). "Wider cards: flexible items share the
        // extra width" — `innerWidth` scales directly with `width`, so every formula below that derives from
        // it already satisfies this. "Narrower cards: if W is under 326, stop and report" — flagged in the
        // CLAUDE.md status entry for this ferry; nothing here can literally halt rendering, so a too-narrow
        // card still lays out (by the same scaling formulas), just unverified below the reference size.
        let innerWidth = EuclideousLaneCardMetrics.innerWidth(cardWidth: width)
        // THREE FIXED ROWS (ferry: step row 44 · tab row 28 · tab content 202, two 6pt gaps between them) —
        // `contentAreaH` is no longer a "whatever's left" budget; it's the literal 202 whenever `height`
        // matches the reference 306 exactly, and scales only if a caller ever hands this a different height.
        let contentAreaH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: height)   // card height − 104 (comet 44 + tabs 28 + 2 × 10 inset + 2 × 6 gap)
        let steps = max(2, min(16, line.steps))
        // LANE SOLO §6.1: a solo-silenced lane's card content draws at 42 % — except the SOLO button and the card's own ground / border — and never stacks with the output-ring TRACE dim below (which already
        // dims the whole card).
        let soloDimContent = soloSilenced(idx) && outputCue(forLane: idx)?.cue != .dim
        VStack(alignment: .leading, spacing: cardRowGap) {
            // LISTEN TAB: a FOLLOW lane PLAYS its partner's pattern, at the partner's rate — so its bar shows THAT (lit cells in the
            // partner's colour, faded; the comet sweeping at the partner's pace) and its bar gestures edit the PARTNER, the thing it
            // is following (2026-10-16). SHADOW keeps its footer-height partner-colour band (see `EuclidLaneBox`).
            let followIdx = euclideousRhythmBorrowPartner(lane: idx, lines: lines)
            let gestureLane = euclideousRhythmGestureTarget(lane: idx, lines: lines)
            let followEff = followIdx != nil ? euclideousEffectivePattern(lane: idx, lines: lines) : nil
            let listenFollowTint: Color? = followIdx.map { laneAccents[$0 % laneAccents.count] }   // the partner's colour: the lit cells + the badge dot
            let listenShadowTint: Color? = (line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo) ? laneAccents[line.listenSourceResolved(ownLane: idx) % laneAccents.count] : nil
            // LANES GRID: the lane's own grid, resolved exactly as the engine resolves it, so the card's comet / flashes follow the rhythm origin and a
            // lane the grid has muted dims. Both stay nil for a lane with no restart marks / no mute, leaving its card byte-identical.
            let gridView = euclideousLaneGridView(lines: lines, lane: idx, legacy: lanesSeq, defaultRateBeats: 0.25, beatsPerBar: clock.beatsPerBar)
            let cardMuteCells = gridView.grid.muteCells, cardMuteUnit = gridView.muteUnitBeats
            // RESTART CHAINS (ferry 2026-10-19): `.off` (both FREE) during the brief pre-first-resync window,
            // the same safe default the Router and the walk mirror fall back to — this lane's OWN chains
            // regardless of FOLLOW (mirrors the old grid's lookup, which also read `line` not the partner).
            let cardChains: EuclideousLaneRestartChains = line.usesRestartChains
                ? EuclideousLaneRestartChains(rhythm: .from(line.restartRhythmBars ?? []), melody: .from(line.restartMelodyPasses ?? []),
                                              barBeats: clock.beatsPerBar, lapBeats: Double(gridView.cycleLen) * gridView.sub)
                : .off
            EuclidLaneBox(idx: idx, line: line, width: innerWidth, height: cometRowH, accent: accent,
                          // WHOLE-CARD OUTLINE (ferry §1.4): `selected` here used to draw EuclidLaneBox's own
                          // border/fill around just this row (the step-bar area) — always `false` now; the
                          // selection indicator moved to a single outline around the ENTIRE card below.
                          selected: false, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: euclideousStripDivisionRate(lane: idx, lines: lines), spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
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
                          // §2.5: PINCH goes through the one STEPS setter too, so HITS/OFFSET memory survives it.
                          onStepsDelta: { d in edit(gestureLane) { l in euclideousSliderCommit(.steps, &l, snapshot: l, newValue: Double(max(2, min(16, l.steps + d)))) } },
                          onAllRotateDelta: { d in euclideousApplyAllRhythmX(d) },
                          onAllHitsDelta: { d in euclideousApplyAllRhythmY(d) },
                          onDragState: { point, allRows in
                              lockCometTouch(idx, lane: gestureLane, down: point != nil, all: allRows)   // LANE LOCK 6.2: a finger on the comet bar writes lock fields too
                              euclideousRhythmDragState(gestureLane, via: idx, point, allRows)
                          },
                          // WHOLE-CARD SELECTION HIGHLIGHT REMOVED (Paul: "remove the highlight that
                          // sometimes appears around the euclid lane boxes") — `onSelect` has no remaining
                          // effect anywhere on this page (confirmed by grep before removing the state it
                          // used to drive), so this is a genuine no-op, not a disabled one.
                          onSelect: { },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          // THE STRIP (LANE STRIP ferry 2026-10-21): a pure plan, not a view — `EuclidCometBar` paints the riff track and the key row from it; `stripCurrent` is asked per display frame which step's
                          // chip is the current one (the arrow's hit).
                          strip: stripPlan, stripCurrent: { beat, _ in stripCurrentStep(idx, plan: stripPlan, beat: beat) },
                          pulseFeed: pulseFeed, pulseLane: idx, pulseScale: euclideousPulseScale(level: pulseLevel), pulseLive: pulseLive,
                          // LANE SOLO (2026-10-21, §1): the step-count box's slot — same 44 × 44 frame, so the strip doesn't move — now holds the SOLO button. `stepCountBadge` (and its parameter) stay, unused here (§1.3): the
                          // step count is still on the RHYTHM tab's STEPS stepper and in the strip's boxes. `soloDim` is "this lane is solo-silenced": its play button and strip dim; the button never does.
                          soloButton: soloButton(idx, accent), soloButtonWidth: stepCountBadgeTotalWidth, soloDim: soloDimContent,
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
                          patternOverride: laneTimingBoxes(idx, line) ?? followEff.map { Array($0.buf.prefix($0.n)) },
                          cellTint: listenFollowTint, cellFade: followIdx != nil ? euclideousListenCellFade : 1,
                          rateBeatsOverride: followEff?.rateBeats,
                          restartChains: cardChains.isActive ? cardChains : nil,
                          mutedAt: cardMuteCells == 0xFFFF ? nil : { b in !euclideousLaneAudible(beat: lanesMusicalBeat(real: b), cells16: cardMuteCells, unitBeats: cardMuteUnit) },
                          lockOutline: lockOn(idx, .cometStrip))
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
                .opacity(soloDimContent ? EuclideousLaneDimStyle.opacity : 1)
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: soloDimContent)
            AnyView(tabContent(idx, line, tab, accent, contentAreaH: contentAreaH, fullWidth: innerWidth))
                .opacity(soloDimContent ? EuclideousLaneDimStyle.opacity : 1)
                .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: soloDimContent)
        }
        .padding(cardInset)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1B1D23)))
        .clipped()
        // FOURFOLD §7.2: while an output ring is HELD, every lane NOT routed to it sits at the existing OFF-dim 42% (no animation
        // — release restores everything at once). Routed lanes get their ring in `laneTabRow` / `laneOutRow` instead.
        .opacity(outputCue(forLane: idx)?.cue == .dim ? 0.42 : 1)
        .overlay(euclideousRandomReturnHighlight(idx, width: width, height: height))
        }
    }

    // MARK: RANDOM MODE — §7.3 the return highlight (visual only: no state, no undo, never blocks a touch)
    /// (LANE LOCK 5.1 / 5.5 rides in this one overlay: the lock ring and the badge, outside the dimming above — the badge never dims — so the card's modifier chain gains nothing.)
    @ViewBuilder private func euclideousRandomReturnHighlight(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            euclideousRandomReturnHighlightBody(idx, width: width, height: height)
            lockCardOverlays(idx, width: width, accent: laneAccents[idx % laneAccents.count])
        }
    }
    @ViewBuilder private func euclideousRandomReturnHighlightBody(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        if let start = euclideousRandomReturnHighlightStart[idx] {
            let accent = laneAccents[idx % laneAccents.count]
            let durationSeconds = clock.playing && clock.tempo > 0 ? (2 * clock.beatsPerBar * 60.0 / clock.tempo) : 4.0
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                let elapsed = tl.date.timeIntervalSinceReferenceDate - start.timeIntervalSinceReferenceDate
                if elapsed < 0 || elapsed > durationSeconds {
                    Color.clear.allowsHitTesting(false)
                        .onAppear { if euclideousRandomReturnHighlightStart[idx] == start { euclideousRandomReturnHighlightStart[idx] = nil } }
                } else {
                    let fadeIn = min(1, elapsed / 0.6)
                    let fadeOut = elapsed > durationSeconds - 0.5 ? max(0, (durationSeconds - elapsed) / 0.5) : 1
                    let ringOpacity = elapsed < 0.6 ? (1 - elapsed / 0.6) : 0   // §7.3: a 600 ms ring fading 100%→0
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2).opacity(ringOpacity)
                        Text("KEPT · UNDO TO GO BACK").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundColor(Color(hex: 0xF2F4F7))
                            .padding(.horizontal, 10).frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.106, green: 0.114, blue: 0.137, opacity: 0.95))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent, lineWidth: 1)))
                            .position(x: width / 2, y: height - 30)
                            .opacity(min(fadeIn, fadeOut))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // THE COUNT BOX (2026-10-13 "lane card, exact dimensions" ferry, literal): "CHIP fill, 9pt radius,
    // number 15pt heavy TEXT, centred." Simplified from the old output-chip/NO-OUT sub-display — that per-
    // lane routing readout is now the RHYTHM tab's own dedicated Emitters row (A·B·C·D, part of this SAME
    // ferry's own RHYTHM table), making the count box's old secondary content redundant; dropped here rather
    // than kept alongside it. `accent`/`mask` params are gone — this box no longer needs either.
    private var stepCountBadgeTotalWidth: CGFloat { 44 }
    // MARK: LANE SOLO (ferry 2026-10-21)
    /// The effective solo mask: latched | held (§4.3).
    private var soloEffective: UInt8 { euclideousSoloEffective(latched: soloMask, held: soloHeld) }
    /// Is lane `lane` solo-silenced — the effective mask isn't 0 and doesn't contain it (§6)? Every dim below asks this (or `euclideousLaneIsDimmed`, which folds in the LANES mute).
    private func soloSilenced(_ lane: Int) -> Bool { euclideousSoloSilences(lane: lane, soloMask: soloEffective) }
    /// The SOLO button of lane `idx` (§2-3), built here as an `AnyView` like every other leaf of the lane card (the page's construction chain has almost no stack to spare in a debug build).
    private func soloButton(_ idx: Int, _ accent: Color) -> AnyView {
        AnyView(EuclideousSoloPressable(lane: idx, accent: accent, latched: (soloMask >> UInt8(idx)) & 1 != 0,
                                        onDown: { onSoloDown(idx) }, onUp: { onSoloUp(idx, $0) }))
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
    /// RESTART CHAINS ferry §1.3 — the RHYTHM tab's upper zone: two equal halves. Left half: two equal
    /// columns (the HITS fader, full height; the STEPS stepper, §2.2). Right half: two equal rows (OFFSET,
    /// TILT), each a full-width horizontal slider with its label row pinned to the top (§2.3/§2.4) — VEL and
    /// GATE are gone from this tab (MIX's riff pad already edits them, §1.2); STEPS is no longer a slider.
    private func rhythmUpperZone(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, rowHeight: CGFloat) -> AnyView {
        // STACK DEPTH (2026-10-21, device crash `MidiSparkAU-2026-10-21-164149.ips`, "Thread stack size exceeded" in this function's right-half closure): in a DEBUG build every view value this
        // eager construction chain holds is a stack temporary — an `EuclideousSlider` is ~4 KB (it carries two `EuclidLine`s) and each opaque `some View` it is wrapped in is another dynamic
        // 4 KB alloca — so a closure holding several sliders at once, on the extension's 1 MB main-thread stack that the page's SwiftUI update chain already nearly fills, overflowed it. Every
        // piece below is therefore built by its own small function that returns an `AnyView` (the technique `laneCard` already uses for `laneTabRow` / `tabContent`): each callee's temporaries die
        // when it returns, and the closures in between only ever hold an 8-byte `AnyView`. Keep it that way (Docs/claude-playbook.md).
        let halfW = max(1, (fullWidth - sp4) / 2)
        return AnyView(HStack(spacing: sp4) {
            rhythmLeftHalf(idx, line, accent, halfW: halfW, rowHeight: rowHeight)
            rhythmRightHalf(idx, line, accent, halfW: halfW, rowHeight: rowHeight)
        }
        .frame(width: fullWidth, height: rowHeight))
    }
    /// LISTEN/FOLLOW (§5 of an earlier ferry, carried over): HITS and TILT show the partner's values at 42% opacity and can't be dragged while following; OFFSET stays live. STEPS (no longer
    /// a slider) isn't part of this set either — the stepper has no FOLLOW treatment of its own today (device-owed, §16, not silently assumed).
    /// RHYTHM POLISH §2.1: the HITS caption's colour — the lane colour 75 % toward #F2F4F7 (`euclideousHitsCaptionRGB`).
    private func hitsCaptionColour(_ idx: Int) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(laneAccents[idx % laneAccents.count]).getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = euclideousHitsCaptionRGB((Double(r), Double(g), Double(b)))
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
    private func rhythmLeftHalf(_ idx: Int, _ line: EuclidLine, _ accent: Color, halfW: CGFloat, rowHeight: CGFloat) -> AnyView {
        let leftColW = max(1, (halfW - sp4) / 2)
        return AnyView(HStack(spacing: sp4) {
            rhythmHitsSlider(idx, line, accent, width: leftColW, height: rowHeight)
            rhythmStepsStepper(idx, line, accent, width: leftColW, height: rowHeight)
        }
        .frame(width: halfW, height: rowHeight))
    }
    /// RESTART CHAINS ferry §1.3: the right half is TWO equal rows (OFFSET, TILT), each a full-width horizontal slider with its label row pinned to the top (§2.3/§2.4).
    /// RHYTHM POLISH ferry (2026-10-22) §1.2: the right half is now THREE equal rows, sp4 apart — OFFSET, TILT and the direction row (the three directions + FLIP HITS) — each `(rowHeight − 8) / 3` tall (38.67 at the reference).
    private func rhythmRightHalf(_ idx: Int, _ line: EuclidLine, _ accent: Color, halfW: CGFloat, rowHeight: CGFloat) -> AnyView {
        let rowH = EuclideousRhythmGeometry.rightRowH(upperH: rowHeight)
        return AnyView(VStack(spacing: sp4) {
            rhythmOffsetRow(idx, line, accent, width: halfW, height: rowH)
            rhythmTiltRow(idx, line, accent, width: halfW, height: rowH)
            directionFlipRow(idx, line, accent, width: halfW, height: rowH)
        }
        .frame(width: halfW, height: rowHeight))
    }
    /// §1.3: four equal buttons, sp4 apart — `<`, `><`, `>` (same styles, setters and selected state as ever) and FLIP HITS (§2.3).
    private func directionFlipRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        let w = EuclideousRhythmGeometry.directionButtonW(rightHalfW: width)
        return AnyView(HStack(spacing: sp4) {
            directionRow(idx, line, accent, rowH: height).frame(width: w * 3 + sp4 * 2)
            flipHitsButton(idx, line, accent, width: w, height: height)
        }
        .frame(width: width, height: height))
    }
    // LISTEN REBUILT (2026-10-23): HITS/TILT no longer show a partner's value at reduced opacity while
    // individually "following" — §7's "a tab is either fully the lane's own or fully paused" replaces that
    // old per-slider dim with the RHYTHM tab's own full-tab pause overlay (`listenPausedOverlay`), which
    // covers every control at once, including this one, whenever RHYTHM is COPY/FILL.
    private func rhythmHitsSlider(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        AnyView(EuclideousSlider(
            field: .hits, line: line, accent: accent, width: width, height: height, horizontal: false,
            onCommit: { mutate in edit(idx, mutate) },
            onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(.hits, &$0) } },
            onRevertToEuclid: { edit(idx) { $0.customHits = nil } },
            lockActive: lockLocked(idx), lockOutline: lockOn(idx, .hits) ? accent : nil, onLockTouch: lockTouch(idx),
            heroCaption: hitsCaptionColour(idx)))
    }
    private func rhythmStepsStepper(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        AnyView(EuclideousStepsStepper(
            line: line, accent: accent, width: width, height: height,
            onCommit: { newStep, mutate in editStep(idx, newStep, mutate) },
            onToggleValueBoxTap: {
                if stepsPickerLane == idx { stepsPickerLane = nil }
                else { stepsPickerLane = idx; restartEditorLane = nil }
            },
            lockActive: lockLocked(idx), lockMomentary: lockMomentary(idx), lockOutline: lockOn(idx, .steps) ? accent : nil, onLockTouch: lockTouch(idx)))
    }
    private func rhythmOffsetRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        AnyView(EuclideousSlider(
            field: .offset, line: line, accent: accent, width: width, height: height, horizontal: true,
            touchPad: 2,
            onCommit: { mutate in edit(idx, mutate) },
            onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(.offset, &$0) } },
            onRevertToEuclid: { edit(idx) { $0.customHits = nil } },
            topAlignLabelRow: true,
            lockActive: lockLocked(idx), lockOutline: lockOn(idx, .offset) ? accent : nil, onLockTouch: lockTouch(idx)))
    }
    private func rhythmTiltRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        AnyView(EuclideousSlider(
            field: .tilt, line: line, accent: accent, width: width, height: height, horizontal: true,
            touchPad: 2,
            onCommit: { mutate in edit(idx, mutate) },
            onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(.tilt, &$0) } },
            onRevertToEuclid: { edit(idx) { $0.customHits = nil } },
            topAlignLabelRow: true,
            // Floors ferry (2026-10-23): pure annotation, not the control — drops first as the row shrinks.
            endLabels: EuclideousRhythmGeometry.showsEndLabels(rowH: height) ? ("EARLY", "LATE") : nil,
            lockActive: lockLocked(idx), lockOutline: lockOn(idx, .tilt) ? accent : nil, onLockTouch: lockTouch(idx)))
    }

    // MARK: LANE LOCK — the normal card's side (§5, §6)
    private func lockOf(_ idx: Int) -> EuclideousLaneLock { idx < locks.count ? locks[idx] : EuclideousLaneLock() }
    private func lockLocked(_ idx: Int) -> Bool { lockOf(idx).isLocked }
    /// 6.9: a lane locked on the BEAT grid — its tap-controls act on touch-down. Everything else (an unlocked lane, a bar grid) behaves exactly as before.
    private func lockMomentary(_ idx: Int) -> Bool { let l = lockOf(idx); return l.isLocked && l.gridResolved == .beat }
    /// 5.4: the controls of lane `idx` whose value differs from its locked state — empty unless the lane is locked and has moved. One list (`euclideousLockChangedControls`), asked per control.
    private func lockDiff(_ idx: Int) -> Set<EuclideousLockControl> {
        let l = lockOf(idx)
        guard l.isLocked, let st = l.state, idx < lines.count else { return [] }
        return euclideousLockChangedControls(from: st, to: lines[idx])
    }
    private func lockOn(_ idx: Int, _ c: EuclideousLockControl) -> Bool { lockLocked(idx) && lockDiff(idx).contains(c) }
    private func lockTouch(_ idx: Int) -> (Bool) -> Void { { down in onLockHeld(idx, down) } }
    /// 5.6: a control with an outline adds ", will snap back" to its spoken value.
    private func lockSpoken(_ idx: Int, _ c: EuclideousLockControl, _ value: String) -> String { euclideousLockAppendSnapWords(value, outlined: lockOn(idx, c)) }
    @State private var lockCometHeld: [[Int]] = [[], [], [], []]
    @State private var lockOverlayHeld: [Bool] = [false, false, false, false]
    /// A finger on lane `card`'s comet bar edits `lane`'s pattern (every lane for a two-finger gesture): the locked lanes among them count as held until it lifts — exactly the lanes counted at touch-down / when the gesture widened.
    private func lockCometTouch(_ card: Int, lane: Int, down: Bool, all: Bool) {
        guard card >= 0, card < lockCometHeld.count else { return }
        if down {
            for t in (all ? [0, 1, 2, 3] : [lane]) where lockLocked(t) && !lockCometHeld[card].contains(t) { lockCometHeld[card].append(t); onLockHeld(t, true) }
        } else if !lockCometHeld[card].isEmpty {
            let held = lockCometHeld[card]; lockCometHeld[card] = []
            for t in held { onLockHeld(t, false) }
        }
    }
    /// 6.2: "its STEPS picker or restart editor is open" (and the NOTES picker, which writes a lock field too) counts as a finger on the lane: opening is touch-down, closing is lift.
    private var lockOverlayMask: Int {
        (0..<4).reduce(0) { m, i in m | (((stepsPickerLane == i || restartEditorLane == i || notesPickerOpen.contains(i)) ? 1 : 0) << i) }
    }
    private func laneTapMod(_ idx: Int, _ action: @escaping () -> Void) -> EuclideousLaneTap {
        EuclideousLaneTap(locked: lockLocked(idx), momentary: lockMomentary(idx), onTouch: lockTouch(idx), action: action)
    }
    private func lockOutlineMod(_ idx: Int, _ c: EuclideousLockControl, _ accent: Color) -> EuclideousLockOutline {
        EuclideousLockOutline(on: lockOn(idx, c), accent: accent)
    }
    private func lockTabDiffers(_ idx: Int, _ t: EuclideousLaneTab) -> Bool {
        guard lockLocked(idx) else { return false }
        let tab: EuclideousLockTab
        switch t { case .rhythm: tab = .rhythm; case .riff: tab = .riff; case .notes: tab = .notes; case .listen: return false }
        return euclideousLockChangedTabs(lockDiff(idx)).contains(tab)
    }
    /// The ring (5.5: once per snap / capture) and the badge (5.1) as ONE value in the card's modifier chain.
    private func lockCardOverlays(_ idx: Int, width: CGFloat, accent: Color) -> AnyView {
        AnyView(ZStack(alignment: .topLeading) {
            EuclideousLockRing(start: idx < lockRingStart.count ? lockRingStart[idx] : nil, accent: accent, radius: 12, reduceMotion: reduceMotion)
            lockBadge(idx, width: width)
        })
    }
    private func tabDecor(_ idx: Int, _ t: EuclideousLaneTab, sel: Bool, _ accent: Color) -> AnyView {
        AnyView(ZStack {
            Rectangle().fill(sel ? lane100(accent) : patternUnselectedFill).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
            lockTabDot(idx, t, lane100(accent)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        })
    }
    /// 5.4: the dot on a tab with a control that differs from L (6pt, 6pt from its trailing edge, 5pt from its top).
    private func lockTabDot(_ idx: Int, _ t: EuclideousLaneTab, _ accent: Color) -> AnyView {
        guard lockTabDiffers(idx, t) else { return AnyView(EmptyView()) }
        return AnyView(Circle().fill(accent).frame(width: 6, height: 6).padding(.top, 5).padding(.trailing, 6).allowsHitTesting(false))
    }
    /// 5.1 / 5.2: the badge, drawn over the card (never dimmed) at the tab row's trailing end; none for an unlocked lane.
    private func lockBadge(_ idx: Int, width: CGFloat) -> AnyView {
        guard lockLocked(idx), let st = lockOf(idx).state, idx < lines.count else { return AnyView(EmptyView()) }
        let accent = laneAccents[idx % laneAccents.count]
        let touch = EuclideousLockBadge.touchFrame(cardWidth: width)
        return AnyView(EuclideousLockBadgeView(lane: idx, accent: accent, deviated: euclideousLockDeviated(line: lines[idx], from: st), grid: lockOf(idx).gridResolved,
                                               held: idx < lockHeld.count && lockHeld[idx], running: clock.playing, tempo: clock.tempo, barBeats: clock.beatsPerBar,
                                               beatAt: { walkTagBeat(at: $0) },
                                               onTap: { onLockCommand(idx, .unlock) }, onHold: { onLockCommand(idx, .capture) })
            .offset(x: touch.minX, y: touch.minY))
    }

    // MARK: LANE LOCK — the lane card in lock mode (§4)
    private func euclideousLockLaneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> AnyView {
        let accent = laneAccents[idx % laneAccents.count]
        let lock = idx < locks.count ? locks[idx] : EuclideousLaneLock()
        let autoRate = ArpRate.allCases.min(by: { abs($0.beats - clock.stepBeats) < abs($1.beats - clock.stepBeats) }) ?? .r1_16
        return AnyView(EuclideousLockCardView(lane: idx, size: CGSize(width: width, height: height), accent: accent,
                                              line: idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all), lock: lock, autoRate: autoRate,
                                              held: idx < lockHeld.count && lockHeld[idx], running: clock.playing, tempo: clock.tempo, barBeats: clock.beatsPerBar,
                                              beatAt: { walkTagBeat(at: $0) }, ringStart: idx < lockRingStart.count ? lockRingStart[idx] : nil, reduceMotion: reduceMotion,
                                              onTap: { onLockCommand(idx, lock.isLocked ? .unlock : .lock) },
                                              onHold: { onLockCommand(idx, .capture) },
                                              onGrid: { onLockCommand(idx, .setGrid($0)) }))
    }

    // MARK: RANDOM MODE — the lane card's picture mode (§3)
    @ViewBuilder private func euclideousRandomLaneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        let accent = laneAccents[idx % laneAccents.count]
        // §3.3: a card whose normal tab is LISTEN shows RHYTHM in random mode.
        let tab = euclideousRandomTab[idx]
        let state = euclideousRandomRolls[idx][tab.rawValue]
        let line = euclideousRandomEffectiveLine(lane: idx)
        let displayLine = euclideousRandomHeldLane == idx ? (state.original ?? line) : line
        let slot = euclideousRandomPendingSlot(lane: idx, tab: tab)
        EuclideousRandomCardView(lane: idx, width: width, height: height, accent: accent, line: displayLine,
                                  riffRanks: effectiveGridRanks, tab: tab, state: state, holding: euclideousRandomHeldLane == idx,
                                  onSelectTab: { t in
                                      if euclideousRandomHeldLane == idx { euclideousRandomHoldEnded(lane: idx) }   // release the OLD tab's render-thread override before switching
                                      euclideousRandomTab[idx] = t
                                  },
                                  onThrow: { euclideousRandomThrow(lane: idx) },
                                  onTweak: { euclideousRandomTweak(lane: idx) },
                                  onBack: { euclideousRandomBack(lane: idx) },
                                  onKeep: { euclideousRandomKeep(lane: idx) },
                                  onHoldBegan: { euclideousRandomHoldBegan(lane: idx) },
                                  onHoldEnded: { euclideousRandomHoldEnded(lane: idx) },
                                  clockPlaying: clock.playing, clockAnchor: clock.anchor, clockAnchorAt: clock.anchorAt,
                                  clockTempo: clock.tempo, clockBeatsPerBar: clock.beatsPerBar,
                                  landingBeat: slot < pendingRolls.count ? pendingRolls[slot]?.landingBeat : nil,
                                  laneLocked: lockLocked(idx),
                                  // Lane-box buttons ferry: the SAME callback/view the normal-mode card uses —
                                  // not a second derivation of play/SOLO.
                                  onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                                  soloButtonView: soloButton(idx, accent))
    }

    // MARK: - Per-lane tab row + content (Paul 2026-10-07, §2.6)

    /// CLARITY PASS §2: one tab's label (11 pt heavy, tracking 1) with its glyph after it (sp5), or — on RHYTHM — a space and "hits/steps" in lane100 (same face and size, no tracking). A single `Text` with
    /// tail truncation, so a narrow tab loses the count before the label ("truncate, never shrink"). An OFF glyph tab (RIFF / NOTES / LISTEN) dims its label and glyph to 40 %, selected or not.
    private func laneTabLabel(_ idx: Int, _ line: EuclidLine, _ t: EuclideousLaneTab, sel: Bool, accent: Color) -> AnyView {
        let glyph = euclideousTabGlyph(tab: EuclideousTabKind(rawValue: t.rawValue) ?? .rhythm, line: line, lane: idx)
        let face = Font.system(size: 11, weight: .heavy, design: .monospaced)
        let name = Text(t.label).font(face).tracking(1).foregroundColor(sel ? patternSelectedText : patternUnselectedText)
        // §7.1: RHYTHM always shows a count (its own hits/steps, or "← n" while borrowed); RIFF/NOTES show
        // nothing UNLESS paused, in which case they show the same "← n" link.
        let tabKind = EuclideousTabKind(rawValue: t.rawValue) ?? .rhythm
        let borrowedMark = tabKind == .rhythm
            ? euclideousRhythmBorrowPartner(lane: idx, lines: lines) != nil
            : euclideousPausedTabHeaderText(tab: tabKind, lane: idx, lines: lines) != nil
        let suffix: String? = t == .rhythm ? euclideousRhythmTabCount(lane: idx, lines: lines)
            : euclideousPausedTabHeaderText(tab: tabKind, lane: idx, lines: lines)
        // §7.1: "← n" is drawn "in the SOURCE's lane100 at full strength" — only the ordinary hits/steps
        // count (not borrowed) uses the card's own lane colour.
        let suffixColor = borrowedMark ? lane100(laneAccents[line.listenSourceResolved(ownLane: idx) % laneAccents.count]) : lane100(accent)
        let title: Text = suffix.map { name + Text(" " + $0).font(face).tracking(0).foregroundColor(suffixColor) } ?? name
        // A tab too narrow for "RHYTHM 5/16" (the iPad mini; a locked lane's badge) used to cut the NUMBER ("5/…"). The count is what the tab is for, so the word gives way first: "RHY 5/16". (Nothing shrinks.)
        let shortTitle: Text? = (t == .rhythm && suffix != nil)
            ? Text("RHY").font(face).tracking(1).foregroundColor(sel ? patternSelectedText : patternUnselectedText) + Text(" " + suffix!).font(face).tracking(0).foregroundColor(suffixColor) : nil
        let fill: Color = {
            switch glyph.fill {
            case .lane(let l): return lane100(laneAccents[max(0, l) % laneAccents.count])
            }
        }()
        return AnyView(
            HStack(spacing: 5) {
                if let shortTitle, #available(iOS 16.0, *) {
                    ViewThatFits(in: .horizontal) {
                        title.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        shortTitle.lineLimit(1).truncationMode(.tail)
                    }
                } else {   // (`ViewThatFits` is iOS 16: on iOS 15 a tab too narrow for "RHYTHM 5/16" cuts the count again, as it did before the mini fix)
                    title.lineLimit(1).truncationMode(.tail)
                }
                if glyph.shape != .none { EuclideousTabGlyphView(shape: glyph.shape, on: glyph.on, fill: fill) }
            }
            .opacity(glyph.shape != .none && !glyph.on ? 0.4 : 1)
        )
    }

    private func laneTabRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(EuclideousLaneTab.allCases, id: \.rawValue) { t in
                let sel = (idx < laneTab.count ? laneTab[idx] : .rhythm) == t
                // CLARITY PASS (2026-10-23) §2: RIFF/NOTES/LISTEN each carry a GLYPH (a square / an upright bar / a circle) where the round status dot used to sit — filled in a lane's colour while that tab's thing is ON
                // (exactly what filled the dot: `euclideousTabGlyph`), a 1.5 pt outline and the label + glyph at 40 % while off; RHYTHM shows its "hits/steps" in lane100 instead. The underline and the LOCK dot
                // are the overlay below, outside the dimmed content. (The label is its own AnyView-returning leaf, like the rest of this row — the 1 MB stack rule.)
                laneTabLabel(idx, line, t, sel: sel, accent: accent)
                .frame(maxWidth: .infinity, alignment: .center).frame(height: rowH)
                // LANE LOCK 5.4: the underline and — on a tab with a control that differs from L — a 6pt lane100 dot (6pt from its trailing edge, 5pt from its top), in ONE overlay
                .overlay(tabDecor(idx, t, sel: sel, accent))
                // RESTART CHAINS ferry §10.4: the RHYTHM tab chip no longer rings — lane cards have no OUT
                // circles any more, so the pulse/trace now points at MIX (its OUT buttons, or the MIX tab
                // chip), never at this per-lane tab row.
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(euclideousTabAccessibilityLabel(tab: EuclideousTabKind(rawValue: t.rawValue) ?? .rhythm, lines: lines, lane: idx))   // §4.1: "Rhythm, 5 of 16 hits" · "Riff, on" · "Listen, on, following lane 2"
                .onTapGesture {
                    if idx < laneTab.count { laneTab[idx] = t }
                    // §1.6: the STEPS picker and the restart editor both close when the card switches tab.
                    if stepsPickerLane == idx { stepsPickerLane = nil }
                    if restartEditorLane == idx { restartEditorLane = nil }
                }
            }
            // LANE LOCK 5.1: a locked lane's badge sits at the trailing end (drawn over the card); the tabs share what is left by the same rule (equal width, spacing 4)
            if lockLocked(idx) { Color.clear.frame(width: EuclideousLockBadge.size, height: 1) }
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
            // RESTART CHAINS ferry §1.1/§1.3: the control block stays 80pt (two 38pt rows + 4pt gap); the
            // upper zone gets whatever's left (124pt at the reference contentAreaH=202).
            let patternBlockH: CGFloat = 80
            let upperH = max(1, contentAreaH - patternBlockH - sp4)
            let pickerEditorH = upperH + sp4 + patternBlockH
            // LISTEN REBUILT (2026-10-23): RHYTHM pauses whole under COPY/FILL (§7) — the same dim + paused-
            // card overlay RIFF/NOTES use under SHADOW/ECHO.
            let borrowed = euclideousRhythmBorrowPartner(lane: idx, lines: lines) != nil
            ZStack {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: sp4) {
                        rhythmUpperZone(idx, line, accent, fullWidth: fullWidth, rowHeight: upperH)
                        patternControlBlock(idx, line, accent, fullWidth: fullWidth)
                    }
                    // §1.5/§1.7: the picker and the restart editor cover both zones, full content width, from
                    // the top of the upper zone — only one of the two open at a time (§1.6). The STEPS picker
                    // keeps its own 192pt floor (unchanged, not in this ferry's scope); the restart editor now
                    // builds at ANY height and degrades itself (RHYTHM fixes §5.1 — see its own doc comment).
                    if stepsPickerLane == idx {
                        if pickerEditorH >= 192 {
                            stepsPicker(idx, line, accent, width: fullWidth, height: pickerEditorH)
                        }
                    } else if restartEditorLane == idx {
                        let geo = euclideousLaneStepGeometry(lines: lines, lane: idx, defaultRateBeats: 0.25)
                        let lapBeats = Double(geo.cycleLen) * geo.sub
                        restartEditor(idx, line, accent, width: fullWidth, height: pickerEditorH, lapBeats: lapBeats)
                    }
                }
                .opacity(borrowed ? EuclideousListenPauseMetrics.dimOpacity : 1)
                .allowsHitTesting(!borrowed)
                .accessibilityHidden(borrowed)   // §10: VoiceOver skips the paused, non-interactive content entirely
                if borrowed { listenPausedOverlay(idx, line, label: "RHYTHM", width: fullWidth, height: contentAreaH) { $0.listenRhythm = .own } }
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
        return HStack(spacing: sp4) {   // RHYTHM POLISH §1.3: the four buttons across the row (these three + FLIP HITS) are sp4 apart (was 3 pt between the three)
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .modifier(laneTapMod(idx) { edit(idx) { $0.direction = dir } })
                    .accessibilityValue(lockSpoken(idx, .direction, ""))
            }
        }
        .modifier(lockOutlineMod(idx, .direction, accent))
    }

    /// RHYTHM POLISH ferry (2026-10-22) §2.3: INV is now FLIP HITS — "FLIP" over "HITS" on two lines (8 pt heavy, 0.08 em tracking, 1 pt apart, centred). The setter, undo and selected state are unchanged; VoiceOver says
    /// "Flip hits" and it carries the page's toggle trait (INV carried none). The old `invButton` below is kept, unused.
    private func flipHitsButton(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> AnyView {
        let on = line.patternMissResolved
        return AnyView(VStack(spacing: 1) {
            Text(EuclideousFlipHits.lines[0]).tracking(0.64); Text(EuclideousFlipHits.lines[1]).tracking(0.64)   // per Text: `View.tracking` on the stack is iOS 16, `Text.tracking` is iOS 13
        }
        .font(.system(size: 8, weight: .heavy, design: .monospaced))
        .foregroundColor(on ? patternSelectedText : patternUnselectedText)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .modifier(laneTapMod(idx) { edit(idx) { $0.patternMiss = !on } })
        .modifier(lockOutlineMod(idx, .inv, accent))
        .euclideousHelp("Play on the empty steps instead of the hits")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EuclideousFlipHits.accessibilityLabel)
        .accessibilityValue(lockSpoken(idx, .inv, on ? "on" : "off"))
        .ringToggleTrait())
    }

    // MARK: - RESTART CHAINS (ferry 2026-10-19) — §6 tiles + editor, §3 STEPS picker

    /// §6.1 — the two restart tiles (RHYTHM, MELODY), replacing the OUT A–D circles in the RHYTHM tab's lower-right row (§9 moves OUT to MIX). Each opens the shared restart editor (§6.2, holds both chains).
    /// RHYTHM POLISH ferry (2026-10-22) §1.4 / §6: one tile per row (the rate grid's two rows), each a sweep + progress track drawn from the pure `restartTileState` at the UI beat of ONE `TimelineView` for the pair (the
    /// restart flash's timer, reused — the comet strip's own is private to `EuclidCometBar`; same 60 fps, same `anchor + elapsed × tempo` beat). Only a RUNNING lane sweeps, lights cells or strikes; stopped, the tracks keep
    /// their structure at the transport's beat. RESTART TILES ferry (2026-10-22): the MELODY track is one cell per riff note and each hit that plays a note strikes its cell (`euclideousRestartCellStrikes`, from the pulse feed).
    /// The flash (`restartFlash`, `euclideousRestartFlashLook`, `RestartFlashPainter`) is no longer called from here — its code is kept.
    private func restartTilesRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat, fullWidth: CGFloat) -> some View {
        let rhythm = EuclideousRestartChain.from(line.restartRhythmBars ?? [])
        let melody = EuclideousRestartChain.from(line.restartMelodyPasses ?? [])
        let running = euclideousLaneIsRunning(transportPlaying: clock.playing, line: line)
        let cfg = riffWalkConfig(idx)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running || cfg == nil)) { tl in
            let beat = lanesMusicalBeat(real: walkTagBeat(at: tl.date))   // the engine's musical beat (identity at 50 % swing): the restarts are on its bar lines
            let melodyState = cfg.map { restartTileState(.melody, cfg: $0, beat: beat, running: running) }
            let bank: EuclideousCellStrikeBank? = (running && melodyState != nil)
                ? euclideousRestartCellStrikes(pulseFeed.strikes(lane: idx), columnCells: melodyState!.columnCells, now: tl.date.timeIntervalSinceReferenceDate) : nil
            VStack(spacing: sp4) {
                restartTile(idx, chain: rhythm, name: "RHYTHM", unitSingular: "BAR", unitPlural: "bars", accent: accent, width: fullWidth, height: rowH,
                            state: cfg.map { restartTileState(.rhythm, cfg: $0, beat: beat, running: running) }, strikes: nil)
                restartTile(idx, chain: melody, name: "MELODY", unitSingular: "PASS", unitPlural: "passes", accent: accent, width: fullWidth, height: rowH,
                            state: melodyState, strikes: bank)
            }
        }
        .frame(width: fullWidth, height: rowH * 2 + sp4)
    }
    /// One restart tile (§6.1/§6.2). A set chain: #22252C fill and a 1 pt lane100 inner border; FREE: #2A2D34, no border. ONE text line, its top 6 pt in, 10 pt either side, baseline-aligned: ↻ (8 pt) and "RHYTHM RESTART" /
    /// "MELODY RESTART" (8 pt heavy, 0.1 em, #8A909A, truncating first) on the left; the chain (13 pt heavy, #F2F4F7 — FREE #AAB0BA) and its BAR / PASS unit on the right. RESTART TILES §2: the layers are walked in
    /// `euclideousRestartTileLayerOrder` — base (fill + border), sweep, track, text — so the sweep never draws over the text.
    /// Built as an `AnyView` (the page's construction chain has almost no stack to spare in a debug build — see Docs/claude-playbook.md).
    private func restartTile(_ idx: Int, chain: EuclideousRestartChain, name: String, unitSingular: String, unitPlural: String, accent: Color, width: CGFloat, height: CGFloat,
                             state: EuclideousRestartTileState?, strikes: EuclideousCellStrikeBank?) -> AnyView {
        let control: EuclideousLockControl = name == "MELODY" ? .melodyRestart : .rhythmRestart
        return AnyView(ZStack(alignment: .topLeading) {
            ForEach(Array(euclideousRestartTileLayerOrder.enumerated()), id: \.offset) { _, layer in
                restartTileLayer(layer, chain: chain, name: name, unitSingular: unitSingular, accent: accent, width: width, height: height, state: state, strikes: strikes)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            restartEditorLane = idx
            stepsPickerLane = nil   // §1.6: only one of the picker/editor open at a time
        }
        .modifier(lockOutlineMod(idx, control, accent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousRestartTileAccessibleLabel(name: name, chain: chain, unitSingular: unitSingular.lowercased(), unitPlural: unitPlural))
        .accessibilityValue(lockSpoken(idx, control, state?.restartsInText ?? ""))
        .accessibilityHint("Double-tap to edit"))
    }
    private func restartTileLayer(_ layer: EuclideousRestartTileLayer, chain: EuclideousRestartChain, name: String, unitSingular: String, accent: Color, width: CGFloat, height: CGFloat,
                                  radius: CGFloat = 8, trackCentred: Bool = false, state: EuclideousRestartTileState?, strikes: EuclideousCellStrikeBank?) -> AnyView {
        switch layer {
        case .base:
            return AnyView(RoundedRectangle(cornerRadius: radius).fill(chain.isFree ? Color(hex: 0x2A2D34) : Color(hex: 0x22252C))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(chain.isFree ? Color.clear : lane100(accent), lineWidth: 1))
                .frame(width: width, height: height))
        case .sweep:
            guard let state else { return AnyView(EmptyView()) }
            return AnyView(EuclideousRestartTileCanvas(part: .sweep, state: state, accent: accent, width: width, height: height, radius: radius))
        case .track:
            guard let state else { return AnyView(EmptyView()) }
            return AnyView(EuclideousRestartTileCanvas(part: .track, state: state, accent: accent, width: width, height: height, radius: radius, trackCentred: trackCentred, strikes: strikes,
                                                       pulseScale: euclideousPulseScale(level: pulseLevel), reduceMotion: reduceMotion))
        case .text:
            let text = euclideousRestartChainText(chain)
            let showUnit = !chain.isFree && chain.count <= 3
            return AnyView(HStack(alignment: .lastTextBaseline, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .heavy)).foregroundColor(Color(hex: 0x8A909A))
                    Text("\(name) RESTART").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.8)
                        .foregroundColor(Color(hex: 0x8A909A)).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(text).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(chain.isFree ? Color(hex: 0xAAB0BA) : Color(hex: 0xF2F4F7)).lineLimit(1)
                    if showUnit {
                        Text(unitSingular.lowercased() == "bar" ? "BAR" : "PASS")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.64)
                            .foregroundColor(Color(hex: 0x8A909A))
                    }
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, 10).padding(.top, 6)
            .frame(width: width, height: height, alignment: .topLeading))
        }
    }

    /// §6.2 — the restart editor: both chains, each a FREE + 4-link row. RESTART TILES ferry (2026-10-22) §3: under each chain row, in place of the timeline, its axis label and the hint line (all gone), the TILE's own
    /// live graphic — its sweep and its track (and, for MELODY, its strikes) from the same `restartTileState` — without the tile's text. The vertical layout comes from `euclideousRestartEditorLayout`
    /// (the gaps are built from it, not left to flexible spacers), so the view and the tests read the same numbers.
    private func restartEditor(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat, lapBeats: Double) -> some View {
        typealias M = EuclideousRestartEditorMetrics
        let rhythmChain = EuclideousRestartChain.from(line.restartRhythmBars ?? [])
        let melodyChain = EuclideousRestartChain.from(line.restartMelodyPasses ?? [])
        let contentW = max(1, width - sp8 * 2)
        let layout = euclideousRestartEditorLayout(width: width, height: height)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                (Text("RESTARTS").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.48).foregroundColor(Color(hex: 0xAAB0BA))
                 + Text(" · TAP + TO ADD · TAP A LINK TO CHANGE IT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Button(action: { restartEditorLane = nil }) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color(hex: 0xAAB0BA))
                        .frame(width: 28, height: 20)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                        // RHYTHM fixes §5.3 (2026-10-21): the drawn size stays 28×20; the hit area extends 2pt
                        // up/down ONLY (28×24, not 32×24 — `.inset(by:)` would widen it too), matching the
                        // picker's own close button below.
                        .contentShape(Rectangle().path(in: CGRect(x: 0, y: -2, width: 28, height: 24)))
                }
                .accessibilityLabel("Close restarts")   // RHYTHM fixes §6.1 (2026-10-21): the spec's exact wording
            }
            .frame(height: M.headerH)
            .padding(.leading, 4)
            Color.clear.frame(height: layout.gaps[0])
            restartChainSection(idx, line, name: "RHYTHM", unitWord: "bar", chain: rhythmChain, accent: accent, isMelody: false, width: contentW)
            Color.clear.frame(height: layout.gaps[1])
            restartChainSection(idx, line, name: "MELODY", unitWord: "pass", chain: melodyChain, accent: accent, isMelody: true, width: contentW)
            Spacer(minLength: 0)
        }
        .padding(sp8)
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Restarts for lane \(idx + 1)")
    }
    private func euclideousRestartEditorSetChain(_ idx: Int, melody: Bool, links: [UInt8]) {
        edit(idx) { l in if melody { l.restartMelodyPasses = links } else { l.restartRhythmBars = links } }
    }
    private func restartChainSection(_ idx: Int, _ line: EuclidLine, name: String, unitWord: String, chain: EuclideousRestartChain, accent: Color, isMelody: Bool, width: CGFloat) -> some View {
        typealias M = EuclideousRestartEditorMetrics
        let btnGap: CGFloat = sp4
        let btnsW = max(1, width - M.labelW - btnGap)
        let btnW = max(1, (btnsW - btnGap * 4) / 5)
        let isFree = chain.isFree
        return VStack(alignment: .leading, spacing: M.gap) {
            ForEach(Array(euclideousRestartEditorSectionParts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .chainRow:
                    HStack(spacing: btnGap) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.9).foregroundColor(Color(hex: 0xF2F4F7))
                            Text("IN \(unitWord.uppercased())\(unitWord == "pass" ? "ES" : "S")").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.64).foregroundColor(Color(hex: 0x8A909A))
                        }
                        .padding(.leading, 4)
                        .frame(width: M.labelW, height: M.rowH, alignment: .leading)
                        Text("FREE").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
                            .foregroundColor(isFree ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
                            .frame(width: btnW, height: M.rowH)
                            .background(RoundedRectangle(cornerRadius: 6).fill(isFree ? lane20(accent) : Color(hex: 0x2A2D34)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isFree ? lane100(accent) : Color.clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { if !isFree { euclideousRestartEditorSetChain(idx, melody: isMelody, links: []) } }
                            .accessibilityLabel("\(name.capitalized) restarts free")
                        ForEach(0..<4, id: \.self) { slot in
                            restartLinkSlot(idx, isMelody: isMelody, chain: chain, slot: slot, unitWord: unitWord, accent: accent, width: btnW, height: M.rowH)
                        }
                    }
                case .strip:
                    HStack(spacing: M.gap) {
                        Color.clear.frame(width: M.labelW, height: M.stripH)   // the label column beside the strip stays empty
                        restartEditorStrip(idx, line, name: name, unitWord: unitWord, chain: chain, accent: accent, isMelody: isMelody, width: max(1, width - M.labelW - M.gap))
                    }
                }
            }
        }
    }
    /// RESTART TILES §3.2 — the section's live strip: the tile's base and border (radius 6), sweep, track (centred) and strikes, from the same pure `restartTileState` and the same strike bank as the tile, no text. It is built
    /// from the CURRENT lines on every body evaluation, so a tap on a link, + or FREE redraws both the sweep and the track for the new chain in the same update. One static VoiceOver element (§3.5).
    private func restartEditorStrip(_ idx: Int, _ line: EuclidLine, name: String, unitWord: String, chain: EuclideousRestartChain, accent: Color, isMelody: Bool, width: CGFloat) -> some View {
        typealias M = EuclideousRestartEditorMetrics
        let kind: EuclideousRestartKind = isMelody ? .melody : .rhythm
        let running = euclideousLaneIsRunning(transportPlaying: clock.playing, line: line)
        let cfg = riffWalkConfig(idx)
        let label = euclideousRestartTileAccessibleLabel(name: name, chain: chain, unitSingular: unitWord, unitPlural: unitWord == "pass" ? "passes" : "bars")
        let beatNow = lanesMusicalBeat(real: walkTagBeat(at: Date()))
        let spoken = cfg.map { restartTileState(kind, cfg: $0, beat: beatNow, running: running) }
        let value = [spoken?.restartsInText ?? "", isMelody ? (spoken?.notesThisCycleText ?? "") : ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running || cfg == nil)) { tl in
            let beat = lanesMusicalBeat(real: walkTagBeat(at: tl.date))
            let state = cfg.map { restartTileState(kind, cfg: $0, beat: beat, running: running) }
            let bank: EuclideousCellStrikeBank? = (isMelody && running && state != nil)
                ? euclideousRestartCellStrikes(pulseFeed.strikes(lane: idx), columnCells: state!.columnCells, now: tl.date.timeIntervalSinceReferenceDate) : nil
            ZStack(alignment: .topLeading) {
                ForEach(Array(euclideousRestartTileLayerOrder.filter { $0 != .text }.enumerated()), id: \.offset) { _, layer in
                    restartTileLayer(layer, chain: chain, name: name, unitSingular: unitWord, accent: accent, width: width, height: M.stripH, radius: M.stripRadius, trackCentred: true, state: state, strikes: bank)
                }
            }
        }
        .frame(width: width, height: M.stripH)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
    private func restartLinkSlot(_ idx: Int, isMelody: Bool, chain: EuclideousRestartChain, slot: Int, unitWord: String, accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let count = chain.count
        return Group {
            if slot < count {
                let v = Int(chain.link(slot))
                Text("\(v)").font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xF2F4F7))
                    .frame(width: width, height: height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(lane20(accent)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lane100(accent), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let ladder = [1, 2, 3, 4, 6, 8]
                        var links = chain.links
                        if let i = ladder.firstIndex(of: v), i + 1 < ladder.count {
                            links[slot] = UInt8(ladder[i + 1])
                        } else {
                            links.remove(at: slot)
                        }
                        euclideousRestartEditorSetChain(idx, melody: isMelody, links: links)
                    }
                    .accessibilityLabel("\(isMelody ? "Melody" : "Rhythm") link \(slot + 1), \(v) \(unitWord)\(v == 1 ? "" : (unitWord == "pass" ? "es" : "s"))")
                    .accessibilityHint("Double-tap for the next length")
            } else if slot == count {
                Text("+").font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xAAB0BA))
                    .frame(width: width, height: height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var links = chain.links
                        links.append(1)
                        euclideousRestartEditorSetChain(idx, melody: isMelody, links: links)
                    }
                    .accessibilityLabel("Add a \(isMelody ? "melody" : "rhythm") link")
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34))
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)
            }
        }
    }

    /// §3 — the STEPS picker: 15 cells (lengths 2–16), each previewing this lane's rhythm.
    private func stepsPicker(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let contentW = max(1, width - sp8 * 2)
        let contentH = max(1, height - sp8 * 2)
        let headerH: CGFloat = 20
        let gridH = max(1, contentH - headerH - sp4)
        let cellGap: CGFloat = sp4
        let cellW = max(1, (contentW - cellGap * 4) / 5)
        let cellH = max(1, (gridH - cellGap * 2) / 3)
        let lengths = Array(2...16)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                (Text("STEPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.9).foregroundColor(Color(hex: 0xAAB0BA))
                 + Text(" · TAP A LENGTH").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: { stepsPickerLane = nil }) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color(hex: 0xAAB0BA))
                        .frame(width: 28, height: 20)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)))
                        // RHYTHM fixes §5.3 (2026-10-21): drawn size stays 28×20; hit area extends 2pt up/down
                        // only (28×24).
                        .contentShape(Rectangle().path(in: CGRect(x: 0, y: -2, width: 28, height: 24)))
                }
                .accessibilityLabel("Close the steps picker")
            }
            .frame(height: headerH)
            .padding(.leading, 4)
            Spacer(minLength: sp4)
            VStack(spacing: cellGap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: cellGap) {
                        ForEach(0..<5, id: \.self) { col in
                            let length = lengths[row * 5 + col]
                            stepsPickerCell(idx, line, accent, length: length, width: cellW, height: cellH)
                        }
                    }
                }
            }
            .frame(height: gridH)
        }
        .padding(sp8)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x3A3E47), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose how many steps")
    }
    private func stepsPickerCell(_ idx: Int, _ line: EuclidLine, _ accent: Color, length: Int, width: CGFloat, height: CGFloat) -> some View {
        let isCurrent = length == line.steps
        let pattern: [Bool] = isCurrent
            ? (line.customHitsResolved(length) ?? euclideousStepsPickerPreview(line, length: length))
            : euclideousStepsPickerPreview(line, length: length)
        let hits = pattern.filter { $0 }.count
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(isCurrent ? lane20(accent) : Color(hex: 0x2A2D34))
            if isCurrent { RoundedRectangle(cornerRadius: 6).stroke(lane100(accent), lineWidth: 1) }
            Text("\(length)").font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundColor(isCurrent ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
                .frame(height: 18)
                .padding(.leading, 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(stride(from: 0, to: pattern.count, by: 8)), id: \.self) { rowStart in
                    HStack(spacing: 1.5) {
                        ForEach(rowStart..<min(rowStart + 8, pattern.count), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1).fill(pattern[i] ? lane100(accent) : Color(hex: 0x4A4E57))
                                .frame(width: 4.6, height: 6)
                        }
                    }
                }
            }
            .padding(.leading, 7).padding(.bottom, 7)
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            edit(idx) { l in euclideousSliderCommit(.steps, &l, snapshot: l, newValue: Double(length)) }
            stepsPickerLane = nil
        }
        .accessibilityLabel("\(length) steps, \(hits) hits\(isCurrent ? ", current length" : "")")
    }

    /// RESTART CHAINS ferry §9.7/§9.9 — the lane's OUT A–D row, moved here from the RHYTHM tab's own
    /// `laneOutRow` (deleted: nothing else used it). Reuses `euclideousLaneOutChipStyle` verbatim (the SAME
    /// three-state look `laneOutRow` drew as circles) as a rounded rectangle instead — "header §7.3's dashed
    /// circle as a rounded rectangle" — and carries over its own ring wiring (§10.2), now targeting THIS
    /// button instead of the old RHYTHM-tab circle.
    private func mixOutRow(lane: Int, width: CGFloat, height: CGFloat) -> some View {
        let line = lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all)
        let accent = laneAccents[lane % laneAccents.count]
        let mask = line.emitterMask ?? 0
        let names = ["A", "B", "C", "D"]
        let btnW = max(1, (width - sp4 * 3) / 4)
        let ring = outputRingTargets(panelShowsMix: true)
        return HStack(spacing: sp4) {
            ForEach(0..<4, id: \.self) { b in
                let routed = (mask >> UInt8(b)) & 1 != 0
                let mainOn = (mainOutMask >> UInt8(b)) & 1 != 0
                let style = euclideousLaneOutChipStyle(routed: routed, mainOn: mainOn)
                let textColor: Color = {
                    switch style {
                    case .filled: return patternEmitterActiveText
                    case .hollowDashed: return lane100(accent)
                    case .plain: return patternUnselectedText
                    }
                }()
                Text(names[b]).font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(textColor)
                    .frame(width: btnW, height: height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(style == .filled ? lane100(accent) : (style == .plain ? patternUnselectedFill : Color.clear)))
                    .overlay(
                        Group {
                            switch style {
                            case .filled: EmptyView()
                            case .hollowDashed: RoundedRectangle(cornerRadius: 6).stroke(lane100(accent), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                            case .plain: EmptyView()
                            }
                        }
                    )
                    .overlay {
                        // §10.2: a ring around THIS button when the active output's pulse/trace is this one and this lane is routed to it.
                        if let r = ring, r.output == b, r.targets.contains(.mixOutButton(lane: lane)) {
                            EuclideousOutputCueRing(kind: .mixButton, held: r.held, reduceMotion: reduceMotion).id(r.token)
                        }
                    }
                    // RHYTHM fixes §5.3 (2026-10-21): drawn size stays btnW×height (height=outRowH=20); the
                    // hit area extends 2pt up/down only (to 24 tall) — there's exactly a 4pt gap (sp4) to the
                    // OCT stepper above, so this never reaches into it.
                    .contentShape(Rectangle().path(in: CGRect(x: 0, y: -2, width: btnW, height: height + 4)))
                    .onTapGesture { edit(lane) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
                    .zIndex({ if let r = ring, r.output == b, r.targets.contains(.mixOutButton(lane: lane)) { return 1.0 }; return 0.0 }())
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Lane \(lane + 1), output \(names[b]), \(routed ? "on" : "off")\(style == .hollowDashed ? ", main out \(names[b]) is off" : "")")
            }
        }
        .frame(width: width, height: height)
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
    private func patternControlBlock(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat) -> AnyView {
        // STACK DEPTH (LANE LOCK ferry, 2026-10-22): the rate half (a 3×2 grid + a feel column + the FOLLOW chips, every cell now with a lock tap modifier) and the right half are built by their OWN functions returning
        // `AnyView`, so each one's temporaries die when it returns and this frame only ever holds two 8-byte values (the extension's 1 MB debug stack — Docs/claude-playbook.md).
        // Exact-dimensions ferry (2026-10-13): rowH 40→38 (two 38pt rows + 4pt gap = 80pt block,
        // matching the 118(sliders)+4(gap)+80(this block)=202 tab-content height exactly); halfW's
        // divider footprint corrected from 8 (a bare 1pt rule + 3.5pt either side) to 17 (1pt rule +
        // 8pt padding either side) — both halves land at the spec's own 154.5pt.
        let rowH: CGFloat = 38, gap: CGFloat = 4, blockH = rowH * 2 + gap
        let halfW = max(1, (fullWidth - 17) / 2)
        return AnyView(HStack(spacing: 0) {
            patternRateHalf(idx, line, accent, halfW: halfW, blockH: blockH, gap: gap)
                // LISTEN REBUILT (2026-10-23): the old `.followMult` lock control is retired along with FOLLOW
                // itself — this grid is always the lane's own plain RATE now.
                .modifier(lockOutlineMod(idx, .rate, accent))   // on the AnyView, so the big HStack's type is never copied under a wrapper
            Rectangle().fill(Color(hex: 0x2A2D34)).frame(width: 1).padding(.horizontal, 8)
            patternOutHalf(idx, line, accent, halfW: halfW, rowH: rowH, gap: gap, blockH: blockH)
        }
        .frame(width: fullWidth, height: blockH))
    }
    private func patternRateHalf(_ idx: Int, _ line: EuclidLine, _ accent: Color, halfW: CGFloat, blockH: CGFloat, gap: CGFloat) -> AnyView {
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
        // LISTEN REBUILT (2026-10-23): the old FOLLOW-mult rate grid (÷8…×4, reading the partner's rate) is
        // retired along with FOLLOW itself — RHYTHM's own RATE always shows the lane's plain division/feel
        // grid now, borrowing or not (SPEED/DIRECTION for a borrowing lane live on the LISTEN tab, §2.3).
        let rateHalf = HStack(spacing: gridGap) {
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
                                .modifier(laneTapMod(idx) { setRate(division: d) })
                                .accessibilityValue(lockSpoken(idx, .rate, ""))
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
                        .modifier(laneTapMod(idx) { setRate(feel: f) })
                        .accessibilityLabel(feelLabels[f])
                        .accessibilityValue(lockSpoken(idx, .rate, ""))
                }
            }
        }
        .frame(width: halfW, height: blockH)

        return AnyView(rateHalf)
    }
    private func patternOutHalf(_ idx: Int, _ line: EuclidLine, _ accent: Color, halfW: CGFloat, rowH: CGFloat, gap: CGFloat, blockH: CGFloat) -> AnyView {
        return AnyView(VStack(spacing: gap) {
            // RHYTHM POLISH ferry (2026-10-22) §1.4: the direction row (and INV → FLIP HITS) moved up beside OFFSET and TILT; this group is now the two restart tiles, one full-width row each, matching the rate grid's rows.
            restartTilesRow(idx, line, accent, rowH: rowH, fullWidth: halfW)
        }
        .frame(width: halfW, height: blockH))
    }

    // RIFF TAB RETIRED (ferry 2026-10-10 §1.2) — `riffDirGrid`/`riffTabButton`/`euclideousNextOnRest`/
    // `riffDirPopupCard` deleted entire; confirmed by grep to have no remaining callers once `tabContent`'s
    // `.riff` case was removed. Direction/FREE-LOCK/INVERT/ON-REST selection now lives inline in the melody
    // pop-up's own WALK section below. `riffDirShortLabel` (PEND/PING/RAND short labels) was kept for the
    // riff direction row's own word-label buttons; DELETED 2026-10-22 once that row switched to chevron
    // glyphs ("<"/"><"/">") and dropped PENDULUM — confirmed by grep to have no remaining callers.
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
        case .fill: return "On a riff rest, play nothing from the riff, but keep lit notes sounding"   // MIX ferry Q1: FILL no longer strikes its own pick
        case .tie: return "On a riff rest, hold the previous note"   // §3.3's own literal REST TIE example
        case .repeatLast: return "On a riff rest, play the riff's previous note again"   // RIFF WALK ferry §9.5
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
    /// Returns `AnyView` (LANE LOCK ferry 2026-10-22): its caller's frame then holds 8 bytes per button instead of the whole modifier chain (the page's debug stack — Docs/claude-playbook.md).
    private func melodyButton(_ label: String, on: Bool, accent: Color, height: CGFloat = 40, fontSize: CGFloat = 10, cornerRadius: CGFloat = 6, help: String? = nil, lane: Int? = nil, outline: Bool = false, action: @escaping () -> Void) -> AnyView {
        let base = Text(label).font(.system(size: fontSize, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA))
            .lineLimit(1)   // §4.6: nothing under 10pt — truncate, never shrink (no .minimumScaleFactor call at all, SwiftUI's own default already never scales below 1.0)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(on ? lane20(accent) : Color(hex: 0x2A2D34)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .modifier(EuclideousLockOutline(on: outline, accent: accent))   // LANE LOCK 5.4
            .accessibilityValue(euclideousLockAppendSnapWords("", outlined: outline))   // 5.6
            .modifier(EuclideousLaneTap(locked: lane.map { lockLocked($0) } ?? false, momentary: lane.map { lockMomentary($0) } ?? false,   // LANE LOCK 6.2 / 6.9: a plain tap unless the lane is locked
                                        onTouch: { if let lane { onLockHeld(lane, $0) } }, action: action))
        if let help { return AnyView(base.euclideousHelp(help)) } else { return AnyView(base) }
    }
    /// One chip (default 69.5×34, `width` overridable — 2026-10-14 ferry widens the RIFF tab's own 4 steppers
    /// to 79.25 each so the row runs full width, which also widens the decorative end-zones 14→18pt per the
    /// ferry's own exact "‹ zone 18 | centre 43.25 | › zone 18" breakdown at that width): ‹/› glyphs in the end
    /// zones (decorative), name(10pt) over value(14pt) centred, 2pt apart. Tapping the LEFT HALF of the whole
    /// chip decreases; the RIGHT HALF increases — not just the glyph zones.
    /// `showLabel: false` (RIFF WALK ferry §8.1, the EVERY stepper): drops the key line, showing only the
    /// value, centred — every other call site keeps its label unchanged (the default is `true`).
    private func melodyStepper(_ label: String, value: Int, range: ClosedRange<Int>, unit: String? = nil, width: CGFloat = 69.5, showLabel: Bool = true, help: String? = nil,
                                             height: CGFloat = 34, valueText shown: String? = nil, lowDisabled: Bool = false, highDisabled: Bool = false, wraps: Bool = false, lane: Int? = nil, outline: Bool = false, onChange: @escaping (Int) -> Void) -> AnyView {   // AnyView: see melodyButton
        // NOTES TAB ferry (CHANCE): `height`, a text-valued stepper (25% / 50% / 75% / 100%) and a disabled look at either end — every default leaves the other callers exactly as they were.
        let w: CGFloat = width, h: CGFloat = height, arrowZone: CGFloat = 18
        let valueText = Text(shown ?? (unit != nil ? "\(euclideousSigned(value)) \(unit!)" : "\(value)"))
            .font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)   // §4.6: truncate, never shrink — no .minimumScaleFactor
        let base = ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34))
            HStack(spacing: 0) {
                Text("‹").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: lowDisabled ? 0x4A4E57 : 0x8A909A))
                    .frame(width: arrowZone, height: h)
                Group {
                    if showLabel {
                        VStack(spacing: 2) {
                            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                            valueText
                        }
                    } else {
                        valueText
                    }
                }
                .frame(maxWidth: .infinity)
                Text("›").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: highDisabled ? 0x4A4E57 : 0x8A909A))
                    .frame(width: arrowZone, height: h)
            }
        }
        .frame(width: w, height: h)
        .modifier(EuclideousLockOutline(on: outline, accent: lane.map { laneAccents[$0 % laneAccents.count] } ?? Color.clear))   // LANE LOCK 5.4
        .overlay(
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .modifier(EuclideousLaneTap(locked: lane.map { lockLocked($0) } ?? false, momentary: lane.map { lockMomentary($0) } ?? false,
                                                onTouch: { if let lane { onLockHeld(lane, $0) } }, action: { onChange(wraps && value <= range.lowerBound ? range.upperBound : max(range.lowerBound, value - 1)) }))
                Color.clear.contentShape(Rectangle())
                    .modifier(EuclideousLaneTap(locked: lane.map { lockLocked($0) } ?? false, momentary: lane.map { lockMomentary($0) } ?? false,
                                                onTouch: { if let lane { onLockHeld(lane, $0) } }, action: { onChange(wraps && value >= range.upperBound ? range.lowerBound : min(range.upperBound, value + 1)) }))
            }
        )
        if let help { return AnyView(base.euclideousHelp(help)) } else { return AnyView(base) }
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
    /// VALUES row: four stepper chips, LEN · NUDGE (the old SHIFT, relabelled per an earlier ferry — same
    /// `riffRotate` field, same 0...(LEN-1) range) · STRIDE · TRANS, 3pt gaps (2026-10-13 ferry §5). Per ferry
    /// §6, none of these turn the riff on or off. FIX 3 (2026-10-14 ferry): was a narrower, centred row (4×
    /// 69.5pt chips inside a wider tab) — now spans the tab's own full width, each chip sized from it
    /// (`(fullWidth − 3 inter-chip 3pt gaps) / 4` — at the 326pt reference this is exactly 79.25, matching
    /// the ferry's own literal table).
    private func melodyValuesRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, stepperWidth: CGFloat? = nil) -> some View {
        let n = line.riffLengthResolved
        let shift = line.riffRotateResolved
        let w = stepperWidth ?? max(1, (fullWidth - 3 * sp4) / 4)
        return HStack(spacing: sp4) {
            melodyStepper("LEN", value: n, range: 1...8, width: w, help: "How many riff columns, from SHIFT, the walk loops over", lane: idx, outline: lockOn(idx, .length)) { v in
                edit(idx) { euclideousSetRiffLength(&$0, v) }   // RIFF WINDOW ferry: the ONE LEN setter — independent of SHIFT now, nothing to pin
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Length").accessibilityValue(lockSpoken(idx, .length, "\(n)"))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: edit(idx) { euclideousSetRiffLength(&$0, min(8, n + 1)) }
                case .decrement: edit(idx) { euclideousSetRiffLength(&$0, max(1, n - 1)) }
                @unknown default: break
                }
            }
            // RIFF WINDOW ferry (2026-10-21): SHIFT picks which riff column (1...8) the window starts at,
            // wrapping past column 8 back to column 1 — independent of LENGTH (LEN 4 SHIFT 4 reads columns
            // 5,6,7,8). `wraps: true` makes the ‹/› taps cycle 7→0 and 0→7 to match.
            melodyStepper("SHIFT", value: shift, range: 0...7, width: w, help: "Which riff column the walk starts reading from, wrapping at 8", wraps: true, lane: idx, outline: lockOn(idx, .shift)) { v in
                edit(idx) { euclideousSetRiffShift(&$0, v) }   // RIFF WINDOW ferry: the ONE SHIFT setter — wraps at 8, nothing to do with LEN
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Shift").accessibilityHint("Which riff column the walk starts reading from, wrapping at 8")
            .accessibilityValue(lockSpoken(idx, .shift, "\(shift)"))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: edit(idx) { euclideousSetRiffShift(&$0, (shift + 1) % 8) }
                case .decrement: edit(idx) { euclideousSetRiffShift(&$0, (shift + 7) % 8) }
                @unknown default: break
                }
            }
            melodyStepper("STRIDE", value: line.riffStrideResolved, range: 1...7, width: w, help: "How many riff steps to move per note", lane: idx, outline: lockOn(idx, .stride)) { v in
                edit(idx) { $0.riffStride = v }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Stride").accessibilityValue(lockSpoken(idx, .stride, "\(line.riffStrideResolved)"))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: edit(idx) { $0.riffStride = min(7, line.riffStrideResolved + 1) }
                case .decrement: edit(idx) { $0.riffStride = max(1, line.riffStrideResolved - 1) }
                @unknown default: break
                }
            }
            melodyStepper("TRANS", value: line.melodyTransposeResolved, range: -7...7, width: w, help: "Shift every riff note up or down the pool", lane: idx, outline: lockOn(idx, .transpose)) { v in
                edit(idx) { $0.melodyTranspose = v }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Transpose").accessibilityValue(lockSpoken(idx, .transpose, euclideousSigned(line.melodyTransposeResolved)))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: edit(idx) { $0.melodyTranspose = min(7, line.melodyTransposeResolved + 1) }
                case .decrement: edit(idx) { $0.melodyTranspose = max(-7, line.melodyTransposeResolved - 1) }
                @unknown default: break
                }
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
        let curStep = (idx < riffPositions.count && euclideousLaneIsRunning(transportPlaying: clock.playing, line: line)) ? riffPositions[idx] : -1   // the live step only while the lane runs (as the WALK strip's ring)
        let isRiff = line.riffOnResolved
        let neverPlay = riffReadout(idx)?.neverPlay ?? []   // RIFF WALK ferry §2.1/§7.6
        let window = euclideousRiffWindowColumns(length: len, shift: line.riffRotateResolved)   // RIFF WINDOW ferry (2026-10-21): the window wraps at 8, not always columns 1...LEN
        let cell = max(1, (size - 7) / 8)   // 8 cells + 7 gaps of 1pt
        return VStack(spacing: 1) {
            ForEach((1...8).reversed(), id: \.self) { rank in
                HStack(spacing: 1) {
                    ForEach(0..<n, id: \.self) { col in
                        let raw = col < stepRanks.count ? stepRanks[col] : 0
                        let isHit = raw >= 1 && raw <= 8 && raw == rank
                        let inWindow = window.contains(col)
                        let isCur = col == curStep
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(riffMiniGridFill(isRiff: isRiff, isHit: isHit, isCur: isCur))
                            .frame(width: cell, height: cell)
                            .opacity((!inWindow || neverPlay.contains(col)) ? 0.32 : 1.0)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
    /// Fix 1's own exact fill table — riff ON (card = lane colour, label INK): a note is solid INK; an empty
    /// cell is INK at 14%; the CURRENT step's note (if it has one) is `#f2f4f7`, one cell only. Riff OFF
    /// keeps the SAME palette already shipped, with the current-step note's own `#aab0ba` fill. RIFF WALK
    /// ferry §2.1: a past-LEN or never-played column's own 32% dim is now ONE uniform opacity layer the
    /// caller applies on top (lit or empty alike) — this function no longer bakes its own separate "outside
    /// the window" reduction into the fill colour, which would have double-dimmed those cells.
    private func riffMiniGridFill(isRiff: Bool, isHit: Bool, isCur: Bool) -> Color {
        if isRiff {
            if isHit && isCur { return Color(hex: 0xF2F4F7) }
            if isHit { return Color(hex: 0x0D0F14) }
            return Color(hex: 0x0D0F14).opacity(0.14)
        } else {
            if isHit && isCur { return Color(hex: 0xAAB0BA) }
            if isHit { return Color.white.opacity(0.55) }
            return Color.white.opacity(0.06)
        }
    }
    /// The riff card itself — a 90×82 thumbnail (RIFF WALK ferry §2.1, 8pt shorter than before: OCT's row
    /// is gone) that ALSO serves as this lane's on/off switch for the whole riff layer (ferry §2: "the whole
    /// card toggles the riff on and off; turning it on restores the remembered direction" — `riffDir` is
    /// already persisted independent of `riffOn`, so nothing extra is needed to "remember" it). The card
    /// itself never dims regardless of riff state — its own colour already shows on/off. Geometry per §2.1:
    /// an 11pt label line 8pt below the card's top, the 55.3×55.3 grid (8 cells of 5.6pt, 1.5pt apart)
    /// starting 23pt below the card's top — the grid's OWN size is fixed (cell/gap are literal), not scaled
    /// to fill whatever's left; any remaining height at the bottom is empty.
    private func riffCard(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let isRiff = line.riffOnResolved
        return VStack(spacing: 0) {
            Text("RIFF").font(.system(size: 10, weight: .heavy, design: .monospaced)).kerning(2)
                .foregroundColor(isRiff ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .frame(height: 11)
                .padding(.top, 8)
            Spacer(minLength: 0).frame(height: 4)
            riffMiniGrid(idx, line, accent, size: 55.3)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 10).fill(isRiff ? lane100(accent) : Color(hex: 0x2A2D34)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isRiff ? Color(hex: 0x0D0F14) : Color(hex: 0x5C626C), lineWidth: 1))
        .contentShape(Rectangle())
        .modifier(laneTapMod(idx) { edit(idx) { $0.riffOn = !($0.riffOnResolved) } })
        .modifier(lockOutlineMod(idx, .riffOn, accent))
        .euclideousHelp("The riff as this lane plays it. Tap to turn the riff on or off.")
        .accessibilityElement(children: .ignore)
        .accessibilityValue(lockSpoken(idx, .riffOn, ""))
        .accessibilityLabel({
            guard isRiff else { return "Riff, off" }
            let pos = (idx < riffPositions.count && euclideousLaneIsRunning(transportPlaying: clock.playing, line: line)) ? riffPositions[idx] : -1
            return pos >= 0 ? "Riff, on, now on step \(pos + 1)" : "Riff, on"
        }())
    }
    /// RIFF WALK ferry §3 — the WALK strip: display only, not interactive. A header line ("WALK" + the
    /// readout, §7.5) over a row of up to 16 cells, one per walk step 0..<P, each showing the column it
    /// reads (or a rest dash), the current step ringed, EVERY pips under the number when EVERY >= 2, and a
    /// column/step this lane never plays dimmed to 42% (§7.6).
    private func riffWalkStrip(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let cfg = riffWalkConfig(idx)
        let readout = riffReadout(idx)
        let stepRanks = euclideousRiffStepRanks(ranks: effectiveGridRanks, invert: line.riffInvertResolved, transpose: line.melodyTransposeResolved)
        let len = line.riffLengthResolved
        let every = line.riffAdvanceEveryResolved
        let P = euclideousFXWalkPeriod(dir: line.euclideousRiffDirResolved, length: len, stride: line.riffStrideResolved)
        let readoutText = euclideousRiffReadoutText(readout, overBudget: readout == nil)
        let isRiff = line.riffOnResolved
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("WALK").font(.system(size: 8, weight: .heavy, design: .monospaced)).kerning(0.8).foregroundColor(Color(hex: 0xAAB0BA))
                Spacer(minLength: 2)
                euclideousWalkReadoutText(readoutText)
            }
            .padding(.horizontal, 2)
            .opacity(isRiff ? 1.0 : 0.42)   // §1.8: dims while the riff is off — the cell row below folds this into its own per-cell opacity instead (§3.3: "the dims don't multiply")
            // §3.4: the ring shows only while the transport runs, the lane plays and the riff is on — one
            // TimelineView for the whole row (never one per cell), paused while stopped, matching this
            // page's own established idiom (`riffWalkTagOverlay`).
            let ringEligible = clock.playing && line.enabledResolved && isRiff
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !ringEligible)) { tl in
                let current: Int? = (ringEligible ? cfg : nil).flatMap { riffWalkCurrentStep($0, beat: walkTagBeat(at: tl.date), P: P) }
                HStack(spacing: 1.5) {
                    ForEach(0..<16, id: \.self) { i in
                        if i < P, let cfg {
                            let col = euclideousRiffColumn(ordinal: Int64(i), every: 1, direction: cfg.riffDir, length: len, stride: cfg.stride, shift: cfg.rotate, seed: cfg.seed)
                            let rank = col < stepRanks.count ? stepRanks[col] : 0
                            let isRest = rank < 1
                            let neverPlays = readout?.neverPlayWalkSteps.contains(i) ?? false
                            // §3.3: "the dims don't multiply" — a never-played step on a riff-off lane stays
                            // at 42%, not 0.42×0.42 ≈ 17.6% — so this is ONE opacity decision, not two nested
                            // modifiers (the bug an adversarial review caught: the old code let this cell's
                            // own 42% compound with riffTopRow's outer 42% wrapper).
                            riffWalkStripCell(col: col, isRest: isRest, every: every, isCurrent: i == current, accent: accent, dim: neverPlays || !isRiff)
                        } else {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x181A1F)).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(4)
        .frame(width: width, height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x131519)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x262930), lineWidth: 1))
        .euclideousHelp("The columns this lane's walk reads, in order.")
        // §9.2: one static element — doesn't read the current step (the ring is a sighted-only cue).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk")
        .accessibilityValue(euclideousWalkVoiceOverValue(cfg: cfg, len: len, every: every, P: P, stepRanks: stepRanks, readoutText: readoutText))
    }
    /// One WALK-strip cell: the column number or a rest dash, EVERY pips underneath when EVERY >= 2, lane20
    /// fill + a lane100 inner ring on the current step (§3.3). `dim` is already the FULLY-RESOLVED decision
    /// (never-played OR riff-off) — exactly one opacity level, never stacked with an ancestor's own dim.
    private func riffWalkStripCell(col: Int, isRest: Bool, every: Int, isCurrent: Bool, accent: Color, dim: Bool) -> some View {
        VStack(spacing: 1.5) {
            Text(isRest ? "\u{2013}" : "\(col + 1)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(isRest ? Color(hex: 0x5C626C) : Color(hex: 0xF2F4F7))
                .frame(height: 11)
            if every >= 2 {
                HStack(spacing: 1) {
                    ForEach(0..<every, id: \.self) { j in
                        Circle().fill(isCurrent ? lane100(accent) : (isRest ? Color(hex: 0x4A4E57) : Color(hex: 0x8A909A))).frame(width: 2, height: 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 3).fill(isCurrent ? lane20(accent) : (isRest ? Color(hex: 0x1F2228) : Color(hex: 0x2A2D34))))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isCurrent ? lane100(accent) : Color.clear, lineWidth: 1))
        .opacity(dim ? 0.42 : 1.0)
    }
    /// §3.4: the current walk step = floor(o ÷ EVERY) mod P — ADV HIT reads the latest hit at or before
    /// `beat` (nil until the lane's first hit since the melody origin); ADV STEP reads the step playing now.
    private func riffWalkCurrentStep(_ cfg: EuclideousWalkLaneConfig, beat: Double, P: Int) -> Int? {
        guard cfg.sub > 0, P > 0 else { return nil }
        let advOrd: Int64
        if cfg.advanceStep {
            let tick = Int64((beat / cfg.sub).rounded(.down))
            advOrd = euclideousWalkTick(cfg, tick: tick).advOrd
        } else {
            let scan = euclideousWalkScanHits(cfg, beat: beat, back: 2, ahead: 0)
            guard let t = scan.prev.first else { return nil }
            advOrd = euclideousWalkTick(cfg, tick: t).advOrd
        }
        let w = euclideousRiffWalkStep(ordinal: advOrd, every: cfg.every)
        return Int(((w % Int64(P)) + Int64(P)) % Int64(P))
    }
    /// §3.2's readout text, the amber "N NEVER PLAY" part split out into its own colour.
    private func euclideousWalkReadoutText(_ text: String) -> some View {
        let parts = text.components(separatedBy: " · ")
        return HStack(spacing: 0) {
            Text(parts[0]).foregroundColor(Color(hex: 0x8A909A)).kerning(0.32)   // per Text: `View.kerning` on the stack is iOS 16, `Text.kerning` is iOS 13
            if parts.count > 1 { Text(" · " + parts[1]).foregroundColor(Color(hex: 0xFFB454)).kerning(0.32) }
        }
        .font(.system(size: 8, weight: .heavy, design: .monospaced)).lineLimit(1)
    }
    /// §9.2's VoiceOver value text for the WALK strip.
    private func euclideousWalkVoiceOverValue(cfg: EuclideousWalkLaneConfig?, len: Int, every: Int, P: Int, stepRanks: [Int], readoutText: String) -> String {
        guard let cfg else { return "No hits to play." }
        if readoutText == "CYCLE TOO LONG TO COUNT" { return "The cycle is too long to count." }
        if readoutText == "NO HITS TO PLAY" { return "No hits to play." }
        var cols: [String] = []
        for i in 0..<P {
            let col = euclideousRiffColumn(ordinal: Int64(i), every: 1, direction: cfg.riffDir, length: len, stride: cfg.stride, shift: cfg.rotate, seed: cfg.seed)
            let rank = col < stepRanks.count ? stepRanks[col] : 0
            cols.append(rank < 1 ? "rest" : "\(col + 1)")
        }
        // readoutText (post-2026-10-22: no more "LINES UP EVERY n PASSES") is now either empty or
        // " · n NEVER PLAY" — strip the separator rather than reusing the old capitalize-and-replace,
        // which left an awkward bare "." where "LINES UP EVERY..." used to be.
        let never = readoutText.replacingOccurrences(of: "·", with: "").trimmingCharacters(in: .whitespaces)
        var s = cols.joined(separator: ", ") + ", then round again."
        if !never.isEmpty { s += " " + never.capitalized + "." }
        if every >= 2 { s += ", each for \(every) \(every == 1 ? "hit" : "hits")" }
        return s
    }
    /// RIFF WALK ferry §1.3 Row A — the card (left) + a right-hand column holding the WALK strip (top) and
    /// the direction row with INV (bottom). Supersedes the OCT-trough layout entirely (§1.2): OCT's row is
    /// gone (MIX's stepper is now riffOctave's only control). The card never dims; the right-hand column
    /// dims to 42% while the riff is off, matching every other riff-only control on this tab.
    private func riffTopRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, layout: EuclideousRiffTabLayout) -> some View {
        let isRiff = line.riffOnResolved
        return HStack(spacing: sp4) {
            riffCard(idx, line, accent, width: 90, height: layout.rowAHeight)
            VStack(spacing: sp4) {
                // Floors ferry (2026-10-23): the WALK strip is read-only ("display only, not interactive")
                // — it drops out first when showing it would leave the direction row (real controls) under
                // its own floor, per `layout.showWalkStrip`.
                if layout.showWalkStrip {
                    // §3.3: the strip dims itself per-cell (folding the riff-off state into its own single
                    // opacity decision) — NOT wrapped in an outer .opacity() here, which would compound with
                    // that per-cell dim (a bug an adversarial review caught: 0.42×0.42 ≈ 17.6% on a never-played
                    // step of an off lane, instead of the spec's own "the dims don't multiply" 42%).
                    riffWalkStrip(idx, line, accent, width: layout.rightColumnWidth, height: layout.walkStripHeight)
                }
                riffDirectionRow(idx, line, accent, height: layout.directionRowHeight)
                    .frame(height: layout.directionRowHeight)
                    .opacity(isRiff ? 1.0 : 0.42)
            }
        }
        .frame(height: layout.rowAHeight)
    }
    /// The riff direction row — FWD·REV·PEND·PING·INV, five equal full-label buttons (§2.3: INV moves in
    /// here as the fifth, in the SAME style, replacing its old spot in the retired modes row). Tapping the
    /// lit direction turns the riff off (remembering it); tapping any other turns the riff on with that
    /// direction; INV is a plain toggle, independent of on/off, unchanged from its old behaviour.
    /// Pendulum removed from this row (Paul, 2026-10-22) — still a real, working `RiffDir` case (an
    /// already-saved lane keeps walking it; THROW/TWEAK can still pick it), just no longer offered here.
    /// The remaining three read as chevrons — "<" / "><" / ">" — matching the RHYTHM tab's own direction
    /// tabs exactly (`directionRow`'s glyphs, sizing and colours: `patternSelectedText`/
    /// `patternUnselectedText`/`patternUnselectedFill` already equal `melodyButton`'s own "on"/"off"
    /// colours byte-for-byte, so only the LABEL changes here, not the look it already had).
    /// `height` (Floors ferry, 2026-10-23): the buttons used to declare their own fixed 40pt regardless of
    /// the row's real computed height, so shrinking the row did nothing but squeeze/overflow the HStack —
    /// now they take the real height, so `EuclideousRiffTabFloors.directionRowHeight` means something.
    private func riffDirectionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, height: CGFloat) -> some View {
        let dirs: [(RiffDir, String)] = [(.reverse, "<"), (.pingpong, "><"), (.forward, ">")]
        let curDir = line.euclideousRiffDirResolved
        let isRiff = line.riffOnResolved
        return HStack(spacing: 3) {
            ForEach(dirs, id: \.0) { d, glyph in
                let lit = curDir == d
                melodyButton(glyph, on: lit, accent: accent, height: height, fontSize: 13, cornerRadius: 7,
                             help: "How the riff walks. Tap the lit one to turn the riff off.", lane: idx, outline: lit && lockOn(idx, .riffDirection)) {
                    edit(idx) { l in
                        if l.riffOnResolved && l.euclideousRiffDirResolved == d { l.riffOn = false }
                        else { l.riffOn = true; l.riffDir = d }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(riffDirHelpPhrase(d).capitalized), \(lit ? "selected" : "not selected")" + (lit && isRiff ? ". Tap again to turn the riff off." : ""))
                .accessibilityValue(euclideousLockAppendSnapWords("", outlined: lit && lockOn(idx, .riffDirection)))
            }
            // Paul, 2026-10-22: "Change INV to read Invert melody" — the visible label itself, not just
            // the spoken value (which already said as much via its own descriptive phrase). 10pt (the
            // house floor — "nothing under 10pt," §4.6) rather than the chevrons' 13: "Invert melody" is
            // long for this row's now-four-way split; it truncates rather than shrinks if a card is
            // narrow, the same house rule every other label on this tab already accepts.
            melodyButton("Invert melody", on: line.riffInvertResolved, accent: accent, height: height, fontSize: 10, cornerRadius: 7,
                         help: "Flip the riff upside down in pitch", lane: idx, outline: lockOn(idx, .riffInvert)) { edit(idx) { $0.riffInvert = !($0.riffInvertResolved) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Invert melody")
                .accessibilityValue(lockSpoken(idx, .riffInvert, ""))
                .accessibilityAddTraits(line.riffInvertResolved ? [.isButton, .isSelected] : .isButton)
        }
    }
    /// RIFF WALK ferry §1.3 Row B — "ADVANCE" / "EVERY" label, the EVERY stepper (§8), then HIT/STEP (§2.4:
    /// read "HIT"/"STEP" at EVERY 1, "HITS"/"STEPS" at 2-8 (raised from 2-4, 2026-10-22), so the row reads
    /// "ADVANCE EVERY 2 STEPS").
    private func riffAdvanceRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, layout: EuclideousRiffTabLayout) -> some View {
        let isRiff = line.riffOnResolved
        let every = line.riffAdvanceEveryResolved
        let plural = every >= 2
        return HStack(spacing: sp4) {
            riffRowLabel("ADVANCE", "EVERY").frame(width: layout.labelColumnWidth)
            melodyStepper("EVERY", value: every, range: 1...8, width: layout.everyStepperWidth, showLabel: false,
                         help: "The riff moves once every this many hits (or steps)", lane: idx, outline: lockOn(idx, .advanceEvery)) { v in
                edit(idx) { $0.riffAdvanceEvery = v }
            }
            // §9.4: ONE adjustable element — "1 hit"/"2 hits" or "1 step"/"3 steps" following ADV, swipe up/
            // down changes it by one, matching how the values-row steppers read.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Advance every")
            .accessibilityValue(lockSpoken(idx, .advanceEvery, "\(every) \(line.riffAdvanceStepResolved ? (every == 1 ? "step" : "steps") : (every == 1 ? "hit" : "hits"))"))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: edit(idx) { $0.riffAdvanceEvery = min(8, every + 1) }
                case .decrement: edit(idx) { $0.riffAdvanceEvery = max(1, every - 1) }
                @unknown default: break
                }
            }
            melodyButton(plural ? "HITS" : "HIT", on: !line.riffAdvanceStepResolved, accent: accent, height: layout.rowBHeight, fontSize: 11, cornerRadius: 7,
                         help: "Move the riff only on sounding hits", lane: idx, outline: lockOn(idx, .advanceMode) && !line.riffAdvanceStepResolved) { edit(idx) { $0.riffAdvanceStep = false } }
                .frame(width: layout.hitStepButtonWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Advance by hits")
                .accessibilityValue(euclideousLockAppendSnapWords("", outlined: lockOn(idx, .advanceMode) && !line.riffAdvanceStepResolved))
                .accessibilityAddTraits(!line.riffAdvanceStepResolved ? [.isButton, .isSelected] : .isButton)
            melodyButton(plural ? "STEPS" : "STEP", on: line.riffAdvanceStepResolved, accent: accent, height: layout.rowBHeight, fontSize: 11, cornerRadius: 7,
                         help: "Move the riff on every step, not just hits", lane: idx, outline: lockOn(idx, .advanceMode) && line.riffAdvanceStepResolved) { edit(idx) { $0.riffAdvanceStep = true } }
                .frame(width: layout.hitStepButtonWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Advance by steps")
                .accessibilityValue(euclideousLockAppendSnapWords("", outlined: lockOn(idx, .advanceMode) && line.riffAdvanceStepResolved))
                .accessibilityAddTraits(line.riffAdvanceStepResolved ? [.isButton, .isSelected] : .isButton)
        }
        .opacity(isRiff ? 1.0 : 0.42)
    }
    /// RIFF WALK ferry §1.4 — the ON REST row: "ON REST" / "IN RIFF" label, then SKIP / TIE / REPEAT. NOTES TAB ferry §9: FILL is gone from the row (it adds no pitch of its own; the
    /// NOTES tab's RESTS now does what it was for). A lane still holding `.fill` in memory reads as SKIP — which is what its decoder makes it.
    private func riffOnRestRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, layout: EuclideousRiffTabLayout) -> some View {
        let isRiff = line.riffOnResolved
        let current: EuclidRiffOnRest = line.riffOnRestResolved == .fill ? .skip : line.riffOnRestResolved
        return HStack(spacing: sp4) {
            riffRowLabel("ON REST", "IN RIFF").frame(width: layout.labelColumnWidth)
            ForEach([EuclidRiffOnRest.skip, .tie, .repeatLast], id: \.self) { r in
                let selected = current == r
                melodyButton(r.rawValue == "REPEAT" ? "REPEAT" : r.rawValue, on: selected, accent: accent, height: layout.lowerRowHeight, fontSize: 11, cornerRadius: 7,
                             help: riffOnRestHelpPhrase(r), lane: idx, outline: selected && lockOn(idx, .onRest)) { edit(idx) { $0.riffOnRest = r } }
                    .frame(width: layout.onRestButtonWidth)
                    // §9.5 / NOTES TAB §9.3: SKIP and TIE keep their plain labels; REPEAT reads "Repeat" with its own hint.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(r == .repeatLast ? "Repeat" : r.rawValue.capitalized)
                    .accessibilityValue(euclideousLockAppendSnapWords("", outlined: selected && lockOn(idx, .onRest)))
                    .accessibilityHint(r == .repeatLast ? "Plays the riff's previous note again" : "")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .opacity(isRiff ? 1.0 : 0.42)
    }
    /// §2.6's label column: a name over a second line, 3pt below, centred vertically as a pair — replaces
    /// the retired rotated `melodyVerticalLabel("ADV"/"REST", ...)` single-word labels.
    private func riffRowLabel(_ top: String, _ bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(top).font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.9).foregroundColor(Color(hex: 0xF2F4F7))
            Text(bottom).font(.system(size: 8, weight: .heavy, design: .monospaced)).kerning(0.64).foregroundColor(Color(hex: 0x8A909A))
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The whole RIFF tab, RIFF WALK ferry §1.1-§1.4: the RIFF tab now fills RHYTHM's own two zones exactly
    /// (`euclideousRiffTabLayout`, §1.5 — reusing RHYTHM's real `patternBlockH`/`upperH` split, not the
    /// ferry's own literal 124/208 reference figures, which don't match the real `contentAreaH` formula —
    /// reported, not hand-fitted), so the header row and tab row stop moving between tabs. Upper zone: Row A
    /// (card + WALK strip + direction row) + Row B (ADVANCE EVERY). Lower zone: ON REST row + values row.
    private func riffTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        let layout = euclideousRiffTabLayout(contentAreaH: contentAreaH, fullWidth: fullWidth, sp4: sp4)
        // LISTEN REBUILT (2026-10-23): RIFF pauses whole under SHADOW or ECHO now (§9.9's `borrowedTabs`), not SHADOW alone.
        let paused = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
        return ZStack {
            VStack(spacing: sp4) {
                riffTopRow(idx, line, accent, layout: layout)
                riffAdvanceRow(idx, line, accent, layout: layout).frame(height: layout.rowBHeight)
                riffOnRestRow(idx, line, accent, layout: layout).frame(height: layout.lowerRowHeight)
                melodyValuesRow(idx, line, accent, fullWidth: fullWidth, stepperWidth: layout.valueStepperWidth)
                    .frame(height: layout.lowerRowHeight)
                    .opacity(line.riffOnResolved ? 1.0 : 0.42)
            }
            .opacity(paused ? EuclideousListenPauseMetrics.dimOpacity : 1)
            .allowsHitTesting(!paused)
            .accessibilityHidden(paused)
            if paused { listenPausedOverlay(idx, line, label: "RIFF", width: fullWidth, height: contentAreaH) { $0.listenPitch = .own } }
        }
    }
    /// §7 (LISTEN REBUILT, 2026-10-23): the opacity a borrowed tab's own content dims to underneath its
    /// paused-card overlay (replaces the old SHADOW-only 0.42).
    private enum EuclideousListenPauseMetrics { static let dimOpacity: Double = 0.18 }

    /// §7.2's own exact explanatory sentence, literal: RHYTHM names COPY's "h of s hits" or FILL's "g of s
    /// steps" (g = s − h) before the shared DELAY/SPEED/DIRECTION-moved-to-LISTEN sentence; RIFF (and NOTES,
    /// which pauses alongside it, §4.6/§9.9 — the spec gives no separate NOTES wording) names which of
    /// SHADOW/ECHO is active before the shared INTERVAL/OCTAVE-moved-to-LISTEN sentence.
    private func listenPausedExplanation(_ idx: Int, _ line: EuclidLine, label: String) -> String {
        if label == "RHYTHM" {
            let eff = euclideousEffectivePattern(lane: idx, lines: lines)
            let steps = eff?.n ?? 0, hits = eff.map { e in e.buf.prefix(e.n).filter { $0 }.count } ?? 0
            let first = line.listenRhythmResolved == .fill
                ? "Filling its gaps: \(steps - hits) of \(steps) steps."
                : "Copying its \(hits) of \(steps) hits."
            return "\(first) Delay, speed and direction are on Listen. Your own rhythm is kept for when you stop following."
        }
        let mode = line.listenPitchResolved == .echo ? "ECHO" : "SHADOW"
        return "Playing its notes (\(mode)). Interval and octave are on Listen. Your own riff is kept for when you stop following."
    }
    /// §7.2 (LISTEN REBUILT, 2026-10-23; adversarial-review fix — built without the literal spec text in
    /// hand the first time, corrected against it here): the paused-card overlay — a link glyph (the
    /// source's lane100), "<LABEL> FOLLOWS LANE n" (heavy, #F2F4F7 — NOT lane-coloured), one explanatory
    /// line (13pt #D5D9E0, exact text per `listenPausedExplanation`), and two buttons at least 44pt tall
    /// (GO TO LISTEN / USE MY OWN) — drawn over a borrowed tab's own content, which sits underneath at
    /// `EuclideousListenPauseMetrics.dimOpacity` and takes no touches (§7: "a tab is either fully the
    /// lane's own or fully paused"). Card: radius as the lane card's inner panels (12), #24262C fill, 1pt
    /// border in the source's lane100 at 50%, padding sp16 — matching `listenRhythmPanel`/`listenPitchPanel`'s
    /// own panel look exactly, per §2.3/§2.5's "same panel look as 2.3". `useOwn` writes back whichever
    /// field this tab's row actually reads (RHYTHM → `listenRhythm`, RIFF/NOTES → `listenPitch`).
    private func listenPausedOverlay(_ idx: Int, _ line: EuclidLine, label: String, width: CGFloat, height: CGFloat, useOwn: @escaping (inout EuclidLine) -> Void) -> some View {
        let source = line.listenSourceResolved(ownLane: idx)
        let sourceAccent = laneAccents[source % laneAccents.count]
        return VStack(spacing: 6) {
            VStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 16, weight: .bold)).foregroundColor(lane100(sourceAccent))
                Text("\(label) FOLLOWS LANE \(source + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
                    .multilineTextAlignment(.center).lineLimit(1)
                Text(listenPausedExplanation(idx, line, label: label))
                    .font(.system(size: 13, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0xD5D9E0))
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            // Grouped into one spoken element (the icon alone has nothing to say); the two buttons below stay
            // their own separately-focusable elements, not swallowed into this group.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) follows lane \(source + 1)")
            HStack(spacing: 8) {
                Text("GO TO LISTEN").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(patternSelectedText)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 7).fill(lane20(sourceAccent)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(lane100(sourceAccent), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { if idx < laneTab.count { laneTab[idx] = .listen } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Go to Listen")
                    .accessibilityAddTraits(.isButton)
                Text("USE MY OWN").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(patternUnselectedText)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 7).fill(patternUnselectedFill))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx, useOwn) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Use my own \(label.lowercased())")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(sp16)
        // §7.2: "one card CENTRED over them" — the card hugs its own content and centres in the tab body
        // (the ZStack caller's default alignment), not a card that fills the whole body. `width`/`height`
        // (the body's own size) only cap how wide it may grow.
        .frame(maxWidth: min(width - sp16 * 2, 280), maxHeight: height)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x24262C)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(lane100(sourceAccent).opacity(0.5), lineWidth: 1))
    }

    // MARK: - NOTES TAB (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs") — lit notes/
    // TOP/TOP2 + 4 new things: an on/off strip for the notes layer, per-note octave shifts, the notes
    // layer's own octave (independent of RIFF's — the ferry's explicit reversal), and a velocity offset for
    // the notes layer alone. Total content height: 120 (keys+chips) + 8 + 40 (octave+TOP/TOP2) + 8 + 34
    // (NOTES VEL) = 210 — slightly over this page's usual 202 budget, a disclosed judgment call (see this
    // section's own layout note) rather than squeezing any one row below a comfortable touch size; the
    // excess clips per this file's own established "fit always wins, nothing shrinks a font" precedent if a
    // narrower/shorter real card ever offers less.

    /// The NOTES strip — the whole layer's own on/off master switch (same visual language as the RIFF
    /// card's own on/off styling, just vertical), carrying a new 8-bar lit-notes graphic (rank 1 at the
    /// bottom, matching the keys row's own left-to-right rank order read top-down) so the strip itself
    /// shows WHICH notes are lit without needing to glance across the whole row.
    private func notesStrip(_ idx: Int, _ line: EuclidLine, _ accent: Color, height: CGFloat) -> some View {
        let isOn = euclideousNotesLayerIsOn(line)   // off whenever no note is selected, even if the switch itself is on (Paul 2026-10-18)
        let litMask = line.litNotesResolved
        let litCount = (0..<8).filter { (litMask & (1 << $0)) != 0 }.count + (line.topLitResolved ? 1 : 0) + (line.top2LitResolved ? 2 : 0)
        return VStack(spacing: 8) {
            Text("NOTES").font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(isOn ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
                .fixedSize().rotationEffect(.degrees(-90)).frame(width: EuclideousNotesTabLayout.stripW)
            VStack(spacing: 1) {
                ForEach((1...8).reversed(), id: \.self) { rk in
                    let lit = (litMask & (1 << (rk - 1))) != 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill((isOn ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA)).opacity(lit ? 1.0 : 0.25))
                        .frame(width: 10, height: 3)
                }
            }
        }
        .frame(width: EuclideousNotesTabLayout.stripW, height: height)   // NOTES TAB ferry §1.3: 35 wide, across both zones and the gap between them
        .background(RoundedRectangle(cornerRadius: 6).fill(isOn ? lane100(accent) : Color(hex: 0x2A2D34)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? Color(hex: 0x0D0F14) : Color(hex: 0x5C626C), lineWidth: 1))
        .contentShape(Rectangle())
        .modifier(laneTapMod(idx) { edit(idx) { $0.notesOn = !euclideousNotesLayerIsOn($0) } })   // flips what the strip SHOWS (on → off, off → on)
        .modifier(lockOutlineMod(idx, .notesStrip, accent))
        .euclideousHelp("Turn the notes layer on or off. Lit notes are remembered.")
        .accessibilityElement(children: .ignore)
        .accessibilityValue(lockSpoken(idx, .notesStrip, ""))
        .accessibilityLabel("Notes layer, \(isOn ? "on" : "off"), \(litCount) notes lit")
    }
    /// What the NOTES tab shows for one lane, from the SAME pool the riff grid's note-label column reads: the ten keys (names via the grid's own naming function, received vs octave copy
    /// via the same `rank <= pool.count` test), the play list (6.5) and the spoken names. Nothing held: every key takes the copy look and an en dash, as the grid does.
    private struct NotesTabData {
        var specs: [EuclideousNotesKeySpec]
        var list: EuclideousNotesList
        var spoken: [[String]]      // per position: the spoken note names (rank key: one or none; TOP: one; TOP 2: up to two)
    }
    private func notesTabData(_ line: EuclidLine, riffDotRank: Int? = nil, sounding: [Double] = []) -> NotesTabData {
        let pool = riffLivePool
        let n = pool.count
        let extended = euclideousGlobalPoolExtended(sortedRaw: pool.map { Int($0) })
        func name(_ m: Int) -> String {
            guard m >= 0, m <= 127 else { return "\u{2013}" }
            return euclideousDisplayNoteName(UInt8(m), source: noteSource, pool: pool, keyRoot: keyRoot, keyType: keyType)
        }
        func spoken(_ m: Int) -> String {
            euclideousAccessibleDisplayNoteName(UInt8(max(0, min(127, m))), source: noteSource, pool: pool, keyRoot: keyRoot, keyType: keyType)
        }
        let order = line.litOrderResolved
        let receivedOnly = line.notesReceivedOnlyResolved
        let list = notesPlayList(line)
        let places = euclideousNotesPlaceNumbers(list: list, way: line.notesPlayAsResolved)
        var specs: [EuclideousNotesKeySpec] = []
        var spokenNames: [[String]] = []
        for p in 0..<10 {
            let lit = order.contains(p)
            let sound = p < sounding.count ? sounding[p] : 0
            if p < 8 {
                let rank = p + 1
                let has = rank <= extended.count
                specs.append(EuclideousNotesKeySpec(position: p, received: rank <= n, lit: lit, heldBack: lit && receivedOnly && rank > n,
                                                    name: has ? name(extended[rank - 1]) : "\u{2013}", place: places[p],
                                                    riffDot: riffDotRank == rank, sounding: sound))
                spokenNames.append(has ? [spoken(extended[rank - 1])] : [])
            } else if p == EuclideousLitOrder.topTwoPosition {
                let second: String = n >= 2 ? name(Int(pool[n - 2])) + "+" : (n == 1 ? name(Int(pool[0])) : "\u{2013}")
                specs.append(EuclideousNotesKeySpec(position: p, received: n > 0, lit: lit, heldBack: false, name: second, place: places[p], riffDot: false, sounding: sound))
                spokenNames.append(n >= 2 ? [spoken(Int(pool[n - 2])), spoken(Int(pool[n - 1]))] : (n == 1 ? [spoken(Int(pool[0]))] : []))
            } else {
                specs.append(EuclideousNotesKeySpec(position: p, received: n > 0, lit: lit, heldBack: false, name: n >= 1 ? name(Int(pool[n - 1])) : "\u{2013}", place: places[p],
                                                    riffDot: false, sounding: sound))
                spokenNames.append(n >= 1 ? [spoken(Int(pool[n - 1]))] : [])
            }
        }
        return NotesTabData(specs: specs, list: list, spoken: spokenNames)
    }
    /// 10.1 / 10.2: which keys are sounding and where the riff dot sits, for lane `idx` at `beat` — from the lane's latest strike event (the engine's own NOTE VIEW event, the same feed the
    /// header rings and the comet bar flash from) and `euclideousNotesKeyFlash`; nothing is kept per frame. ROLL's spacing needs the gap to the lane's next hit, so that is worked out
    /// from the lane's own walk config exactly as the engine does (`euclideousNextChainHitGapBeats`).
    private func notesKeyFlash(_ idx: Int, _ line: EuclidLine, list: EuclideousNotesList, now: Double) -> EuclideousNotesKeyFlash {
        // the strike's pitches come from the latest NOTE VIEW event; its velocities and display-clock onset from the feed's matching strike (PULSE §8.1: the glow takes §1's f for the notes layer's played velocity)
        guard idx < strikeEvents.count, let ev = strikeEvents[idx], let cfg = riffWalkConfig(idx),
              let s = pulseFeed.strikes(lane: idx).last(where: { $0.onsetBeat == ev.onsetBeat && $0.onsetAt <= now }) else { return EuclideousNotesKeyFlash() }
        let way = line.notesPlayAsResolved
        let step = max(1e-6, cfg.sub)
        let tempo = max(1.0, clock.tempo)
        var gap = step
        if way == .roll {
            let tick = Int64((lanesMusicalBeat(real: ev.onsetBeat) / step).rounded())
            gap = euclideousNextChainHitGapBeats(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: euclidCycleLen(cfg.dir, n: cfg.n), sub: step, tick: tick,
                                                 cap: euclidCycleLen(cfg.dir, n: cfg.n) * 4, chains: cfg.chains, legacySpanBeats: cfg.spanBeats)
        }
        let g = line.notesGateResolved
        let len = euclideousPitchGateBeats(gate: g, nextHitGapBeats: gap, tieExt: 0, minGateBeats: 0.005 * tempo / 60.0)
        return euclideousNotesKeyFlash(eventPitches: ev.notes, hasRiffNote: ev.hasRiffNote, riffRank: Int(ev.rank), seconds: now - s.onsetAt, riffVel: Int(s.riffVel), notesVel: Int(s.notesVel), list: list,
                                       pitchShift: 12 * max(-2, min(2, line.octaveResolved)), way: way, stepBeats: step, gapBeats: gap, lenBeats: len, legato: g >= 1.0,
                                       tempo: tempo, scale: euclideousPulseScale(level: pulseLevel))
    }
    @ViewBuilder private func notesToggle(_ label: String, on: Bool, accent: Color, accessibility: String, hint: String, help: String, lane: Int? = nil, outline: Bool = false, action: @escaping () -> Void) -> some View {
        melodyButton(label, on: on, accent: accent, height: EuclideousNotesTabLayout.rowH, fontSize: 12, cornerRadius: 8, help: help, lane: lane, outline: outline, action: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)
            .accessibilityValue(euclideousLockAppendSnapWords(on ? "on" : "off", outlined: outline))
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
    }
    /// The whole NOTES tab (NOTES TAB ferry 2026-10-19 §1-§4): the strip across both zones, then four rows — the ten keys, WHEN (PLAYS · RESTS · CHANCE), PLAY AS and SOUND ONLY — and, over both
    /// zones and the gap, the PLAY AS picker while it is open. Every frame comes from `euclideousNotesTabLayout`. While the notes layer is off everything right of the strip draws at 42% and stays live;
    /// the strip keeps its own look and the picker is not dimmed.
    private func notesTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        let isOn = line.notesOnResolved
        // LISTEN REBUILT (2026-10-23): NOTES pauses whole under SHADOW or ECHO (§9.9's `borrowedTabs`, NOTES
        // reads the riff far beyond one pitch, so it always pauses alongside RIFF — confirmed, not assumed).
        let shadowing = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
        let lay = euclideousNotesTabLayout(contentAreaH: contentAreaH, fullWidth: fullWidth, sp4: sp4)
        let data = notesTabData(line)
        let way = line.notesPlayAsResolved
        let plays = line.notesPlaysResolved, rests = line.notesRestsResolved
        let chance = line.notesChanceResolved
        let chanceStops = [25, 50, 75, 100]
        let chanceIdx = chanceStops.firstIndex(of: chance) ?? 3
        // a control placed by its layout frame; `row` is the row group it lives in (the group's origin is subtracted so the control sits where the layout says)
        func placed<V: View>(_ r: CGRect, in row: CGRect? = nil, @ViewBuilder _ v: () -> V) -> some View {
            v().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY - (row?.minY ?? 0))
        }
        // one VoiceOver group per row (§11.2): the group spans the content width at the row's own y, its children keep their layout x
        func group<V: View>(_ row: CGRect, label: String, @ViewBuilder _ v: () -> V) -> some View {
            ZStack(alignment: .topLeading) { v() }
                .frame(width: fullWidth, height: row.height, alignment: .topLeading)
                .offset(x: 0, y: row.minY)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        }
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                placed(lay.strip) { notesStrip(idx, line, accent, height: lay.strip.height) }
                Group {
                    // the keys (§2): a tap lights or unlights through the lit order — one undo step
                    group(lay.keyRow, label: euclideousNotesKeyRowGroupLabel) {
                        // the glow and the riff dot follow the hit events (10.1, 10.2) — the only per-frame work on the tab, and only while the transport runs
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pulseLive)) { tl in
                            let flash = notesKeyFlash(idx, line, list: data.list, now: tl.date.timeIntervalSinceReferenceDate)
                            ZStack(alignment: .topLeading) {
                                ForEach(0..<10, id: \.self) { p in
                                    let spec: EuclideousNotesKeySpec = {
                                        var sp = data.specs[p]
                                        sp.sounding = flash.sounding[p]
                                        sp.riffDot = p < 8 && flash.riffDotRank == p + 1 && flash.riffDotStrength > 0
                                        return sp
                                    }()
                                    // The shape, the tap and the accessibility element go BEFORE the offset: a `.contentShape` applied after `.offset` stays at the un-offset position, which stacked all
                                    // ten keys' hit areas at the row's top-left (over the strip) and left the keys, TOP 2, TOP and the strip's left edge untappable.
                                    EuclideousNotesKeyView(spec: spec, accent: lane100(accent), size: lay.keys[p].size)
                                        .contentShape(Rectangle())
                                        .modifier(laneTapMod(idx) { edit(idx) { euclideousToggleLitPosition(&$0, position: p) } })
                                        .modifier(lockOutlineMod(idx, .noteKey(p), accent))
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(p < 8
                                            ? euclideousNotesRankKeyAccessibilityLabel(rank: p + 1, spokenNote: data.spoken[p].first, received: spec.received, lit: spec.lit, heldBack: spec.heldBack, place: spec.place)
                                            : euclideousNotesTopKeyAccessibilityLabel(isTopTwo: p == EuclideousLitOrder.topTwoPosition, spokenNotes: data.spoken[p], lit: spec.lit, place: spec.place))
                                        .accessibilityValue(lockSpoken(idx, .noteKey(p), ""))
                                        .accessibilityHint("Lights or unlights this note")
                                        .accessibilityAddTraits(.isButton)
                                        .ringToggleTrait()
                                        .offset(x: lay.keys[p].minX, y: lay.keys[p].minY - lay.keyRow.minY)
                                }
                            }
                        }
                    }
                    // WHEN (§3.1, §3.2): PLAYS and RESTS — one of the two always stays on; CHANCE steps 25 / 50 / 75 / 100
                    group(lay.whenRow, label: euclideousNotesWhenGroupLabel) {
                        placed(lay.whenLabel, in: lay.whenRow) { riffRowLabel("WHEN", "RIFF") }.accessibilityHidden(true)
                        placed(lay.plays, in: lay.whenRow) {
                            notesToggle("PLAYS", on: plays, accent: accent, accessibility: euclideousNotesPlaysLabel,
                                        hint: euclideousNotesWhenHint(isOnlyOneOn: plays && !rests, riffOn: line.riffOnResolved),
                                        help: "Play the lit notes on hits where the riff plays a note.", lane: idx, outline: lockOn(idx, .notesWhen)) {
                                guard !(plays && !rests) else { return }
                                edit(idx) { $0.notesWhen = $0.notesWhenResolved ^ 0b01 }
                            }
                        }
                        placed(lay.rests, in: lay.whenRow) {
                            notesToggle("RESTS", on: rests, accent: accent, accessibility: euclideousNotesRestsLabel,
                                        hint: euclideousNotesWhenHint(isOnlyOneOn: rests && !plays, riffOn: line.riffOnResolved),
                                        help: "Play the lit notes on hits where the riff rests.", lane: idx, outline: lockOn(idx, .notesWhen)) {
                                guard !(rests && !plays) else { return }
                                edit(idx) { $0.notesWhen = $0.notesWhenResolved ^ 0b10 }
                            }
                        }
                        placed(lay.chance, in: lay.whenRow) {
                            melodyStepper("CHANCE", value: chanceIdx, range: 0...3, width: lay.chance.width, help: "How many of the chosen hits the lit notes play.",
                                          height: lay.chance.height, valueText: "\(chance)%", lowDisabled: chanceIdx == 0, highDisabled: chanceIdx == 3, lane: idx, outline: lockOn(idx, .notesChance)) { v in
                                guard v != chanceIdx else { return }
                                edit(idx) { $0.notesChance = chanceStops[v] }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Chance")
                            .accessibilityValue(lockSpoken(idx, .notesChance, euclideousNotesChanceValue(chance)))
                            .accessibilityAdjustableAction { direction in
                                let next = direction == .increment ? min(3, chanceIdx + 1) : max(0, chanceIdx - 1)
                                guard next != chanceIdx else { return }
                                edit(idx) { $0.notesChance = chanceStops[next] }
                            }
                        }
                    }
                    // PLAY AS (§3.3): the current way with a live preview; a tap opens the picker (not an undo step)
                    group(lay.playAsRow, label: euclideousNotesPlayAsGroupLabel) {
                        placed(lay.playAsLabel, in: lay.playAsRow) { riffRowLabel("PLAY", "AS") }.accessibilityHidden(true)
                        placed(lay.playAs, in: lay.playAsRow) {
                            EuclideousNotesPlayAsButtonView(way: way, list: data.list, accent: lane100(accent))
                                .equatable()
                                .contentShape(Rectangle())
                                .modifier(lockOutlineMod(idx, .notesPlayAs, accent))
                                .onTapGesture { notesPickerOpen.insert(idx) }
                                .euclideousHelp("How the lit notes play on each hit it chooses.")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(euclideousNotesPlayAsButtonLabel(way))
                                .accessibilityValue(lockSpoken(idx, .notesPlayAs, euclideousNotesPlayAsButtonValue(way)))
                                .accessibilityHint(euclideousNotesPlayAsHint)
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    // SOUND ONLY (§3.4)
                    group(lay.soundRow, label: euclideousNotesSoundOnlyGroupLabel) {
                        placed(lay.soundLabel, in: lay.soundRow) { riffRowLabel("SOUND", "ONLY") }.accessibilityHidden(true)
                        placed(lay.received, in: lay.soundRow) {
                            notesToggle("RECEIVED", on: line.notesReceivedOnlyResolved, accent: accent, accessibility: euclideousNotesReceivedLabel, hint: euclideousNotesReceivedHint,
                                        help: "Keep lit octave copies silent, so lit ranks join in as the held chord grows.", lane: idx, outline: lockOn(idx, .notesReceived)) {
                                edit(idx) { $0.notesReceivedOnly = !$0.notesReceivedOnlyResolved }
                            }
                        }
                    }
                }
                .opacity(isOn ? 1.0 : 0.42)
            }
            .opacity(shadowing ? EuclideousListenPauseMetrics.dimOpacity : 1)
            .allowsHitTesting(!shadowing)
            .accessibilityHidden(shadowing)
            if shadowing { listenPausedOverlay(idx, line, label: "NOTES", width: fullWidth, height: contentAreaH) { $0.listenPitch = .own } }
            if notesPickerOpen.contains(idx) {
                EuclideousNotesPickerView(layout: lay, current: way, list: data.list, accent: lane100(accent),
                                          onChoose: { w in
                                              if w != way { edit(idx) { $0.notesPlayAs = w } }
                                              notesPickerOpen.remove(idx)
                                          },
                                          onClose: { notesPickerOpen.remove(idx) })
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(euclideousNotesPickerGroupLabel)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .frame(width: fullWidth, height: contentAreaH, alignment: .topLeading)
        // §4.5: switching the tab, a layout change or the card going away closes the picker
        .onDisappear { notesPickerOpen.remove(idx) }
        .onChange(of: contentAreaH) { _ in notesPickerOpen.remove(idx) }
        .onChange(of: fullWidth) { _ in notesPickerOpen.remove(idx) }
    }

    // MARK: - Per-lane EUCLID MASK (Paul 2026-10-07, §2.7 — pattern/transport; real effect added 2026-10-10
    // "modes and settings" ferry; step-bar fixed 2026-10-11, see `maskStepBar`'s own doc comment)




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
        // §2.5: the all-lanes drag is also an OFFSET writer — stores the displayed (mirrored) offset too.
        onEdit { lines in for i in lines.indices where euclideousRhythmBorrowPartner(lane: i, lines: lines) == nil {
            let n = max(2, min(16, lines[i].steps)); lines[i].rotate = ((lines[i].rotate - d) % n + n) % n
            let r = ((lines[i].rotate % n) + n) % n; lines[i].offsetRequested = (n - r) % n
        } }
    }
    private func euclideousApplyAllRhythmY(_ d: Int) {
        // §2.5: the all-lanes drag is also a HITS writer — stores what was actually asked for too.
        onEdit { lines in for i in lines.indices {
            let n = max(2, min(16, lines[i].steps)); lines[i].pulses = max(0, min(n, lines[i].pulses + d))
            lines[i].hitsRequested = lines[i].pulses
        } }
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
        // §10: one of a row of exclusive choices — label + hint read together, SELECTED when lit (matches
        // `notesToggle`'s own accessibility shape elsewhere on this page).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name.capitalized), \(hint.lowercased())")
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
    }
    /// §3's own ANY glyph: "a circle split into four quarters (red, blue, yellow, green, clockwise from
    /// the top)." Four quarter-pie wedges via `Path`, each a plain 90° arc from the lane's own accent.
    // LISTEN REBUILT (2026-10-23): `listenAnyDot`/`listenPartnerButton`/`listenPartnerPopupCard` deleted —
    // no ANY option and no partner popup in the new single-source model (§2.1 picks the one shared source
    // inline, via chips, on the FOLLOW row below).
    /// §3's own details-row stepper — fill `#2a2d34`, radius 7, 16pt ‹/› zones, label(10pt)/value(13pt
    /// heavy) centred 2pt apart. §3: "A stepper whose mode isn't lit is drawn at 42% opacity and doesn't
    /// respond."
    private func listenStepper(_ label: String, value: String, enabled: Bool, width: CGFloat, height: CGFloat, onDec: @escaping () -> Void, onInc: @escaping () -> Void) -> some View {
        // §2.3: "− and + are at least 44 × 44 hit areas" — the drawn glyph stays its visual 16pt width (the
        // panel is too narrow to draw it at 44pt without crowding the value out), but the TAP target
        // extends invisibly to 44×44, centred on the glyph — the same overflow-hit-area technique the
        // RHYTHM tab's own restart buttons already use (adversarial-review fix: this was 16×height before).
        let padH: CGFloat = max(0, 44 - 16) / 2, padV: CGFloat = max(0, 44 - height) / 2
        let tapRect = CGRect(x: -padH, y: -padV, width: 16 + padH * 2, height: height + padV * 2)
        return HStack(spacing: 0) {
            Text("‹").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                .frame(width: 16, height: height)
                .contentShape(Rectangle().path(in: tapRect)).onTapGesture { if enabled { onDec() } }
            VStack(spacing: 2) {
                Text(label).font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                // `.minimumScaleFactor` removed (adversarial-review fix) — every value this stepper shows
                // (UNISON/−7TH.../100%/MUTE/MOVE) fits its 79.25pt width at 13pt comfortably.
                Text(value).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            Text("›").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                .frame(width: 16, height: height)
                .contentShape(Rectangle().path(in: tapRect)).onTapGesture { if enabled { onInc() } }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x2A2D34)))
        .opacity(enabled ? 1 : 0.42)
    }
    /// §6's own INTERVAL naming table — KEY source names it diatonically; CHORD/MIDI IN show the bare
    /// signed pool-step count.
    // LISTEN REBUILT (ferry 2026-10-23, "Fourfold Listen Tab") — §2/§6. REPLACES the whole old
    // listenTabContent/listenIntervalText/toggleListen* block above: one shared source lane for the tab
    // (§2.1's FOLLOW row), RHYTHM (OWN/COPY/FILL, §2.2-§2.3), PITCH (OWN/SHADOW/ECHO/AVOID, §2.4-§2.5),
    // footer (§2.6). `listenModeButton`/`listenStepper` (above) are reused as-is.

    /// §6.1: INTERVAL's value text — "UNISON", "3RD UP", "5TH DOWN". Unconditional now (not keyed off the
    /// lane's own SOURCE mode, unlike the old pool-step wording) — INTERVAL always names a scale degree in
    /// the header's own key, per §6.1-§6.2's general chromatic-note mover.
    private func listenIntervalText(_ v: Int) -> String {
        let names = ["UNISON", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH"]
        if v == 0 { return "UNISON" }
        return "\(names[min(6, abs(v))]) \(v > 0 ? "UP" : "DOWN")"
    }
    /// §3.7: FEEL's value text — "ON TIME" at 0, otherwise the existing TILT readout's own percent wording.
    private func listenFeelText(_ feel: Double) -> String {
        let pct = Int((feel * 100).rounded())
        return pct == 0 ? "ON TIME" : (pct > 0 ? "+\(pct)%" : "−\(-pct)%")
    }
    /// §3.6: DELAY's value text — "0 STEPS" at default, "1 STEP" singular.
    private func listenDelayText(_ n: Int) -> String { n == 1 ? "1 STEP" : "\(n) STEPS" }
    /// §2.1: one FOLLOW-row chip — a 9pt dot in the target lane's own colour, then its number. Selected
    /// (this lane's own source): "LANE n", the selected look in the SOURCE's colour. Disabled (the target
    /// already follows THIS lane, directly or through a chain): no fill, 1pt dashed border, muted text,
    /// "FOLLOWS YOU" — tapping it does nothing.
    private func listenFollowChip(_ idx: Int, target: Int, selected: Bool, disabled: Bool, width: CGFloat, height: CGFloat) -> some View {
        let targetAccent = laneAccents[target % laneAccents.count]
        return HStack(spacing: 4) {
            Circle().fill(disabled ? Color.clear : lane100(targetAccent)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(selected ? "LANE \(target + 1)" : "\(target + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).lineLimit(1)
                if disabled { Text("FOLLOWS YOU").font(.system(size: 10, weight: .bold, design: .monospaced)).lineLimit(1) }
            }
        }
        .foregroundColor(disabled ? Color(hex: 0x7C828D) : (selected ? patternSelectedText : patternUnselectedText))
        .frame(maxWidth: .infinity).frame(height: height)
        // §2.1: a disabled chip is "no fill" — not the same opaque fill a normal unselected chip gets
        // (adversarial-review fix: this used `patternUnselectedFill` for both).
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? lane20(targetAccent) : (disabled ? Color.clear : patternUnselectedFill)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(selected ? lane100(targetAccent) : (disabled ? Color(hex: 0x3A3E47) : Color.clear),
                          style: StrokeStyle(lineWidth: 1, dash: disabled ? [3, 2] : [])))
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { edit(idx) { $0.listenSource = target } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(disabled ? "Lane \(target + 1), follows this lane, unavailable" : "Follow lane \(target + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    /// §2.1: the whole FOLLOW row — label, then one chip per other lane.
    private func listenFollowRow(_ idx: Int, _ line: EuclidLine, fullWidth: CGFloat, height: CGFloat) -> some View {
        let labelW: CGFloat = 50, gap: CGFloat = 4
        let chipW = max(1, (fullWidth - labelW - gap * 3) / 3)
        let source = line.listenSourceResolved(ownLane: idx)
        let sources: [Int?] = (0..<4).map { i in
            let L = i < lines.count ? lines[i] : EuclidLine()
            return euclideousListenIsFollowing(rhythm: L.listenRhythmResolved, pitch: L.listenPitchResolved) ? L.listenSourceResolved(ownLane: i) : nil
        }
        let disabled = euclideousListenDisabledSources(lane: idx, sources: sources)
        return HStack(spacing: gap) {
            Text("FOLLOW").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)).frame(width: labelW, alignment: .leading).accessibilityHidden(true)
            ForEach((0..<4).filter { $0 != idx }, id: \.self) { target in
                listenFollowChip(idx, target: target, selected: source == target, disabled: disabled.contains(target), width: chipW, height: height)
            }
        }
        .frame(width: fullWidth, height: height)
    }
    /// §2.2: RHYTHM's OWN/COPY/FILL row.
    private func listenRhythmRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, height: CGFloat) -> some View {
        let labelW: CGFloat = 50, gap: CGFloat = 4
        let btnW = max(1, (fullWidth - labelW - gap * 3) / 3)
        let mode = line.listenRhythmResolved
        return HStack(spacing: gap) {
            Text("RHYTHM").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)).frame(width: labelW, alignment: .leading).accessibilityHidden(true)
            listenModeButton(name: "OWN", hint: "ITS OWN HITS", lit: mode == .own, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenRhythm = .own } }
            listenModeButton(name: "COPY", hint: "ITS HITS", lit: mode == .copy, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenRhythm = .copy } }
            listenModeButton(name: "FILL", hint: "ITS GAPS", lit: mode == .fill, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenRhythm = .fill } }
        }
        .frame(width: fullWidth, height: height)
    }
    /// §2.3: the RHYTHM panel — DELAY/FEEL (line 1), SPEED/DIRECTION (line 2). `#24262C`, radius matching
    /// the lane card's inner panels (12, the established value throughout this page), padding sp8,
    /// indented under the buttons (not the label column, hence `labelW` added to the leading inset).
    private func listenRhythmPanel(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, height: CGFloat) -> some View {
        let labelW: CGFloat = 50, pad: CGFloat = 8
        let w = max(1, fullWidth - labelW)
        let lineH = max(1, (height - pad * 3) / 2)
        let stepperW = max(1, (w - pad * 2 - 4) / 2)
        let speedW = max(1, (w - pad * 2 - 4) * 5 / 8), dirW = max(1, (w - pad * 2 - 4) * 3 / 8)
        return HStack(spacing: 0) {
            Color.clear.frame(width: labelW)
            VStack(spacing: pad) {
                HStack(spacing: 4) {
                    listenStepper("DELAY", value: listenDelayText(line.listenDelayResolved), enabled: true, width: stepperW, height: lineH,
                                  onDec: { edit(idx) { $0.listenDelay = max(0, $0.listenDelayResolved - 1) } },
                                  onInc: { edit(idx) { $0.listenDelay = $0.listenDelayResolved + 1 } })
                    listenStepper("FEEL", value: listenFeelText(line.listenFeelResolved), enabled: true, width: stepperW, height: lineH,
                                  onDec: { edit(idx) { $0.listenFeel = max(-1, $0.listenFeelResolved - 0.05) } },
                                  onInc: { edit(idx) { $0.listenFeel = min(1, $0.listenFeelResolved + 0.05) } })
                }
                HStack(spacing: 4) {
                    listenSpeedControl(idx, line, width: speedW, height: lineH)
                    listenDirectionControl(idx, line, accent, width: dirW, height: lineH)
                }
            }
            .padding(pad)
            .frame(width: w, height: height, alignment: .top)
        }
        .background(
            HStack(spacing: 0) { Color.clear.frame(width: labelW); RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x24262C)).frame(width: w) }
        )
        .frame(width: fullWidth, height: height)
    }
    /// §2.3 line 2: SPEED, a five-way ×¼ ×½ ×1 ×2 ×4 segmented control over the exponent −2…+2.
    private func listenSpeedControl(_ idx: Int, _ line: EuclidLine, width: CGFloat, height: CGFloat) -> some View {
        let order: [(Int, String, String)] = [(-2, "¼", "Quarter speed"), (-1, "½", "Half speed"), (0, "1", "Normal speed"), (1, "2", "Double speed"), (2, "4", "Quadruple speed")]
        let segW = max(1, (width - 4 * 3) / 5)
        return VStack(alignment: .leading, spacing: 2) {
            Text("SPEED · VS LANE \(line.listenSourceResolved(ownLane: idx) + 1)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)).lineLimit(1)
                .accessibilityHidden(true)
            HStack(spacing: 3) {
                ForEach(order, id: \.0) { exp, glyph, spoken in
                    let on = line.listenSpeedResolved == exp
                    Text("×\(glyph)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                        .frame(width: segW, height: max(1, height - 14))
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.white.opacity(0.14) : patternUnselectedFill))
                        .contentShape(Rectangle())
                        .onTapGesture { edit(idx) { $0.listenSpeed = exp } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }
    /// §2.3 line 2: DIRECTION — the SAME three chevrons the RHYTHM tab's own `directionRow` draws
    /// (< >< >), writing `listenDirection` instead of the lane's own `direction`.
    private func listenDirectionControl(_ idx: Int, _ line: EuclidLine, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let order: [(EuclidDir, String, String)] = [(.bkw, "<", "Backward"), (.pingpong, "><", "Ping-pong"), (.fwd, ">", "Forward")]
        let segW = max(1, (width - 4 * 2) / 3)
        return VStack(alignment: .leading, spacing: 2) {
            Text("DIRECTION").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                ForEach(order, id: \.0) { dir, glyph, spoken in
                    let on = line.listenDirectionResolved == dir
                    Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? patternSelectedText : patternUnselectedText)
                        .frame(width: segW, height: max(1, height - 14))
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? lane20(accent) : patternUnselectedFill))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { edit(idx) { $0.listenDirection = dir } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }
    /// §2.4: PITCH's OWN/SHADOW/ECHO/AVOID row.
    private func listenPitchRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, fullWidth: CGFloat, height: CGFloat) -> some View {
        let labelW: CGFloat = 50, gap: CGFloat = 4
        let btnW = max(1, (fullWidth - labelW - gap * 4) / 4)
        let mode = line.listenPitchResolved
        return HStack(spacing: gap) {
            Text("PITCH").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A)).frame(width: labelW, alignment: .leading).accessibilityHidden(true)
            listenModeButton(name: "OWN", hint: "ITS OWN RIFF", lit: mode == .own, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenPitch = .own } }
            listenModeButton(name: "SHADOW", hint: "ITS NOTE NOW", lit: mode == .shadow, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenPitch = .shadow } }
            listenModeButton(name: "ECHO", hint: "ITS LINE, IN TURN", lit: mode == .echo, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenPitch = .echo } }
            listenModeButton(name: "AVOID", hint: "MUTE ON ITS NOTE", lit: mode == .avoid, width: btnW, height: height, accent: accent) { edit(idx) { $0.listenPitch = .avoid } }
        }
        .frame(width: fullWidth, height: height)
    }
    /// §2.5: the PITCH panel — INTERVAL/OCTAVE, same panel look as §2.3.
    private func listenPitchPanel(_ idx: Int, _ line: EuclidLine, fullWidth: CGFloat, height: CGFloat) -> some View {
        let labelW: CGFloat = 50, pad: CGFloat = 8
        let w = max(1, fullWidth - labelW)
        let stepperW = max(1, (w - pad * 2 - 4) / 2)
        let stepperH = max(1, height - pad * 2)
        return HStack(spacing: 0) {
            Color.clear.frame(width: labelW)
            HStack(spacing: 4) {
                listenStepper("INTERVAL · \(euclideousKeyLabel(root: keyRoot, type: keyType))", value: listenIntervalText(line.listenIntervalResolved), enabled: true, width: stepperW, height: stepperH,
                              onDec: { edit(idx) { $0.listenInterval = max(-6, $0.listenIntervalResolved - 1) } },
                              onInc: { edit(idx) { $0.listenInterval = min(6, $0.listenIntervalResolved + 1) } })
                listenStepper("OCTAVE", value: euclideousSigned(line.listenOctaveResolved), enabled: true, width: stepperW, height: stepperH,
                              onDec: { edit(idx) { $0.listenOctave = max(-3, $0.listenOctaveResolved - 1) } },
                              onInc: { edit(idx) { $0.listenOctave = min(3, $0.listenOctaveResolved + 1) } })
            }
            .padding(pad)
            .frame(width: w, height: height, alignment: .top)
        }
        .background(
            HStack(spacing: 0) { Color.clear.frame(width: labelW); RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x24262C)).frame(width: w) }
        )
        .frame(width: fullWidth, height: height)
    }
    /// §2.6: the footer, pinned to the bottom of whatever room §2.1-§2.5 left (`euclideousListenTabLayout`
    /// drops it first under pressure, so by the time this is called `showFooter` is already decided true).
    private func listenFooter(fullWidth: CGFloat, height: CGFloat) -> some View {
        Text("Starts as an exact copy. Rhythm and Riff pause while borrowed; set a row to OWN to get yours back.")
            .font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundColor(Color(hex: 0xAAB0BA))
            .lineLimit(2).frame(width: fullWidth, height: height, alignment: .topLeading)
    }
    private func listenTabContent(_ idx: Int, _ line: EuclidLine, _ accent: Color, contentAreaH: CGFloat, fullWidth: CGFloat) -> some View {
        let rhythmPanelShown = line.listenRhythmResolved != .own
        let pitchPanelShown = line.listenPitchResolved == .shadow || line.listenPitchResolved == .echo
        let layout = euclideousListenTabLayout(contentAreaH: contentAreaH, rhythmPanelShown: rhythmPanelShown, pitchPanelShown: pitchPanelShown)
        return VStack(spacing: layout.gap) {
            listenFollowRow(idx, line, fullWidth: fullWidth, height: layout.followRowH)
            listenRhythmRow(idx, line, accent, fullWidth: fullWidth, height: layout.rhythmRowH)
            if rhythmPanelShown { listenRhythmPanel(idx, line, accent, fullWidth: fullWidth, height: layout.rhythmPanelH) }
            listenPitchRow(idx, line, accent, fullWidth: fullWidth, height: layout.pitchRowH)
            if pitchPanelShown { listenPitchPanel(idx, line, fullWidth: fullWidth, height: layout.pitchPanelH) }
            if layout.showFooter { listenFooter(fullWidth: fullWidth, height: layout.footerH) }
            Spacer(minLength: 0)
        }
        .frame(width: fullWidth, height: contentAreaH, alignment: .top)
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
    /// `pageBody`/`euclideousRiffRowH`).
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
    /// FOUR RIFFS (2026-10-18 ferry, restoring the 2026-10-14 tab row): tapping a tab makes it the
    /// active riff — both EDITED (the grid below) and SOUNDING (every lane reads `riffs[activeRiff]`
    /// directly, "ONE GLOBAL RIFF" ferry) — there is no separate "editing vs. playing" distinction left
    /// to track, since nothing switches riffs live underneath the page anymore. Long-press opens
    /// COPY/PASTE/CLEAR. The glyph is `riffMiniIcon`, unchanged since the 2026-10-14 icon-redesign ferry.
    /// RIFF PANEL ferry (2026-10-19) §2: four tabs, sp4 apart, each (inner width − 12) ÷ 4 wide and 20 TALL (`EuclideousRiffPanelMetrics.tabRowH`; was ≈29), radius 6.
    /// Fills, colours, tap, long-press and the labels are as before. Contents, centred as a GROUP: the playing triangle when this riff plays (5 × 6), 3pt, the
    /// number, 6pt, then the mini icon at its TAB size (21.7 × 12.8). SOURCE DIFFERENCES (reported): there was no triangle in the restored four-riff row (it went
    /// with the looper tabs, 8a4337e) — in today's one-riff model the ACTIVE riff is the only one that plays, so it is drawn there, in the pre-looper row's colour
    /// for the active tab (ink); and the number stays 9pt heavy (the ferry text says 10) because source wins on an existing type size.
    private func riffTabRow(height: CGFloat = EuclideousRiffPanelMetrics.tabRowH) -> some View {
        HStack(spacing: EuclideousRiffPanelMetrics.tabGap) {
            ForEach(0..<4, id: \.self) { i in
                let sel = i == max(0, min(3, activeRiff))
                let ink = Color(hex: 0x0D0F14)
                HStack(spacing: 0) {
                    if sel {
                        RiffPlayTriangle().fill(ink).frame(width: 5, height: 6)
                        Color.clear.frame(width: 3, height: 1)
                    }
                    Text("\(i + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? ink : Color(hex: 0xAAB0BA))
                    Color.clear.frame(width: 6, height: 1)
                    riffMiniIcon(ranks: i < riffs.count ? riffs[i].ranksResolved : [],
                                 noteColor: sel ? ink : Color(hex: 0xDFE3EA),
                                 dotColor: sel ? ink.opacity(0.3) : Color(hex: 0x4A4E57),
                                 style: .tab)
                }
                .frame(maxWidth: .infinity).frame(height: height)
                .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                .contentShape(Rectangle())
                .onTapGesture { onSetActiveRiff(i) }
                .onLongPressGesture(minimumDuration: 0.5) { riffTabMenuLane = i }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Riff \(i + 1)\(sel ? ", editing" : "")")
            }
        }
    }
    /// The playing triangle: 5 wide, 6 tall, pointing right.
    private struct RiffPlayTriangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
        }
    }
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
            Text("RIFF \(idx + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            row("COPY") {
                riffClipboard = idx < riffs.count ? riffs[idx] : nil
                riffTabMenuLane = nil
            }
            row("PASTE", enabled: riffClipboard != nil) {
                guard let c = riffClipboard else { return }
                onEditRiffs { r in guard idx < r.count else { return }; r[idx] = c }
                riffTabMenuLane = nil
            }
            row("CLEAR") {
                onEditRiffs { r in guard idx < r.count else { return }; r[idx] = .empty }
                riffTabMenuLane = nil
            }
        }
        .padding(16).frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    private func riffGridView(box: CGSize) -> some View {
        let n = 8
        let ranks = effectiveGridRanks
        // RIFF PANEL ferry (2026-10-19) §1/§8.1: the panel's inside comes from ONE pure function of the box the page gives it — the tab row, the grid's cell
        // width and height (the cell is still the smaller of its width- and height-derived candidate, "keeping them square"), the rails block below.
        let layout = euclideousRiffPanelLayout(box: box)
        let cellW = layout.cellW
        let cellH = layout.cellH
        let source = noteSource
        let pool = riffLivePool
        // LIVE STATE (rule, "Live states" §1): MIDI IN with nothing held — no arrows anywhere on the grid. An empty pool means NO rank can resolve a note at all,
        // so the ARROWS are suppressed outright below; the RAILS keep drawing (RIFF PANEL ferry §6.4).
        let midiEmpty = source == .midi && pool.isEmpty
        // RIFF PANEL ferry: the arrows and rails re-derive from the lanes' walk plans EVERY FRAME in `riffPanelOverlay`; this snapshot (taken at body evaluation) feeds only
        // the static VoiceOver text — the cells' arrow phrases and each rail's label. The played sets come from the riff ferry's readout (what the mini-grid dims), once per body.
        let beatNow = walkTagBeat(at: Date())
        let frameNow = riffLaneFrames(ranks: ranks, beat: beatNow)
        let arrowsNow: [EuclideousArrowCell] = midiEmpty ? [] : riffArrowCells(frameNow)
        let playedNow: [Set<Int>] = (0..<4).map { i in
            i < lines.count ? euclideousRailPlayedColumns(length: lines[i].riffLengthResolved, shift: lines[i].riffRotateResolved, neverPlay: riffReadout(i)?.neverPlay ?? []) : []
        }
        let railLabels: [String] = (0..<4).map { i in
            guard let f = frameNow.first(where: { $0.lane == i }) else { return "Lane \(i + 1): riff off" }
            let w = riffRailInputs(f)
            return euclideousAppendSilencedBySolo(euclideousRailAccessibilityLabel(lane: i, riffOn: f.riffOn, running: f.running, played: playedNow[i], current: w.current, heading: w.heading, muted: f.muted), silenced: f.soloSilenced)
        }
        return VStack(alignment: .leading, spacing: 0) {
            riffTabRow(height: layout.tabRowH)
            Color.clear.frame(height: EuclideousRiffPanelMetrics.tabToGrid)
            HStack(spacing: sp4) {
                riffNoteLabelColumn(pool: pool, source: source, cellH: cellH, labelW: layout.labelW)
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
                                    riffGridCell(col: col, rank: rank, ranks: ranks, cellW: cellW, cellH: cellH, n: n, arrows: arrowsNow)
                                }
                            }
                        }
                    }
                    // (The walk tags and their threads were drawn here as an overlay; the RIFF PANEL ferry replaced them with `riffPanelOverlay`'s arrows — see below.)
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
                        }.onEnded { _ in
                            riffDragLastCell = nil
                        })
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
            Color.clear.frame(height: EuclideousRiffPanelMetrics.gridToRails)
            // The four lane rails draw in `riffPanelOverlay`; here, in the rails' own place after the grid (VoiceOver §7.3: the tabs, the grid, then rails 1 to 4), each is ONE static
            // element carrying its label.
            VStack(spacing: EuclideousRiffPanelMetrics.railGap) {
                ForEach(0..<4, id: \.self) { i in
                    Color.clear.frame(height: EuclideousRiffPanelMetrics.railH)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(railLabels[i])
                }
            }
            .frame(height: EuclideousRiffPanelMetrics.railsH)
        }
        .padding(sp8)
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
        .overlay(alignment: .topLeading) { riffPanelOverlay(layout: layout, ranks: ranks, suppressArrows: midiEmpty, played: playedNow) }
    }

    // MARK: - RIFF PANEL ferry (2026-10-19): the blended ARROWS and the lane RAILS
    //
    // Each lane's walk TAG (a corner glyph plus a next-step thread) is replaced by ONE big arrow centred on the note it is playing; lanes on the same note share one arrow.
    // Everything is derived EVERY FRAME from the lanes' walk plans — the same plans, polls and rules the tags used (`euclideousWalkTagPlan`, `riffPositions`,
    // `riffWalkState`, the LANES-grid mute) — plus the per-lane strike feed (`strikeEvents`) for the flare, the comet bar's own afterglow timing. No new poll, no
    // state kept: a pure function of the beat. The tag code (`riffWalkTagOverlay`, `drawWalkTag`, `drawWalkThread`, the painter and `euclideousTagDrawing`) stays,
    // unused ("hide, don't delete").

    /// One lane's inputs for one frame.
    private struct RiffLaneFrame {
        let lane: Int
        let cfg: EuclideousWalkLaneConfig
        let riffOn: Bool            // the riff is on and the lane isn't SHADOWing (a SHADOW lane's own riff is overridden entirely)
        let running: Bool           // the transport runs and the lane isn't stopped
        let muted: Bool             // the LANES grid has this lane muted at this beat
        let soloSilenced: Bool      // LANE SOLO: the solo mask silences this lane (the marker dims like a muted lane's; the words differ)
        var dimmed: Bool { muted || soloSilenced }   // ONE 42 %, never both multiplied
        let flare: Double           // 0…1, the comet bar's burst + afterglow since the lane's latest real strike
        let plan: EuclideousWalkTagPlan?
    }
    /// PULSE §4: lane `lane`'s riff strike as the riff panel shows it — the flash f of its latest riff strike that has happened by `now` (a reference-date time), scaled by the played velocity and P, and the
    /// grid row the engine reported for it. nil when nothing is flaring. A gap hit makes no strike, so it never appears here (2.4).
    private func riffPulse(_ lane: Int, now: Double) -> (f: Double, rank: Int, lane: Int)? {
        let p = euclideousPulseScale(level: pulseLevel)
        guard p > 0, let s = pulseFeed.latestHappened(lane: lane, now: now, riff: true) else { return nil }
        let env = euclideousPulseEnvelopes(velocity: Int(s.riffVel), seconds: now - s.onsetAt, scale: p)
        guard env.f >= 0.01 else { return nil }
        if soloSilenced(lane) { return nil }   // LANE SOLO: a silenced lane makes no strikes, and one it made just before the solo stops flaring at once
        // 4.6 / 1.6: a lane the LANES grid has muted at this moment shows no flare (a strike it made just before the mute stops fading in its arrow, its note cell and its name). Looked up only while something flares.
        if let cfg = riffWalkConfig(lane), !euclideousLaneAudible(beat: lanesMusicalBeat(real: walkTagBeat(at: Date(timeIntervalSinceReferenceDate: now))), cells16: cfg.muteCells, unitBeats: cfg.muteUnitBeats) { return nil }
        return (env.f, Int(s.rank), lane)
    }
    private func riffLaneFrames(ranks: [Int], beat: Double, now: Double = Date().timeIntervalSinceReferenceDate) -> [RiffLaneFrame] {
        let spb = 60.0 / max(1.0, clock.tempo)
        return (0..<4).compactMap { i -> RiffLaneFrame? in
            guard i < lines.count else { return nil }
            // §11.2: while this lane's picture is held, the riff panel follows the ORIGINAL it's playing,
            // not the live (possibly still-undecided-roll) document — a one-off recompute bypassing
            // `riffWalkConfig`'s memoised cache (only paid while a hold gesture is actually active).
            let heldOriginal: EuclidLine? = (euclideousRandomMode && euclideousRandomHeldLane == i)
                ? euclideousRandomRolls[i][euclideousRandomTab[i].rawValue].original : nil
            let cfg: EuclideousWalkLaneConfig?
            if let o = heldOriginal {
                var subs = lines; subs[i] = o
                let cyc = clock.stepBeats * Double(max(1, clock.cols))
                cfg = euclideousWalkLaneConfig(lane: i, lines: subs, cyc: cyc, resetSpanBars: resetSpanBars,
                                                lanesSeqRate: lanesSeq.rate, lanesSeqLen: lanesSeq.len, lanesSeqOn: lanesSeq.on, lanesSeqCells: lanesSeq.cells, fx: fx,
                                                swingPercent: clock.swing, stepBeats: clock.stepBeats, beatsPerBar: clock.beatsPerBar, tempo: clock.tempo)
            } else {
                cfg = riffWalkConfig(i)
            }
            guard let cfg else { return nil }
            let line = heldOriginal ?? lines[i]
            // `walkTagShows(i)`'s own test, inlined against the override-aware `line` above (that function
            // reads `lines[i]` directly, which would bypass the held-original substitution).
            let riffOn = euclideousLanePlaysRiff(line)
            let running = euclideousLaneIsRunning(transportPlaying: clock.playing, line: line)
            let muted = !euclideousLaneAudible(beat: lanesMusicalBeat(real: beat), cells16: cfg.muteCells, unitBeats: cfg.muteUnitBeats)
            let flare = riffPulse(i, now: now)?.f ?? 0   // PULSE §4.1: velocity-scaled flash of the lane's latest riff strike (was the comet bar's step-based flare)
            // `running` is NOT gated on the mute: a muted hit still advances the walk, and the arrow / rail stay on it (dimmed to 42%).
            // a lane that is not RUNNING (its PLAY / STOP off, 0 HITS, or the transport stopped) has no arrow: the engine keeps its last step, and an arrow resting on it read as a lane still walking
            let plan = (euclideousLaneArrowShows(riffOn: riffOn, running: running) && i < riffPositions.count)
                ? euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: spb, polledStep: riffPositions[i], running: running,
                                        polledOrdinal: i < riffWalkState.count ? riffWalkState[i] : nil)
                : nil
            return RiffLaneFrame(lane: i, cfg: cfg, riffOn: riffOn, running: running, muted: muted, soloSilenced: soloSilenced(i), flare: flare, plan: plan)
        }
    }
    /// The arrows' cells: each lane's seat (`euclideousLaneArrowState`), grouped by the cell they share.
    private func riffArrowCells(_ frames: [RiffLaneFrame]) -> [EuclideousArrowCell] {
        euclideousArrowCells(frames.compactMap { f in
            f.plan.map { euclideousLaneArrowState(lane: f.lane, cfg: f.cfg, plan: $0, polledOrdinal: f.lane < riffWalkState.count ? riffWalkState[f.lane] : 0) }
        })
    }
    /// A rail's current column, its trail and its heading — only while the lane runs and its latest hit is known (a stopped lane or transport, or a lane before its first hit,
    /// has none).
    private func riffRailInputs(_ f: RiffLaneFrame) -> (current: Int?, trail: [Int], heading: EuclideousArrowHeading) {
        guard f.riffOn, f.running, let tick = f.plan?.landedTick else { return (nil, [], .still) }
        let w = euclideousRailWalk(cfg: f.cfg, hitTick: tick)
        return (w.current, w.trail, euclideousArrowHeading(riffDir: f.cfg.riffDir, length: f.cfg.length, stride: f.cfg.stride, every: f.cfg.every, ordinal: w.ordinal))
    }
    private func riffPanelOverlay(layout: EuclideousRiffPanelLayout, ranks: [Int], suppressArrows: Bool, played: [Set<Int>]) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pulseLive)) { tl in
            let beat = walkTagBeat(at: tl.date)
            let frames = riffLaneFrames(ranks: ranks, beat: beat, now: tl.date.timeIntervalSinceReferenceDate)
            let cells = suppressArrows ? [] : riffArrowCells(frames)
            ZStack(alignment: .topLeading) {
                ForEach(cells.indices, id: \.self) { k in
                    let cell = cells[k]
                    let members = cell.members.map { m -> EuclideousArrowLane in
                        let f = frames.first(where: { $0.lane == m.lane })
                        return EuclideousArrowLane(lane: m.lane, heading: m.heading, muted: f?.dimmed ?? false, flare: f?.flare ?? 0)
                    }
                    if let spec = euclideousArrowSpec(cellW: layout.cellW, cellH: layout.cellH, members: members, hollow: cell.hollow) {
                        let cf = layout.cellFrame(column: cell.column, rank: cell.rank)
                        // PULSE §4.2: the light note cell under a flaring arrow takes a lane100 overlay at 80% × f (the strongest flaring lane in it), drawn under the arrow; the cell's own colour
                        // returns as f falls. A hollow (rest-cell) arrow has no light cell to tint.
                        if !cell.hollow, let top = members.max(by: { $0.flare < $1.flare }), top.flare > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(laneAccents[top.lane % laneAccents.count].opacity(0.8 * top.flare))
                                .frame(width: cf.width, height: cf.height).offset(x: cf.minX, y: cf.minY)
                        }
                        EuclideousArrowView(spec: spec)
                            .offset(x: cf.midX - spec.size.width / 2, y: cf.midY - spec.size.height / 2)
                    }
                }
                EuclideousRailsView(layout: layout, rails: (0..<4).map { i in
                    let f = frames.first(where: { $0.lane == i })
                    let w = f.map(riffRailInputs) ?? (nil, [], EuclideousArrowHeading.still)
                    return euclideousRailSpec(lane: i, riffOn: f?.riffOn ?? false, running: f?.running ?? false, muted: f?.dimmed ?? false,
                                              played: i < played.count ? played[i] : [], current: w.0, trail: w.1, heading: w.2, flare: f?.flare ?? 0)
                })
            }
        }
        .frame(width: layout.box.width, height: layout.box.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // paint only: the arrows are spoken in their cells' labels and each rail by its own static element (§7)
    }
    /// Rule 2, literal: one label per rank row, right-aligned, 11pt bold `#dfe3ea`, rank 8 at top (matching
    /// the grid's own `(1...8).reversed()` order so a label never lands beside the wrong rank). An empty
    /// pool (MIDI IN, nothing held) shows "–" in `#4A4E57` on every row (Live states §1) instead of a note
    /// name. "For MIDI IN and CHORD, spell flats by default" (rule 2) — only KEY keeps the existing
    /// root-driven sharp/flat choice (`euclideousKeyIsFlat`).
    /// PULSE §4.3: the row of a flaring arrow draws its name in lane100 while f > 0.12, with a text glow of blur 10 × f (radius 5 × f) at f; the strongest lane wins a row. Its own small TimelineView (eight Texts)
    /// reading the same feed the arrows read — nothing is re-derived.
    private func riffNameLights(now: Double) -> [Int: (colour: Color, f: Double)] {
        var out: [Int: (colour: Color, f: Double)] = [:]
        for lane in 0..<4 {
            guard let s = riffPulse(lane, now: now), (1...8).contains(s.rank), euclideousPulseNameLit(f: s.f) else { continue }
            if (out[s.rank]?.f ?? 0) < s.f { out[s.rank] = (laneAccents[lane % laneAccents.count], s.f) }
        }
        return out
    }
    private func riffNoteLabelColumn(pool: [UInt8], source: EuclideousLaneSource, cellH: CGFloat, labelW: CGFloat) -> some View {
        // The names and their VoiceOver words are worked out ONCE per body; the TimelineView only decides which rows are lit this frame.
        let extended = euclideousGlobalPoolExtended(sortedRaw: pool.map { Int($0) })
        let rows: [(rank: Int, label: String, hasNote: Bool, isReal: Bool, spoken: String)] = (1...8).reversed().map { rank in
            let hasNote = rank <= extended.count
            let noteValue = hasNote ? UInt8(extended[rank - 1]) : 0
            return (rank, hasNote ? euclideousDisplayNoteName(noteValue, source: source, pool: pool, keyRoot: keyRoot, keyType: keyType) : "–", hasNote, rank <= pool.count,
                    hasNote ? "Rank \(rank), \(euclideousAccessibleDisplayNoteName(noteValue, source: source, pool: pool, keyRoot: keyRoot, keyType: keyType))" : "Rank \(rank), no note")
        }
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pulseLive)) { tl in
            riffNoteLabelColumnBody(rows: rows, cellH: cellH, labelW: labelW, lights: riffNameLights(now: tl.date.timeIntervalSinceReferenceDate))
        }
    }
    private func riffNoteLabelColumnBody(rows: [(rank: Int, label: String, hasNote: Bool, isReal: Bool, spoken: String)], cellH: CGFloat, labelW: CGFloat, lights: [Int: (colour: Color, f: Double)]) -> some View {
        // (the note names — octave-extended, real-vs-copy dimming, spelled relative to the held chord, "–" with nothing held — are built once in `riffNoteLabelColumn`; see the 2026-10-13 and 2026-10-14 notes in git history)
        return VStack(spacing: sp4) {
            ForEach(rows, id: \.rank) { row in
                Text(row.label).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(lights[row.rank]?.colour ?? (row.hasNote ? (row.isReal ? Color(hex: 0xDFE3EA) : Color(hex: 0xDFE3EA).opacity(0.55)) : Color(hex: 0x4A4E57)))
                    .shadow(color: lights[row.rank].map { $0.colour.opacity($0.f) } ?? .clear, radius: lights[row.rank].map { 5 * CGFloat($0.f) } ?? 0)
                    .frame(width: labelW, height: cellH, alignment: .trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
            }
        }
        .frame(width: labelW)
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
        // FOUR RIFFS (2026-10-14 ferry §7): the grid always edits WHICHEVER tab is active — mutate
        // exactly that one slot of the 4-element array, leaving the other 3 riffs untouched.
        let idx = max(0, min(3, activeRiff))
        onEditRiffs { riffs in
            guard idx < riffs.count else { return }
            var r = riffs[idx]
            var rr = (0..<n).map { k -> Int in let rv = r.ranksResolved; return k < rv.count ? rv[k] : 0 }
            if col < rr.count { rr[col] = (toggle && rr[col] == rank) ? 0 : rank }
            r.ranks = rr; r.steps = n
            riffs[idx] = r
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

    /// RHYTHM POLISH §3.1: for a lane with hit timing (a fractional OFFSET and/or a fine TILT), the step boxes with each hit in the box its START TIME falls in — nil for every other lane (the bar draws from the line as ever).
    private func laneTimingBoxes(_ idx: Int, _ line: EuclidLine) -> [Bool]? {
        guard let cfg = riffWalkConfig(idx), !cfg.timing.isNone else { return nil }
        let n = euclideousEffectiveHitPattern(lane: idx, lines: lines)?.n ?? max(2, min(16, line.steps))
        return euclideousHitBoxes(layoutCells: cfg.buf, n: n, dir: line.directionResolved)
    }
    /// RIFF WALK ferry §3/§7: one lane's walk config, unconditionally (the WALK strip and the mini-grid's
    /// dim rule need it regardless of `walkTagShows` — they're drawn even while the riff is off, at 42%).
    private func riffWalkConfig(_ idx: Int) -> EuclideousWalkLaneConfig? {
        guard idx >= 0, idx < lines.count else { return nil }
        let cyc = clock.stepBeats * Double(max(1, clock.cols))
        return euclideousWalkLaneConfig(lane: idx, lines: lines, cyc: cyc, resetSpanBars: resetSpanBars,
                                        lanesSeqRate: lanesSeq.rate, lanesSeqLen: lanesSeq.len, lanesSeqOn: lanesSeq.on, lanesSeqCells: lanesSeq.cells, fx: fx,
                                        swingPercent: clock.swing, stepBeats: clock.stepBeats, beatsPerBar: clock.beatsPerBar, tempo: clock.tempo)
    }
    /// The readout for lane `idx`'s current riff settings (§7), nil when over budget. MEMOISED on its inputs (§7.2's own ask; `EuclideousRiffReadoutCache`): the lane card's mini-grid,
    /// its WALK strip and the riff panel's rails all read it on every body evaluation, but it is only recomputed when a lane's pattern, rate, chains or riff settings change.
    private func riffReadout(_ idx: Int) -> EuclideousRiffReadout? {
        guard let c = riffWalkConfig(idx) else { return nil }
        return riffReadoutCache.readout(lane: idx, cfg: c)
    }
    /// The UI clock's beat at `date` — the same `anchor + elapsed × tempo` extrapolation every other live view on
    /// this page uses (frozen at the anchor while the transport is stopped).
    /// PULSE §9.1: the strike effects keep their TimelineViews running while the page plays AND for the 1.5 s after it stops (the decays and the marks' fade), then idle. `pulseSettleTick` is bumped once
    /// when that window ends so the body re-evaluates and the views pause.
    private var pulseLive: Bool { _ = pulseSettleTick; return clock.playing || pulseFeed.isSettling(now: Date()) }   // reading the tick is what makes its bump re-evaluate the body
    private func walkTagBeat(at date: Date) -> Double {
        clock.playing ? clock.anchor + date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0 : clock.anchor
    }
    /// A REAL (swung) beat as the engine's MUSICAL beat — mute cells, restart cells and the roll are all in the engine's musical (un-swung) beats, so
    /// the playheads, the window and the mute dimming read this instead of the raw UI clock (identity at 50% swing).
    private func lanesMusicalBeat(real: Double) -> Double {
        let a = min(75, max(50, clock.swing)) / 50.0
        return a == 1 ? real : musicalOf(real, stepBeats: max(0.03125, clock.stepBeats), a: a)
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
    private func riffGridCell(col: Int, rank: Int, ranks: [Int], cellW: CGFloat, cellH: CGFloat, n: Int, arrows: [EuclideousArrowCell] = []) -> some View {
        let on = col < ranks.count && ranks[col] == rank
        let here = arrows.first { $0.column == col && $0.rank == rank }
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
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
        .accessibilityLabel({
            let noteName = (rank >= 1 && rank <= riffLivePool.count) ? euclideousDisplayNoteName(riffLivePool[rank - 1], source: noteSource, pool: riffLivePool, keyRoot: keyRoot, keyType: keyType) : nil
            guard let here else { return noteName.map { "Step \(col + 1), \($0)" } ?? "Step \(col + 1), rank \(rank)" }   // a cell no lane sits on used to be blank (an unlabelled element); now it says which cell it is
            let stepPart = noteName.map { "Step \(col + 1), \($0)" } ?? "Step \(col + 1)"
            // RIFF PANEL ferry §7.1: after its label, the arrow's lanes and headings — ", lane 1 heading right" / ", lanes 2 and 3: 2 heading left, 3 heading right" /
            // ", lane 1 heading right, on a rest". (This replaces the tag's "lane 1 here, next up".)
            return stepPart + euclideousArrowCellPhrase(members: here.members.map { EuclideousArrowMember(lane: $0.lane, heading: $0.heading) }, onRest: here.hollow)
        }())
        // The grid is edited by ONE drag overlay (touch only), so a VoiceOver user had no way to set a note at all. Activating a cell does what a tap on it does: set this column to this rank, or clear it if it is already there.
        .accessibilityValue(on ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { riffSetRank(col: col, rank: rank, n: n, toggle: true) }
    }


    // MARK: - SEQUENCER PANEL (2026-10-14 ferry) — REPLACES the NOTE VIEW panel above (same size/position at
    // both call sites, the page body just swaps which function it calls). Two tabs:
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
    private func sequencerPanel(maxWidth: CGFloat, maxHeight: CGFloat, fxAvailable: Bool = false) -> some View {
        // FX TAB: offered in both orientations since the PAGE LAYOUT ferry (2026-10-19) — in portrait this panel sits BESIDE the riff panel at the same width, so each FX
        // column takes the riff grid's column width and the same offset from its own panel's leading edge (§10.3, by construction); `fxAvailable` stays a parameter.
        let tab: EuclideousSeqTab = (sequencerTab == .fx && !fxAvailable) ? .mix : sequencerTab
        let innerW = max(1, maxWidth - sp8 * 2)
        let innerH = max(1, maxHeight - sp8 * 2)
        let tabBody = euclideousSeqTabBodySize(panelWidth: maxWidth, panelHeight: maxHeight)   // LANES' and FX's area: one function, shared with the page's floor list
        let tabRowH = EuclideousMixMetrics.tabRowH
        // LANES' own bottom bar (OFF/RATE/LEN) was PANEL CHROME drawn under every tab; it now belongs to the LANES tab alone (MIX ferry §2.2),
        // so MIX gets the whole grid area. LANES keeps its exact geometry: tab row, sp4, grid, sp4, controls row.
        // Controls row was ~33pt against the ferry's own 44 (2026-10-14 fixes-after-build ferry §1) — the
        // ratio to the reference panel (307 total) is roughly 44/307 ≈ 0.143; applied proportionally here
        // rather than a literal 44, same convention as every other size on this page.
        let controlsRowH: CGFloat = max(1, innerH * 44 / 307)
        let gridH = max(1, innerH - tabRowH - controlsRowH - sp4 * 2)
        let mixH = max(1, innerH - tabRowH - sp8)
        return VStack(spacing: tab == .mix ? sp8 : sp4) {
            sequencerTabRow(width: innerW, height: tabRowH, fxAvailable: fxAvailable, selected: tab)
            switch tab {
            case .mix:
                mixGrid(width: innerW, height: mixH)
            case .lanes:
                lanesTab(width: tabBody.width, height: tabBody.height)   // LANES GRID (2026-10-18): replaces the old step grid + ON/RATE/LEN row
            case .fx:
                fxTab(width: tabBody.width, height: tabBody.height)
            case .riffs:   // hidden (unreachable from the tab row) — kept so its code stays compiled
                VStack(spacing: sp4) {
                    sequencerRiffsGrid(width: innerW, height: gridH).frame(width: innerW, height: gridH)
                    sequencerControlsRow(width: innerW, height: controlsRowH)
                }
            }
        }
        .padding(sp8)
        .frame(width: maxWidth, height: maxHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }
    /// Tab row — TABS ONLY (MIX ferry 2026-10-18 §1): MIX, then LANES (RIFFS stays hidden), equal widths across the content width sp4 apart
    /// (198.5 each at the reference panel). Each tab is 20 tall: a 12pt heavy label centred in the top 16, a 2pt bar along the bottom edge
    /// (#FFFFFF selected, #2A2D34 not), label #F2F4F7 selected / #AAB0BA not. LANES keeps its on/off dot (filled when its sequencer is ON,
    /// hollow when OFF); MIX has none. The old trailing readout is GONE — "STEP n OF LEN" (the LANES grid's lit column and bold step number
    /// already show the step) and, sharing its slot, the RESET-hold hint "TAP = RESTART" (RESET's gesture and restart marks are unchanged).
    private func sequencerTabRow(width: CGFloat, height: CGFloat, fxAvailable: Bool, selected: EuclideousSeqTab) -> some View {
        let tabs = EuclideousSeqTab.visible(fxAvailable: fxAvailable)
        let tabW = euclideousSeqTabWidth(count: tabs.count, contentWidth: width)
        // §10.2: while the panel is showing a tab OTHER than MIX, a routed output's ring goes around the MIX
        // tab chip itself instead of any per-lane button (`outputRingTargets(panelShowsMix:)` already decides
        // this; the panel being on screen at all is this whole row's own precondition, so §10.5 is automatic).
        let ring = selected == .mix ? nil : outputRingTargets(panelShowsMix: false)
        return HStack(spacing: sp4) {
            ForEach(tabs, id: \.rawValue) { tab in
                let sel = selected == tab
                let ringedHere = tab == .mix && ring?.targets.contains(.mixTab) == true
                // The on/off ring beside LANES is gone with the ON switch (LANES GRID, 2026-10-18): the grid is always live.
                ZStack(alignment: .bottom) {
                    HStack(spacing: 6) {
                        Text(tab.label).font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(sel ? Color(hex: 0xF2F4F7) : Color(hex: 0xAAB0BA)).lineLimit(1)
                    }
                    .frame(width: tabW, height: height - 4, alignment: .center)   // centred in the top 16pt
                    .frame(width: tabW, height: height, alignment: .top)
                    Rectangle().fill(sel ? Color(hex: 0xFFFFFF) : Color(hex: 0x2A2D34)).frame(width: tabW, height: 2)
                }
                .frame(width: tabW, height: height)
                .overlay { if ringedHere, let r = ring { EuclideousOutputCueRing(kind: .tab, held: r.held, reduceMotion: reduceMotion).id(r.token) } }
                .zIndex(ringedHere ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    sequencerTab = tab
                    resetPopupLane = nil   // §6: "switching tabs closes it"
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab == .fx ? "FX" : tab.label.capitalized)   // §14.1: the tab is read "FX", not "Fx"
                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)   // SwiftUI has no tab trait; button + selected, like the lane tabs
            }
        }
        .frame(width: width, height: height)
    }
    // MARK: - THE LANES TAB (LANES GRID ferry, 2026-10-18)
    /// MUTE | RESTART, four lane blocks of 16 cells, a roll behind them and a playhead per lane — all painted by `EuclideousLanesPanel`
    /// (LanesPanelPainter.swift) from the pure layer in Derivations.swift. This page supplies the data (each lane's grid resolved exactly as the
    /// engine resolves it, the cached roll feed) and the edits (one undo step per stroke or rate-box tap). A `TimelineView` at 4 Hz only
    /// re-evaluates the window the roll covers; the playheads animate in their own layer.
    private func lanesTab(width: CGFloat, height: CGFloat) -> some View {
        let layout = euclideousLanesLayout(width: width, height: height)
        return TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            EuclideousLanesPanel(layout: layout, lanes: lanesPanelLanes(beat: lanesMusicalBeat(real: walkTagBeat(at: tl.date))), accents: laneAccents,
                                 playing: clock.playing, beatAt: { lanesMusicalBeat(real: walkTagBeat(at: $0)) },
                                 onRateTap: { lane in lanesRateTap(lane) },
                                 cellValue: { hit in lanesCellValue(hit) },
                                 onApply: { hit, value, first in lanesApply(hit, value, first: first) },
                                 onToggle: { hit in lanesApply(hit, !lanesCellValue(hit), first: true) })
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
    /// The four lanes' MUTE data at `beat` (RESTART CHAINS ferry §8: the panel is mute-only now — restarts are
    /// set on each lane's own RHYTHM tab, §6). The roll feed is cached per lane and recomputed only when one of
    /// its inputs changes (the lane's settings and its neighbours', the riff, the unit, the window, the bar,
    /// the tempo) or the window wraps — never per frame. The read-only rhythm/melody marks (§8.3) now come
    /// from each lane's resolved CHAINS, not the retired masks.
    private func lanesPanelLanes(beat: Double) -> [EuclideousLanesPanelLane] {
        let ranks = effectiveGridRanks   // the riff that is playing — the SAME read the footer and the grid use
        let cyc = clock.stepBeats * Double(max(1, clock.cols))
        return (0..<4).map { lane in
            let v = euclideousLaneGridView(lines: lines, lane: lane, legacy: lanesSeq, defaultRateBeats: 0.25, beatsPerBar: clock.beatsPerBar)
            let unit = v.muteUnitBeats
            let win = euclideousLanesWindow(beat: beat, unitBeats: unit)
            let key = EuclideousLanesRollCache.Key(lines: lines, lanesSeq: lanesSeq, ranks: ranks, windowStart: win.start, unit: unit, restartTab: false,
                                                    beatsPerBar: clock.beatsPerBar, tempo: clock.tempo, swing: clock.swing, fx: fx)
            let roll = lanesRollCache.roll(lane: lane, key: key) {
                guard let cfg = euclideousWalkLaneConfig(lane: lane, lines: lines, cyc: cyc, resetSpanBars: resetSpanBars, lanesSeqRate: lanesSeq.rate,
                                                          lanesSeqLen: lanesSeq.len, lanesSeqOn: lanesSeq.on, lanesSeqCells: lanesSeq.cells, fx: fx,
                                                          swingPercent: clock.swing, stepBeats: clock.stepBeats, beatsPerBar: clock.beatsPerBar,
                                                          tempo: clock.tempo) else { return [] }
                return euclideousLaneRollHits(cfg: cfg, windowStart: win.start, windowBeats: win.length, minGateBeats: 0.005 * clock.tempo / 60.0) { column, _ in
                    column >= 0 && column < ranks.count ? ranks[column] : 0
                }
            }
            let line = lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all)
            let rhythmChain = EuclideousRestartChain.from(line.restartRhythmBars ?? [])
            let melodyChain = EuclideousRestartChain.from(line.restartMelodyPasses ?? [])
            let lapBeats = Double(v.cycleLen) * v.sub
            let rhythmMarks = euclideousChainRhythmMarkBeats(chain: rhythmChain, barBeats: clock.beatsPerBar, windowStart: win.start, windowBeats: win.length)
            let melodyMarks = euclideousChainMelodyMarkBeats(melodyChain: melodyChain, rhythmChain: rhythmChain, barBeats: clock.beatsPerBar,
                                                             lapBeats: lapBeats, windowStart: win.start, windowBeats: win.length)
            return EuclideousLanesPanelLane(grid: v.grid, unitLabel: v.grid.muteUnit.label, unitBeats: unit,
                                            windowStart: win.start, roll: roll, rhythmMarkBeats: rhythmMarks, melodyMarkBeats: melodyMarks,
                                            silenced: soloSilenced(lane))   // LANE SOLO §6.4: the block (rail, cells, roll, marks, playhead) at 42 %
        }
    }
    private func lanesGridView(_ lane: Int) -> EuclideousLaneGridView {
        euclideousLaneGridView(lines: lines, lane: lane, legacy: lanesSeq, defaultRateBeats: 0.25, beatsPerBar: clock.beatsPerBar)
    }
    private func lanesCellValue(_ hit: EuclideousLanesHit) -> Bool {
        euclideousLaneGridCellValue(lanesGridView(hit.lane).grid, restart: false, melody: hit.row == 1, cell: hit.cell)
    }
    /// One cell edit. `first` opens the stroke's single undo step (`editStep`'s `newStep`); the lane's resolved grid is read at touch-down and the
    /// first write pins all five fields from it, so a pre-feature lane's migrated values become its stored values.
    private func lanesApply(_ hit: EuclideousLanesHit, _ value: Bool, first: Bool) {
        let resolved = lanesGridView(hit.lane).grid
        editStep(hit.lane, first) { euclideousApplyLaneGridOp(&$0, resolved: resolved, .mute(cell: hit.cell, on: value)) }
    }
    /// The rate box: tap cycles muteUnit (STEP → 4STP → PASS → 2PASS → STEP). RESTART CHAINS ferry §8.2: no
    /// longer has a RESTART-unit mode — restartUnit stays decodable but is no longer written from here.
    private func lanesRateTap(_ lane: Int) {
        let resolved = lanesGridView(lane).grid
        editStep(lane, true) { euclideousApplyLaneGridOp(&$0, resolved: resolved, .nextMuteUnit) }
    }

    // MARK: - THE FX TAB (FX ferry, 2026-10-18)
    /// Six fixed rows (RATCH, GATE, TIE, VEL, NOTE, CC) × the riff's eight columns, painted by `EuclideousFXPanel` (FXPanelPainter.swift) from the pure layer in
    /// Derivations.swift. The columns are the riff grid's own (`euclideousRiffCellW`). This page supplies the data (the document's FX, the written ranks named exactly
    /// as the riff grid's label column names them, the NOTE preview, the flash from the engine's hit events) and the edits — each tap / double-tap pair / stroke /
    /// value drag / lane toggle / stepper tap or drag is ONE undo step (`fxEdit`).
    private func fxTab(width: CGFloat, height: CGFloat) -> some View {
        let layout = euclideousFXLayout(width: width, height: height)
        let ranks = effectiveGridRanks
        let pool = riffLivePool.map { Int($0) }
        func name(_ n: Int) -> String {
            euclideousDisplayNoteName(UInt8(max(0, min(127, n))), source: noteSource, pool: riffLivePool, keyRoot: keyRoot, keyType: keyType)
        }
        let headers = (0..<8).map { c -> EuclideousFXHeaderLabel in
            let h = euclideousFXHeaderLabel(rank: c < ranks.count ? ranks[c] : 0, pool: pool, name: name)
            return EuclideousFXHeaderLabel(text: h.text, rest: h.rest)
        }
        let ext = euclideousGlobalPoolExtended(sortedRaw: pool)
        let noteNames: [String?] = (0..<8).map { c in
            let r = c < ranks.count ? ranks[c] : 0
            guard r >= 1 else { return nil }
            guard !ext.isEmpty, r <= ext.count else { return "rank \(r)" }
            return euclideousAccessibleDisplayNoteName(UInt8(max(0, min(127, ext[r - 1]))), source: noteSource, pool: riffLivePool, keyRoot: keyRoot, keyType: keyType)
        }
        let previewCol = euclideousFXPreviewColumn(touched: fxNotePreviewCol, fx: fx, ranks: ranks)
        return EuclideousFXPanel(layout: layout, fx: fx, selectedRow: fxSelectedRow, headers: headers, noteNames: noteNames, accents: laneAccents,
                                 silenced: (0..<4).map { soloSilenced($0) },   // LANE SOLO §6.5: the lane dots on each rail and the strip's lane buttons
                                 idleReasons: (0..<4).map { $0 < lines.count ? euclideousFXLaneIdleReason(lines[$0]) : nil },   // REVIEW FIX 2026-10-23: lanes no FX row can act on (riff off / SHADOW) dim too
                                 previewText: euclideousFXNotePreviewText(fx: fx, touched: fxNotePreviewCol, ranks: ranks, pool: pool, name: name),
                                 previewColumn: previewCol, brushes: fxBrushes, playing: pulseLive,   // PULSE §8.1: the flash keeps animating for the 1.5 s after a stop
                                 flashAt: { date in
                                     let now = date.timeIntervalSinceReferenceDate
                                     return euclideousFXFlashCells(fx: fx, lines: lines, strikes: (0..<4).map { pulseFeed.latestHappened(lane: $0, now: now, riff: true) }, ranks: ranks,
                                                                   now: now, scale: euclideousPulseScale(level: pulseLevel))
                                 },
                                 onSelectRow: { fxSelectedRow = $0 },
                                 onTouchBegan: { row, col in
                                     fxSelectedRow = row; fxStepOpen = false; fxTouchDownTime = Date().timeIntervalSinceReferenceDate
                                     if row == 4 { fxNotePreviewCol = col }
                                 },
                                 onEvent: { fxHandle($0) },
                                 onTouchEnded: { fxStepOpen = false },
                                 onToggleLane: { lane in
                                     let row = fxSelectedRow
                                     fxEdit(newStep: true) { euclideousFXToggleLane(&$0, row: row, lane: lane) }
                                 },
                                 onStepper: { kind, value, newStep in fxEdit(newStep: newStep) { euclideousFXSetStepper(&$0, kind, value: value) } },
                                 onAdjust: { row, col, up in
                                     if let v = euclideousFXAdjust(row: row, current: fx.cell(row: row, column: col), brush: fxBrushes[row], up: up) {
                                         fxEdit(newStep: true) { euclideousFXSetCell(&$0, row: row, col: col, value: v) }
                                         if row == 4 { fxNotePreviewCol = col }
                                     }
                                 },
                                 onToggleCell: { row, col in
                                     fxEdit(newStep: true) { euclideousFXTapCell(&$0, row: row, col: col, brush: fxBrushes[row]) }
                                     if row == 4 { fxNotePreviewCol = col }
                                 })
            .frame(width: width, height: height, alignment: .topLeading)
    }
    /// Apply an FX edit — only when it changes something (so a stroke across already-set cells records no empty undo step). `newStep` asks for a fresh undo
    /// checkpoint; the page still decides, so a touch never opens a second one.
    @discardableResult private func fxEdit(newStep: Bool, _ mutate: @escaping (inout EuclideousFX) -> Void) -> Bool {
        var probe = fx
        mutate(&probe)
        guard probe != fx else { return false }
        onEditFX(newStep, mutate)
        return true
    }
    /// One touch event. Taps apply at once (§12.2); the second tap of a double-tap (§12.3) writes the row's default into the FIRST tap's undo step; paint and
    /// value drags share one step per touch (`fxStepOpen`).
    private func fxHandle(_ e: EuclideousFXTouchEvent) {
        let now = Date().timeIntervalSinceReferenceDate
        switch e {
        case .tap(let row, let col):
            if euclideousFXIsDoubleTap(previous: fxLastTap, row: row, col: col, time: fxTouchDownTime) {
                let def = EuclideousFXRow(rawValue: row)?.defaultValue ?? 1
                fxLastTap = nil
                fxEdit(newStep: false) { euclideousFXSetCell(&$0, row: row, col: col, value: def) }
            } else {
                let brush = fxBrushes[row]
                fxLastTap = (row, col, now)
                fxEdit(newStep: true) { euclideousFXTapCell(&$0, row: row, col: col, brush: brush) }
            }
        case .paint(let row, let col, let on):
            fxLastTap = nil
            let brush = fxBrushes[row]
            let had = fx.cell(row: row, column: col) != nil
            guard on != had else { return }                                    // a cell already in the stroke's state is left as it is (a lit cell keeps its own value)
            if fxEdit(newStep: !fxStepOpen, { euclideousFXSetCell(&$0, row: row, col: col, value: on ? brush : nil) }) { fxStepOpen = true }
        case .value(let row, let col, let v):
            fxLastTap = nil
            fxBrushes[row] = v                                                 // the row's brush becomes the dragged value (§12.4)
            if fxEdit(newStep: !fxStepOpen, { euclideousFXSetCell(&$0, row: row, col: col, value: v) }) { fxStepOpen = true }
        }
    }

    /// THE MIX TAB (ferry 2026-10-18 §2, outputs moved here by the restart-chains ferry §9, regrouped by the CLARITY PASS 2026-10-23 §3): four lane PANELS in a 2×2 grid where the lane cards sit (lanes 1,2 on the top row,
    /// 3,4 below), sp16 apart, each a lightly tinted box holding that lane's RIFF pad (leading) and NOTES pad, their OCT steppers and its A–D row. ONE formula (`euclideousMixGrid`): panelW = (W−16)/2,
    /// panelH = (H−16)/2, cellW = (panelW−12)/2, padH = panelH−60. If a panel is too small for the legibility floors nothing is shrunk: it is built to the formula and reported
    /// (PAGE LAYOUT ferry: MIX is never skipped for a small box).
    private func mixGrid(width: CGFloat, height: CGFloat) -> some View {
        let grid = euclideousMixGrid(width: width, height: height)
        return ZStack(alignment: .topLeading) {
            // PAGE LAYOUT ferry (2026-10-19) retired §9.3's STOP (below padH 60 MIX was not built at all — portrait's 248pt panel drew only its tab strip):
            // MIX is always drawn at the formula's values and the page's floor list reports a small box. The one guard left is geometric — a pad needs room for
            // its 14pt GATE strip, or its plot would have a negative size. (CLARITY PASS: the 24pt VEL strip is gone.)
            if grid.cellW > EuclideousMixMetrics.velStripW, grid.padH > EuclideousMixMetrics.gateStripH {
                // CLARITY PASS §3: four lane PANELS in a 2×2 grid where the lane cards sit, sp16 apart; each one leaf (`mixLanePanel`, an AnyView — the 1 MB stack rule).
                ForEach(0..<4, id: \.self) { lane in
                    mixLanePanel(lane: lane, grid: grid)
                        .accessibilitySortPriority(Double(100 - lane))
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .overlay(alignment: .topLeading) { mixPulseOverlay(grid: grid, width: width, height: height) }   // PULSE §5: ripple, fill flash, puck swell, OUT-button glow
    }
    /// CLARITY PASS §3.2/§3.8: one lane's panel — lane100 at 6 % with a 1 pt inner border at 35 % (the lane card's radius, 12), its RIFF and NOTES cells (pad + OCT stepper), then its A–D row across the panel's inside width.
    /// A solo-silenced lane's whole panel (tint, border, pads, steppers, OUT row) dims once to the page's 42 %.
    private func mixLanePanel(lane: Int, grid: EuclideousMixGrid) -> AnyView {
        let accent = laneAccents[lane % laneAccents.count]
        let panel = grid.panelFrame(lane: lane), out = grid.outRowFrame(lane: lane)
        let silenced = soloSilenced(lane)
        let radius = EuclideousMixMetrics.panelRadius
        return AnyView(
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius).fill(lane100(accent).opacity(0.06))
                RoundedRectangle(cornerRadius: radius).strokeBorder(lane100(accent).opacity(0.35), lineWidth: 1)
                // cell by cell, riff before notes, each pad before its stepper (handled by `mixCell`'s own internal VStack order), then the lane's A–D row
                ForEach(0..<2, id: \.self) { n in
                    let notes = n == 1
                    let o = grid.origin(lane: lane, notes: notes)
                    mixCell(lane: lane, notes: notes, grid: grid)
                        .offset(x: o.x - panel.minX, y: o.y - panel.minY)
                        .accessibilitySortPriority(Double(3 - n))
                }
                mixOutRow(lane: lane, width: out.width, height: grid.outRowH)
                    .accessibilityValue(euclideousAppendSilencedBySolo("", silenced: silenced))
                    .offset(x: out.minX - panel.minX, y: out.minY - panel.minY)
                    .accessibilitySortPriority(1)
            }
            .frame(width: panel.width, height: panel.height, alignment: .topLeading)
            .opacity(silenced ? EuclideousLaneDimStyle.opacity : 1)   // LANE SOLO §6.3 / CLARITY PASS §3.8: the whole panel, once
            .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: silenced)
            .offset(x: panel.minX, y: panel.minY)
            .accessibilityElement(children: .contain)
        )
    }
    /// PULSE §5: ONE overlay over the whole grid (one TimelineView, never one per pad): for each pad the lane's latest strike of ITS layer — the riff pad shows riff strikes, the notes pad notes-layer strikes (5.1) — and
    /// for each routed, main-out-on OUT button the lane's latest strike of either layer. Only strikes that have happened and are younger than 1.5 s are passed; the painter turns velocity and age into pixels.
    private func mixPulseOverlay(grid: EuclideousMixGrid, width: CGFloat, height: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pulseLive)) { tl in
            let now = tl.date.timeIntervalSinceReferenceDate
            let p = euclideousPulseScale(level: pulseLevel)
            var pads: [EuclideousMixPulsePad] = []
            var buttons: [EuclideousMixPulseButton] = []
            if p > 0, grid.cellW > EuclideousMixMetrics.velStripW, grid.padH > EuclideousMixMetrics.gateStripH {
                let geo = EuclideousMixPadGeometry(cellW: grid.cellW, padH: grid.padH)
                for lane in 0..<min(4, lines.count) {
                    let line = lines[lane]
                    let accent = laneAccents[lane % laneAccents.count]
                    for notes in [false, true] {
                        guard euclideousMixPadTakesStrike(line, notes: notes), let s = pulseFeed.latestHappened(lane: lane, now: now, riff: !notes) else { continue }   // CLARITY PASS §3.7: an OFF pad has no knob to swell
                        let age = now - s.onsetAt
                        guard age <= euclideousPulseMaxAge else { continue }
                        let v = euclideousMixPadValues(of: line, notes: notes)
                        let puck = geo.puck(gate: v.gate, velocity: v.velocity)
                        pads.append(EuclideousMixPulsePad(rect: CGRect(origin: grid.origin(lane: lane, notes: notes), size: CGSize(width: grid.cellW, height: grid.padH)), puck: puck,
                                                          fill: CGRect(x: geo.plot.minX, y: puck.y, width: max(0, puck.x - geo.plot.minX), height: max(0, geo.plotH - puck.y)),
                                                          colour: accent, velocity: Int(notes ? s.notesVel : s.riffVel), seconds: age))
                    }
                    if let s = pulseFeed.latest(lane: lane, where: { $0.onsetAt <= now }), now - s.onsetAt <= euclideousPulseMaxAge {
                        let mask = line.emitterMask ?? 0
                        for b in 0..<4 where (mask >> UInt8(b)) & 1 != 0 && (mainOutMask >> UInt8(b)) & 1 != 0 {
                            buttons.append(EuclideousMixPulseButton(rect: euclideousMixOutButtonFrame(grid: grid, lane: lane, button: b), colour: accent,
                                                                    velocity: euclideousPulseRingVelocity(riffVel: Int(s.riffVel), notesVel: Int(s.notesVel)), seconds: now - s.onsetAt))
                        }
                    }
                }
            }
            return EuclideousMixPulseOverlay(pads: pads, buttons: buttons, scale: p, size: CGSize(width: width, height: height))
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
    /// One cell: the pad (cellW × padH), sp4, the OCT stepper (cellW × 24). RIFF writes the lane's GATE/VEL through the RHYTHM sliders'
    /// own setters and `riffOctave` through the RIFF tab's OCT setter; NOTES writes `notesGate`/`notesVelocity` and `octave` through the
    /// NOTES tab's octave setter. CLARITY PASS §3.7: a layer that's off is an inert OFF pad (no touch writes it) whose stepper dims to 50 % and still edits.
    @ViewBuilder private func mixCell(lane: Int, notes: Bool, grid: EuclideousMixGrid) -> some View {
        let line = lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all)
        let accent = laneAccents[lane % laneAccents.count]
        let off = euclideousMixLayerIsOff(line, notes: notes)
        let v = euclideousMixPadValues(of: line, notes: notes)
        VStack(spacing: sp4) {
            EuclideousMixPad(cellW: grid.cellW, padH: grid.padH, gate: v.gate, velocity: v.velocity, accent: accent, off: off, notes: notes,
                             accessibilityLabelText: euclideousMixPadAccessibilityLabel(lane: lane, notes: notes, off: off),
                             onEditStep: { newStep, mutate in editStep(lane, newStep, mutate) })
            EuclideousMixOctaveStepper(cellW: grid.cellW, height: grid.stepperH, octave: euclideousMixOctave(of: line, notes: notes), accent: accent,
                                       opacity: euclideousMixOffStepperOpacity(off: off, soloSilenced: soloSilenced(lane)),
                                       accessibilityLabelText: euclideousMixOctaveAccessibilityLabel(lane: lane, notes: notes),
                                       onSet: { o in edit(lane) { l in if notes { euclideousSetNotesOctave(&l, o) } else { euclideousSetRiffOctave(&l, o) } } })
        }
        .frame(width: grid.cellW, height: grid.padH + sp4 + grid.stepperH, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityValue(euclideousAppendSilencedBySolo("", silenced: soloSilenced(lane)))
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
                                // §8.2: the RIFFS tab is HIDDEN (unreachable from the tab strip below),
                                // not deleted — there is only ONE riff now, so every row's icon is the
                                // same effective grid (dead code kept compiling, never actually shown).
                                riffMiniIcon(ranks: effectiveGridRanks, noteColor: Color(hex: 0xDFE3EA), dotColor: Color(hex: 0x3A3E47))
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
        let isLanes = sequencerTab != .riffs
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
    private func riffMiniIcon(ranks: [Int], noteColor: Color, dotColor: Color, style: EuclideousMiniIconStyle = .standard) -> some View {
        // RIFF PANEL ferry (2026-10-19) §2.3: a `style` parameter. `.standard` (the default) is the 31 × 23 every call site but the riff TAB ROW keeps; `.tab` is
        // 21.7 × 12.8 (column pitch 2.8, row pitch 1.65, marks 2.1 × 1.25, dots 0.7 × 0.7). The marks and dots come from the pure `euclideousMiniIconGeometry`.
        let g = euclideousMiniIconGeometry(ranks: ranks, style: style)
        return Canvas { ctx, _ in
            for m in g.marks { ctx.fill(Path(roundedRect: m, cornerRadius: style.markRadius), with: .color(noteColor)) }
            for d in g.dots { ctx.fill(Path(d), with: .color(dotColor)) }
        }
        .frame(width: g.size.width, height: g.size.height)
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

/// The roll feed's per-lane cache (LANES GRID §3.2): "recompute when any mute cell, mark, unit, lane step length, STEPS, hits, offset, rate or riff
/// changes, and when the window wraps; cache between those; never per frame." The key is everything the feed reads, so a hit is exactly a repeat
/// of the same question. A plain reference type: the page keeps one in `@State`, and filling it never invalidates the view.
final class EuclideousLanesRollCache {
    struct Key: Equatable {
        var lines: [EuclidLine]
        var lanesSeq: EuclideousLanesSeq
        var ranks: [Int]
        var windowStart: Double
        var unit: Double
        var restartTab: Bool
        var beatsPerBar: Double
        var tempo: Double
        var swing: Double
        var fx: EuclideousFX   // every FX edit (cells, lane bits, PASSES, …) recomputes the roll (FX ferry §13.4)
    }
    private var store: [Int: (key: Key, roll: [EuclideousRollHit])] = [:]
    func roll(lane: Int, key: Key, make: () -> [EuclideousRollHit]) -> [EuclideousRollHit] {
        if let hit = store[lane], hit.key == key { return hit.roll }
        let r = make()
        store[lane] = (key, r)
        return r
    }
}
