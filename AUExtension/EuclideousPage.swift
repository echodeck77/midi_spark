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
    let onCommit: (@escaping (inout EuclidLine) -> Void) -> Void
    let onDoubleTap: () -> Void
    let onRevertToEuclid: () -> Void

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
    private var edited: Bool { field == .tilt && line.customHits != nil }

    var body: some View {
        let curFrac = euclideousSliderFrac(field, line)
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
                    for tf in euclideousSliderTickFracs(field, line) {
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
                    ctx.fill(Path(bar(center, value)), with: .color(accent.opacity(0.2)))
                    // Exact-dimensions ferry (2026-10-13): TILT's always-visible centre reference line
                    // is now the same neutral grey as every other slider's static ticks (#3a3e47), not
                    // the lane accent — distinguishing "where centre is" (static) from "where the value
                    // sits" (the accent edgeLine(value) line right below, still live-coloured).
                    ctx.fill(Path(edgeLine(center)), with: .color(Color(hex: 0x3A3E47)))
                    ctx.fill(Path(edgeLine(value)), with: .color(accent))
                } else {
                    // UNIPOLAR (ferry, literal): "rises from the bottom of the track to the value" —
                    // grows from the LEFT when horizontal.
                    let value = pos(curFrac)
                    ctx.fill(Path(bar(horizontal ? 0 : len, value)), with: .color(accent.opacity(0.2)))
                    ctx.fill(Path(edgeLine(value)), with: .color(accent))
                }
            }
            VStack(spacing: 0) {
                // Exact-dimensions ferry (2026-10-13): value text 14pt heavy TEXT, 6pt from the
                // slider's top edge; label 10pt MUTED, 5pt from the bottom — no longer vertically
                // centred as a pair, each pinned to its own edge via the Spacer between them.
                if edited {
                    // THE EDITED CHIP (ferry, literal): "LANE-20 fill, LANE-100 border, 10pt... in the
                    // value position." Its own hit area is the overlay below, not this label.
                    Text("EDITED").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.2)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent, lineWidth: 1))
                        .padding(.top, 6)
                } else {
                    Text(euclideousSliderValueText(field, line))
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                Text(euclideousSliderLabelText(field, line)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                    .padding(.bottom, 5)
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
        // THE 2pt TOUCH BORDER is REMOVED (Paul 2026-10-12: "when a slider is selected it has an outline
        // appear. Please remove this behaviour") — was the ferry's own original "while touched: a 2pt
        // LANE-100 border" spec; `touching` (the @State that drove it) is gone too, having no other use.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !edited else { return }   // ferry, literal: "touches elsewhere on a disabled TILT do nothing"
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
                    guard !edited else { return }
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
        .accessibilityLabel(edited ? "\(field.name), edited" : field.name)
        .accessibilityValue(edited ? "double-tap to revert" : euclideousSliderAccessibilityValueText(field, line))
        .accessibilityAdjustableAction { direction in
            guard !edited else { return }
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
    case rhythm = 0, riff = 1, notes = 2, mask = 3
    var label: String { switch self { case .rhythm: "RHYTHM"; case .riff: "RIFF"; case .notes: "NOTES"; case .mask: "MASK" } }
}

struct EuclideousPage: View {
    let lines: [EuclidLine]
    let enabled: Bool
    let lineReady: UInt8
    // RIFF ADVANCE (Paul 2026-10-06): `riff` is the ONE shared pattern every useRiff-on lane reads; `riffPositions`
    // is each lane's own live step-cursor into it (index 0...3, -1 = not started/off) — "independent cursor per
    // lane" into one shared pattern, not a single shared cursor.
    let riff: EuclideousRiff
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
    // NOTE VIEW (Paul 2026-10-10 ferry): per-lane RECONCILED event state, already folded down to "the latest
    // thing to show" by AudioUnitViewController's own poll (see its own doc comment) — this view does no
    // further event-queue bookkeeping, only the fade/hold/rest-flash DISPLAY math, which is a pure function
    // of (one of these, the live extrapolated beat) evaluated fresh every frame.
    let noteViewLastEvent: [Router.EuclideousNoteViewEventSnapshot?]
    let noteViewRestFlash: [Router.EuclideousNoteViewEventSnapshot?]
    // RIFF-CELL WIPES (Paul 2026-10-10 ferry) — each lane's latest wipe-eligible event (column/rank >= 0),
    // reconciled independently from the two above (AudioUnitViewController's own @State doc comment).
    let wipeEvents: [Router.EuclideousNoteViewEventSnapshot?]
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
    let onEditRiff: (@escaping (inout EuclideousRiff) -> Void) -> Void
    let onToggleEnabled: () -> Void
    let onSetResetSpanBars: (Int) -> Void
    let onSetKeyRoot: (Int) -> Void
    let onSetKeyType: (ScaleType) -> Void
    let onSetMainOutMask: (UInt8) -> Void
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

    @State private var selectedLane = 0
    // §3.1's own pressed-state tracking for the NOTE VIEW summary label (per-lane, purely local/ephemeral —
    // matches `selectedLane`/`singleTouchedLanes`'s own established "local @State, never persisted" class).
    @State private var labelPressed: [Bool] = [false, false, false, false]
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
    @State private var resetSpanPopupOpen = false
    @State private var keyPopupOpen = false
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry): the KEY tab's own captured
    // on-screen frame (via EuclideousRiffTabFramePreferenceKey above), letting the picker open as a
    // popover anchored near the tab instead of centre-screen — nil until the tab has rendered at least
    // once, in which case the popup falls back to centre (handled at the render site).
    @State private var riffKeyTabFrame: CGRect? = nil
    @State private var chordsPopupOpen = false
    // riffDirPopupLane RETIRED 2026-10-10 alongside the RIFF tab — direction selection lives inline in the
    // melody pop-up's WALK section now, no separate nested popup needed.
    // MASK MODE POPUP (Paul 2026-10-10, "Euclid mask, modes and settings" ferry §4): "tapping opens a picker
    // of the 11 modes, grouped" — same scrim+centred-card shape as `ratePopupCard`. nil = no popup open.
    @State private var maskModePopupLane: Int? = nil
    // RIFF GRID POSITION MARKERS (Paul 2026-10-12 ferry, Part 1) — each lane's own PERSISTENT marker
    // (column, row), updated by `riffMarkerTimer` below (was `.onChange(of: riffPositions)` until the
    // 2026-10-14 off-by-one fix — see that entry's own comment), not recomputed fresh every render:
    // rule 1's "stays until the lane's next hit moves it... does not flash and fade" means a TIE-on-rest
    // tick (nothing struck, no fresh event) must leave the PREVIOUS marker exactly where it was, which a
    // pure-function-of-current-state view could not express on its own (it has no memory of "where was it
    // last" once the live state has already moved past that tick) — the one piece of this whole ferry that
    // genuinely needs retained, not derived, UI state.
    @State private var riffMarker: [(col: Int, row: Int)?] = [nil, nil, nil, nil]
    // UNCONDITIONAL REFRESH (Paul 2026-10-14, "it sits on 1 for too long, then stays exactly one step
    // behind forever" — a fixed, permanent one-step lag, not jitter/latency, confirmed by him even at a
    // very slow riff rate): `.onChange(of: riffPositions)` only calls `updateRiffMarkers()` when SwiftUI's
    // OWN diffing decides the 4-element array differs from whatever it compared last — if that comparison
    // is ever made against a value one tick staler than the view's current `riffPositions` (a SwiftUI
    // view-update-timing question this file can't execute/observe to confirm), exactly one transition
    // could be silently skipped near the start, after which every later read is correctly one real engine
    // hit AHEAD of what `riffMarker` last recorded — permanently, since nothing ever re-derives from
    // scratch again. A dedicated, OWN-TIMER-DRIVEN re-derivation removes any dependency on detecting a
    // DELTA at all: every tick it just reads the CURRENT `riffPositions`/`wipeEvents` fresh and re-derives
    // `riffMarker`, so there is no "missed change" for it to miss. Reversible: if this doesn't fix it,
    // revert to the `.onChange`-only version 2 commits up — see this entry's own commit message.
    private let riffMarkerTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()
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

    // --- PROTECTED ABSOLUTE SIZE (ferry §3, 2026-10-08 — a component dimension, not spacing, so the
    // 4/8/16 scale doesn't apply to it): MAIN OUT's own header circles never shrink below this. (The
    // sibling `laneOutSize`, for the old circular per-lane OUT toggles, is gone — those toggles are now
    // equal-width buttons inside `patternControlBlock`'s fixed 40pt row, 2026-10-12.) ---
    private let mainOutSize: CGFloat = 36

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
                // THE MELODY POP-UP IS RETIRED ENTIRE (Paul 2026-10-13 ferry, "MELODY tab on the lane cards"):
                // every setting it held (note choice, octave, all riff settings) now lives in the RIFF and
                // NOTES tabs on each lane's own card (`tabContent`'s `.riff`/`.notes` cases, RIFF/NOTES SPLIT
                // ferry) — there is no floating popup left to anchor. `melodyPopupLane`/`melodyStripFrames`/
                // `EuclideousStripFramePreferenceKey`/`euclideousMelodyAnchor`/`melodyPopupCard`/
                // `melodyPointer` are all deleted, not left dead — confirmed by grep before removing, zero
                // remaining readers.
                // RESET SPAN + KEY POPUPS (Paul 2026-10-07) — the SAME scrim+card shape, reused rather than
                // reinvented, for the two new global pickers.
                if resetSpanPopupOpen {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { resetSpanPopupOpen = false }
                        .zIndex(3)
                    resetSpanPopupCard.position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                if keyPopupOpen {
                    // ANCHORED POPOVER (Paul 2026-10-12, second same-day ferry): "a popover anchored to the
                    // tab... dismiss by tapping outside" — a non-dimming full-screen tap-catcher (the SAME
                    // "anchored, not a modal" pattern the melody pop-up already established on this page),
                    // positioned beside the captured KEY tab frame; falls back to centre-screen if the tab
                    // hasn't published a frame yet (shouldn't happen in practice once the page has rendered
                    // once, but a defensive default costs nothing).
                    Color.clear.contentShape(Rectangle()).onTapGesture { keyPopupOpen = false }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(3)
                    let anchorX = riffKeyTabFrame.map { max(170, $0.minX - 10) } ?? geo.size.width / 2
                    let anchorY = riffKeyTabFrame.map { $0.midY } ?? geo.size.height / 2
                    keyPopupCard.position(x: min(anchorX, geo.size.width - 170), y: min(max(140, anchorY), geo.size.height - 140)).zIndex(4)
                }
                // THE CHORDS POP-UP (Paul 2026-10-08) — same scrim+card shape as RESET SPAN/KEY above, but
                // sized from the real available space (like `buildReceiverChordPopup`'s own `min(620, size.width
                // - 32)` precedent) since a full degree matrix needs much more room than those two small cards.
                if chordsPopupOpen {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { chordsPopupOpen = false }
                        .zIndex(3)
                    chordsPopupCard(geo.size).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // THE XY PAD VALUE BUBBLE is RETIRED along with the pads themselves (usability ferry,
                // 2026-10-12) — each of the six new sliders shows its own value permanently, in place, so
                // there's no floating readout left to anchor anywhere.
            }
            .coordinateSpace(name: "euclideousXY")
            .onPreferenceChange(EuclideousRiffTabFramePreferenceKey.self) { if let f = $0 { riffKeyTabFrame = f } }
        }
        .onReceive(riffMarkerTimer) { _ in updateRiffMarkers() }
        .onAppear { updateRiffMarkers() }
    }

    /// Whether this lane's walk is heading to a HIGHER or LOWER step next — drives the marker's arrow
    /// direction (▶/"next up" for true, ◀/"next down" for false). `nil` when there's nothing meaningful to
    /// compare against yet (riff off, fewer than 2 hits in the lap, or a degenerate 1-step walk). Reuses the
    /// SAME `euclideousLapHitSteps`/`euclideousRiffLapBaseline`/`euclideousRiffCyclePrediction` pure
    /// functions `laneFooterStates` calls — invoked again here rather than threaded across two independent
    /// view hierarchies, matching how `euclideousNoteViewPattern` is already called from several independent
    /// UI sites in this file.
    ///
    /// BUGFIX (Paul 2026-10-14, "arrows point the wrong way even though all play directions are forward"):
    /// SUPERSEDES the previous `riffMarkerNextStep(_:_:) -> Int?`, which returned the raw predicted step and
    /// left callers to compare it against `riffMarker[lane].col + 1` as a plain linear `>=` — correct for
    /// every step EXCEPT the one at each lap's wrap boundary. FWD's walk position counts 1…`length` then
    /// wraps back to 1 (`riffStepAt(.forward, …) = raw mod steps`, confirmed by direct read) — a linear
    /// comparison sees that wrap (`length → 1`) as a big DECREASE and points the arrow left, even though the
    /// walk is still advancing forward, just cyclically. REVERSE has the mirror-image bug at its own wrap
    /// (`1 → length` reads as a big increase, pointing right). Fixed by comparing the SHORTEST SIGNED
    /// distance around the walk's own `length`-position cycle instead of a plain difference — a wrap is then
    /// indistinguishable from any other single step in the same direction. (The earlier `riffMarkerDirectionWord`
    /// comment claiming this comparison lived in "1-based COLUMN number" space was itself part of the
    /// confusion — the live-polled `riffMarker[lane].col` and the independently-predicted `current`/`next`
    /// below are the SAME walk-position axis in principle, but polled through two separate channels; computing
    /// the direction entirely from one self-consistent source — this function's own `prediction` — removes
    /// that cross-poll risk too, not just the wraparound bug.)
    private func riffMarkerPointsRight(_ idx: Int, _ line: EuclidLine) -> Bool? {
        guard line.riffOnResolved, idx < riffWalkState.count else { return nil }
        // FORWARD/REVERSE ARE UNCONDITIONAL (Paul 2026-10-14, "I'm also seeing the occasional arrow pointing
        // in the wrong direction" — a REGRESSION this same fix's own circular-distance comparison introduced
        // for STRIDE > half the walk's own LENGTH, found by tracing a concrete example, not guessed): FWD's
        // underlying `advOrd` (hence `raw = advOrd * stride`) only ever INCREASES between hits — `riffStepAt`
        // then folds that ever-increasing `raw` into `[0, length)` via a plain `mod`. For stride=1 the fold
        // only ever advances by 1 at a time, so "the shortest circular path" and "the true direction" always
        // agree — which is why the ORIGINAL bug (the wrap from `length` back to `1`) was fixable by taking
        // the shorter path. But for a LARGER stride (reachable: stride clamps 1...7, length clamps 1...8,
        // e.g. stride=5/length=8), a single hit can hop PAST the halfway point of the cycle even with NO
        // wrap at all (worked example: current=1, next=6 — a genuine, non-wrapping +5 forward hop — the
        // shortest circular path from 1 to 6 is -3, the WRONG way round, so the old comparison misread this
        // as "backward"). FORWARD is PROVABLY always "right" and REVERSE always "left" regardless of stride
        // or wrap, by construction — there is no comparison that can get this wrong, so none is attempted;
        // the `prediction`-based circular comparison below is kept for PENDULUM/PINGPONG/RANDOM only, where
        // the direction genuinely does alternate (or has none) and a real comparison is unavoidable.
        switch line.euclideousRiffDirResolved {
        case .forward: return true
        case .reverse: return false
        default: break
        }
        let steps = max(2, min(16, line.steps))
        let hitSteps = euclideousLapHitSteps(pulses: line.pulses, steps: steps, rotate: line.rotate,
                                              tilt: line.tiltResolved, patternMiss: line.patternMissResolved,
                                              customHits: line.customHitsResolved(steps), dir: line.directionResolved)
        guard hitSteps.count >= 2 else { return nil }
        let ws = riffWalkState[idx]
        let locked = line.riffLockResolved, advanceStep = line.riffAdvanceStepResolved
        let baseline = euclideousRiffLapBaseline(hitSteps: hitSteps, lapSteps: steps, locked: locked, advanceStep: advanceStep,
                                                   liveOrd: ws, dir: line.directionResolved)
        let length = line.riffLengthResolved
        let prediction = euclideousRiffCyclePrediction(hitSteps: hitSteps, advanceStep: advanceStep, dir: line.euclideousRiffDirResolved,
                                                         stride: line.riffStrideResolved, length: length,
                                                         rotate: line.riffRotateResolved, seed: UInt64(bitPattern: Int64(line.riffDirSeedResolved)),
                                                         startOrd: baseline.startOrd)
        guard !prediction.isEmpty, length > 1 else { return nil }
        let current = prediction[baseline.currentHitIndex]
        let nextIdx = (baseline.currentHitIndex + 1) % prediction.count
        let next = prediction[nextIdx]
        // PINGPONG's doubled-endpoint tick (Paul 2026-10-12 ferry, disclosed interpretation beyond his own
        // text): two consecutive hits can land on the SAME riff step — a plain next-vs-current comparison
        // reads as "no direction" right when it matters most (the marker is sitting exactly on an
        // endpoint). Resolved by comparing against the PREVIOUS step instead, continuing whichever
        // direction was already in motion for this one tick (the genuine reversal shows correctly on the
        // FOLLOWING tick, once `current` itself has moved past the dwell). A lane that's dwelled on the
        // SAME step for 3+ consecutive hits (current == previous too) has no real direction to continue —
        // defaults to right, matching this function's own "nothing to compare" `nil` callers' own `?? true`.
        if next == current, line.riffDirResolved == .pingpong {
            let prevIdx = (baseline.currentHitIndex - 1 + prediction.count) % prediction.count
            let previous = prediction[prevIdx]
            if current != previous { return current > previous }
            return true
        }
        // CIRCULAR DIRECTION: the shortest signed distance from `current` to `next` around the walk's own
        // `length`-position cycle — ties (exactly half the cycle away) round to "right" by construction
        // (an inherently ambiguous case, not one the data can resolve either way).
        var delta = (next - current) % length
        if delta > length / 2 { delta -= length } else if delta < -(length / 2) { delta += length }
        return delta >= 0
    }

    /// RIFF GRID POSITION MARKERS (Paul 2026-10-12 ferry, Part 1 rule 7) — updates `riffMarker[i]` on every
    /// `riffPositions` poll tick. A non-rest column is read directly off the shared grid (no telemetry
    /// needed — the rank IS the column's own resolved value); a rest column consults the SAME reconciled
    /// `wipeEvents[i]` FILL-on-rest tells us about elsewhere on this page, and — matching rule 7's own
    /// "with SKIP, the marker sits on the step actually played" read literally as "the step where sound was
    /// actually produced," a disclosed refinement of Paul's own text, not implied by it — a TIE/SKIP rest
    /// with no matching fresh event leaves the PREVIOUS marker untouched rather than jumping to a rest
    /// column with no row to draw on.
    // riffOffDotCell REMOVED (Paul 2026-10-13, "lit notes plus the riff" ferry — "Riff grid markers: these
    // show only the riff. A lane with the riff off draws no marker. This replaces the 'riff off: a dot'
    // rule.") — the dot-for-riff-off mechanism above is gone entire, not merely disabled; its one call site
    // in `riffGridCell` is removed too. A riff-off lane now contributes no occupant at all, by construction.

    private func updateRiffMarkers() {
        let resolved = riff.ranksResolved
        for i in 0..<4 {
            guard i < lines.count, lines[i].riffOnResolved else { riffMarker[i] = nil; continue }
            guard i < riffPositions.count, riffPositions[i] >= 0, riffPositions[i] < 8 else { continue }
            let col = riffPositions[i]
            let rank = col < resolved.count ? resolved[col] : 0
            if rank != 0 {
                riffMarker[i] = (col, rank)
            } else if i < wipeEvents.count, let ev = wipeEvents[i], ev.column == Int8(col), ev.rank >= 1 {
                riffMarker[i] = (col, Int(ev.rank))
            }
            // else: a TIE/SKIP rest with nothing new sounding — leave riffMarker[i] exactly as it was.
        }
    }

    // MARK: - ONE CONTAINER (this ferry §1.3, re-affirming the layout-system ferry's own rule): "the view's
    // bounds minus 16pt left and right. Header, lane grid and riff panel all span exactly that container.
    // Left and right margins must be equal within 1pt." Applied on all four sides for symmetry.
    //
    /// The riff panel's total height at a given MATRIX row height: top+bottom padding (sp8 each) + the
    /// title row (just "RIFF" — §7.1 drops the old subtitle) + a gap + the position-dot row (10pt — §7.2)
    /// + a gap + 8 matrix rows with 7 gaps between them. `riffRowHForPanelHeight` solves the SAME formula
    /// backward from an outer height — one pair, so the panel's claimed height and its internal row height
    /// can never silently disagree.
    private let riffTitleRowH: CGFloat = 18
    private let riffDotRowH: CGFloat = 10   // ferry §7.2: "reserve 10pt of height for the per-lane position dots"
    private func riffPanelHeight(rowH: CGFloat) -> CGFloat {
        sp8 * 2 + riffTitleRowH + sp4 + riffDotRowH + sp4 + rowH * 8 + sp4 * 7
    }
    private func riffRowHForPanelHeight(_ panelH: CGFloat) -> CGFloat {
        max(4, (panelH - sp8 * 2 - riffTitleRowH - sp4 - riffDotRowH - sp4 - sp4 * 7) / 8)
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
        let headerH = portraitHeaderHeight
        let containerW = size.width - sp16 * 2
        let totalBelowH = max(1, size.height - headerH - sp16 * 3)   // top margin + header↔grid gap + bottom margin
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
            portraitHeader().frame(width: containerW, alignment: .leading)
                .padding(.horizontal, sp16).padding(.top, sp16)
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
                    noteViewPanel(maxWidth: halfW, maxHeight: sharedRowH)
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
        let headerH = landscapeHeaderHeight
        let containerW = size.width - sp16 * 2
        let belowH = max(1, size.height - headerH - sp16 * 3)   // top margin + header↔grid gap + bottom margin
        let riffColW = containerW * 0.36
        let laneColW = containerW - riffColW - sp16
        let laneW = max(1, (laneColW - sp8) / 2)
        let laneH = max(1, (belowH - sp8) / 2)
        let halfH = max(1, (belowH - sp16) / 2)   // riff (top) / NOTE VIEW (bottom), 50/50
        let riffRowH = riffRowHForPanelHeight(halfH)
        return VStack(alignment: .leading, spacing: sp16) {
            landscapeHeader().padding(.horizontal, sp16).padding(.top, sp16)
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
                    noteViewPanel(maxWidth: riffColW, maxHeight: halfH)
                }
                .frame(width: riffColW)
            }
            .frame(width: containerW, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }

    // MARK: - Header (this ferry §3, literal): BOTH orientations show exactly EUCLIDEOUS · RESET · KEY −/
    // chip/+ · CHORDS · MAIN OUT A B C D · ON · close — "nothing in the header may be clipped or missing"
    // (§3.3). LANDSCAPE is one row, that exact order. PORTRAIT splits across two rows per §3.2's own
    // literal assignment: row 1 = EUCLIDEOUS · MAIN OUT A B C D · ON · close; row 2 = RESET · KEY −/chip/+
    // · CHORDS (RESET moved OFF row 1 — a direct, deliberate change from the prior ferry's own split, not
    // a continuation of it). Every label is a flat 10pt with NO `.minimumScaleFactor` (§6.1's own floor —
    // see the per-function comments below for why a scale factor is now actively forbidden, not just unused).
    private let headerRowH: CGFloat = 30
    private let headerBtnH: CGFloat = 28

    private var portraitHeaderHeight: CGFloat { headerRowH * 2 + sp4 }
    private var landscapeHeaderHeight: CGFloat { headerRowH }

    private func portraitHeader() -> some View {
        VStack(spacing: sp4) {
            headerRow1().frame(height: headerRowH)
            headerRow2().frame(height: headerRowH)
        }
    }
    private func landscapeHeader() -> some View {
        HStack(spacing: sp4) {
            headerTitle()
            headerUndoRedoGroup()
            Spacer(minLength: sp4)
            headerResetChip()
            headerSourceGroup()
            headerChordsChip()
            headerMainOutGroup()
            headerOnChip()
            headerPresetButton()
            headerCloseButton()
        }
        .frame(height: headerRowH)
    }

    /// PORTRAIT row 1 (this ferry §3.2, literal): EUCLIDEOUS · MAIN OUT A B C D · ON · close — RESET moved
    /// OUT to row 2 (it was here in the prior ferry; this one explicitly re-homes it).
    private func headerRow1() -> some View {
        HStack(spacing: sp4) {
            headerTitle()
            headerUndoRedoGroup()
            Spacer(minLength: sp4)
            headerMainOutGroup()
            headerOnChip()
            headerPresetButton()
            headerCloseButton()
        }
    }
    /// PORTRAIT row 2 (this ferry §3.2, literal): RESET · KEY −/chip/+ · CHORDS. The MIDI IN/CHORD/KEY
    /// SOURCE group (Paul 2026-10-14, moved here from the riff panel) sits between them.
    private func headerRow2() -> some View {
        HStack(spacing: sp4) {
            headerResetChip()
            Spacer(minLength: sp4)
            headerSourceGroup()
            headerChordsChip()
        }
    }

    // TYPE FLOOR (this ferry §6.1: "nothing meaningful is drawn smaller than 10pt. This includes the header
    // labels (RESET, KEY, MAIN OUT)...") — every header label below was previously 7–9pt with a
    // `.minimumScaleFactor` that could shrink it further still; both violate the floor, so EVERY size here
    // is now a flat 10pt with NO scale factor (a renderable minimum below 10pt is exactly what's forbidden —
    // if a real container is too narrow, text now clips via `.lineLimit(1)` instead of silently shrinking
    // under the floor, an honest trade-off, not a silent violation).
    private func headerTitle() -> some View {
        Text("EUCLIDEOUS").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.9)).lineLimit(1)
    }
    /// §7.1, literal: "↶ and ↷ buttons... after the title in landscape and in row 1 in portrait; disabled
    /// (40% opacity) when there is nothing to undo or redo."
    private func headerUndoRedoGroup() -> some View {
        HStack(spacing: sp4) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(canUndo ? 0.7 : 0.4))
                .contentShape(Rectangle())
                .onTapGesture { if canUndo { onUndo() } }
                .euclideousHelp("Undo the last change")
            Image(systemName: "arrow.uturn.forward").font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(canRedo ? 0.7 : 0.4))
                .contentShape(Rectangle())
                .onTapGesture { if canRedo { onRedo() } }
                .euclideousHelp("Redo the last undone change")
        }
    }
    private func headerResetChip() -> some View {
        HStack(spacing: sp4) {
            Text("RESET").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            Text(euclideousResetSpanLabel(resetSpanBars))
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, sp4).frame(height: headerBtnH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { resetSpanPopupOpen = true }
                // §3.3's own literal example: "RESET: Bring every lane back to the start every N bars."
                .euclideousHelp("Bring every lane back to the start every N bars")
            // RESET COUNTDOWN (ferry "riff-cell wipes, reset progress on lane cards" §4) — "IN n", counting
            // down to the next reset; hidden (§4.2) when RESET SPAN is OFF (the chip's own "OFF" value text
            // above already reads as inert with nothing else needed beside it). UNAFFECTED by Reduce Motion
            // (§5: "the header countdown still shows") — no `reduceMotion` gate here, deliberately.
            if resetSpanBars > 0 {
                let cyc = clock.stepBeats * Double(max(1, clock.cols))
                // CAPPED (usability ferry §1.2 DSP fix): a whole-bar countdown changes at most once every
                // few seconds — full display-refresh-rate scheduling here was pure waste. 4Hz is already
                // far faster than this text could ever visibly need to update.
                TimelineView(.animation(minimumInterval: 0.25, paused: !clock.playing)) { tl in
                    let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
                    let spanBeats = euclideousNoteViewSpanBeats(resetSpanBars: resetSpanBars, cyc: cyc)
                    let bars = euclideousResetBarsRemaining(liveBeat: liveBeat, spanBeats: spanBeats, cyc: cyc, resetSpanBars: resetSpanBars)
                    Text("IN \(bars)").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                }
            }
        }
    }
    // headerKeyGroup REMOVED (Paul 2026-10-12, second same-day ferry): "only its entry point moves" — the
    // key picker (`keyPopupCard`, content unchanged) opened exclusively from the KEY tab beside the riff
    // grid for a while (`riffSourceTabs`, since removed — see `headerSourceGroup` below); the old header
    // chip's own +/− quick-step buttons, which had no described replacement at the time, never came back.
    // The KEY entry point is now back in the header, just restyled (2026-10-14) — a full-circle move, not
    // a reversal of this entry's own original reasoning.
    // CHORDS (Paul 2026-10-08) — "next to [KEY] place a chords button that opens a pop-up to a chord grid
    // with rate control."
    private func headerChordsChip() -> some View {
        Text("CHORDS").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.8)).lineLimit(1)
            .padding(.horizontal, sp4).frame(height: headerBtnH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture { chordsPopupOpen = true }
    }
    /// MIDI IN/CHORD/KEY SOURCE — MOVED here from the riff-grid panel's own vertical rotated side tabs
    /// (Paul 2026-10-14: "move the midi in/chords/key control to the top header bar and restyle") —
    /// restyled from `riffSourceTabs`' narrow 22×62pt rotated-text column into 3 plain horizontal header
    /// chips, matching every OTHER header control's own convention (10pt heavy monospaced, `headerBtnH`,
    /// `cornerRadius: 6`) instead of the riff panel's bespoke rotated-tab look. SAME tap behaviour as
    /// before, byte-for-byte: tapping the already-selected KEY chip opens the key popup; tapping an
    /// UNSELECTED chip switches the source; tapping an already-selected MIDI IN/CHORD chip does nothing.
    /// The KEY chip still publishes its own on-screen frame via the SAME `EuclideousRiffTabFramePreferenceKey`
    /// the popup's anchor already reads — moving the PUBLISHER automatically moves the anchor with it, no
    /// change needed to the popup-positioning code itself.
    private func headerSourceGroup() -> some View {
        let current = noteSource
        return HStack(spacing: sp4) {
            ForEach([EuclideousLaneSource.midi, .chords, .key], id: \.self) { src in
                let selected = current == src
                let label = src == .midi ? "MIDI IN" : (src == .chords ? "CHORD" : "KEY")
                let a11y = src == .midi ? "Source, MIDI in" : (src == .chords ? "Source, chord" : "Source, key, double-tap to choose key")
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(selected ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA)).lineLimit(1)
                    .padding(.horizontal, sp4).frame(height: headerBtnH)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(hex: 0xDFE3EA) : Color(hex: 0x2A2D34)))
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: EuclideousRiffTabFramePreferenceKey.self,
                                                     value: src == .key ? g.frame(in: .named("euclideousXY")) : nil)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if src == .key, selected { keyPopupOpen = true }
                        else if !selected { onSetNoteSource(src) }
                        // already-selected MIDI IN/CHORD: literally nothing, matching the prior control's own rule.
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a11y)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    // The "MAIN OUT" text caption is DROPPED here (kept in the §5 spec's own wording as the group's
    // NAME, not a literal required on-screen label) — each circle already shows its own letter (A/B/C/D).
    private func headerMainOutGroup() -> some View {
        HStack(spacing: sp4) {
            ForEach(0..<4, id: \.self) { b in mainOutToggle(b) }
        }
    }
    private func headerOnChip() -> some View {
        Text(enabled ? "ON" : "OFF").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(enabled ? .black : .white.opacity(0.6)).lineLimit(1)
            .padding(.horizontal, sp4).frame(height: headerBtnH)
            .background(RoundedRectangle(cornerRadius: 6).fill(enabled ? Color.green.opacity(0.85) : Color.white.opacity(0.08)))
            .onTapGesture { onToggleEnabled() }
    }
    private func headerCloseButton() -> some View {
        Image(systemName: "xmark.circle.fill").font(.system(size: 15))
            .foregroundColor(.white.opacity(0.5))
            .onTapGesture { onClose() }
    }
    /// PRESETS (Paul 2026-10-11): icon-only, matching headerCloseButton's own plain-glyph footprint rather than
    /// a labelled chip — this header already has no spare width to give (every prior ferry on this page fought
    /// the SAME narrow-panel fit problem). Same "folder.fill" glyph the main workbench's own PRESETS button uses
    /// (ArrangementBar.swift), so it reads as the same action rather than a new one.
    private func headerPresetButton() -> some View {
        Image(systemName: "folder.fill").font(.system(size: 13))
            .foregroundColor(.white.opacity(0.5))
            .onTapGesture { onOpenPresets() }
    }

    /// MAIN OUT (Paul 2026-10-07, §2.3): a GLOBAL master gate over every lane's own per-lane routing — fixed
    /// at 36pt (ferry §3: "do not make... MAIN OUT any smaller than they are now") regardless of header scale.
    private func mainOutToggle(_ b: Int) -> some View {
        let on = (mainOutMask >> UInt8(b)) & 1 != 0
        return Text(["A", "B", "C", "D"][b]).font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.6))
            .frame(width: mainOutSize, height: mainOutSize)
            .background(Circle().fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
            .overlay(Circle().stroke(Color.white.opacity(on ? 0 : 0.25), lineWidth: 2))
            .contentShape(Circle())
            .onTapGesture { onSetMainOutMask(mainOutMask ^ (1 << UInt8(b))) }
    }

    private func euclideousResetSpanLabel(_ bars: Int) -> String { bars <= 0 ? "OFF" : "\(bars) BAR\(bars == 1 ? "" : "S")" }

    private var resetSpanPopupCard: some View {
        VStack(spacing: 8) {
            Text("RESET SPAN").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            ForEach([0, 1, 2, 4, 8, 16], id: \.self) { v in
                let on = resetSpanBars == v
                Text(euclideousResetSpanLabel(v))
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { onSetResetSpanBars(v); resetSpanPopupOpen = false }
            }
        }
        .padding(16).frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
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
        let steps = max(2, min(16, line.steps))
        let hitSteps = euclideousLapHitSteps(pulses: line.pulses, steps: steps, rotate: line.rotate,
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
        return euclideousFooterStates(hitSteps: hitSteps, lapSteps: steps, prediction: prediction, riffRanksResolved: riff.ranksResolved, anyLit: anyLit)
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
            EuclidLaneBox(idx: idx, line: line, width: innerWidth, height: cometRowH, accent: accent,
                          // WHOLE-CARD OUTLINE (ferry §1.4): `selected` here used to draw EuclidLaneBox's own
                          // border/fill around just this row (the step-bar area) — always `false` now; the
                          // selection indicator moved to a single outline around the ENTIRE card below.
                          selected: false, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: line.rate ?? .r1_16, spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          // RHYTHM GESTURE CONTROLS (Paul 2026-10-14, re-enabled — mirrors MASK's own
                          // identical wiring, `maskStepBar` below, just targeting this lane's REAL
                          // pulses/rotate instead of its mask's): up adds hits, down removes, left/right
                          // is offset — routed through the SAME `euclideousSliderCommit` the RHYTHM tab's
                          // own HITS/OFFSET sliders use, so an edited (hand-drawn) pattern rebuilds/round-
                          // trips identically whichever control you drag, and OFFSET can't disagree with
                          // the slider's own just-fixed drag-direction mirror.
                          onRotateDelta: { d in euclideousApplyRhythmX(idx, d) },
                          onHitsDelta: { d in euclideousApplyRhythmY(idx, d) },
                          onStepsDelta: { d in edit(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },   // PINCH — the one thing explicitly kept on the comet bar itself
                          onAllRotateDelta: { d in euclideousApplyAllRhythmX(d) },
                          onAllHitsDelta: { d in euclideousApplyAllRhythmY(d) },
                          onDragState: { point, allRows in euclideousRhythmDragState(idx, point, allRows) },
                          onSelect: { selectedLane = idx },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          // LANE FOOTER BANDS (2026-10-13 ferry, "footers inside the step cells" — supersedes
                          // the separate trailing row the comment here used to describe): a pure array, not a
                          // view — `EuclidCometBar` draws each step's own band directly inside that step's
                          // own cell rect now, so there's no separate row height/gap to budget here at all.
                          footerStates: laneFooterStates(idx, line),
                          stepCountBadge: AnyView(stepCountBadge(steps)),
                          stepCountBadgeWidth: stepCountBadgeTotalWidth,
                          // EXACT DIMENSIONS (2026-10-13 ferry): zero self-padding, 6pt spacing, the CHIP+
                          // triangle play button, flat LANE-100/#2c2f36 cell colours, the hand-placed notch.
                          compact: true)
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
        // WHOLE-CARD SELECTION OUTLINE: "2pt border: LANE-100 when the card is selected, transparent
        // otherwise" (this ferry's own literal spec) — a plain overlay stroke, never consuming layout space,
        // so toggling selection can't shift where the content sits (the `cardInset` padding above already
        // accounts for this 2pt, per that ferry's own "8pt padding... 2pt border" framing).
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedLane == idx ? lane100(accent) : Color.clear, lineWidth: 2))
        .clipped()
    }

    // THE COUNT BOX (2026-10-13 "lane card, exact dimensions" ferry, literal): "CHIP fill, 9pt radius,
    // number 15pt heavy TEXT, centred." Simplified from the old output-chip/NO-OUT sub-display — that per-
    // lane routing readout is now the RHYTHM tab's own dedicated Emitters row (A·B·C·D, part of this SAME
    // ferry's own RHYTHM table), making the count box's old secondary content redundant; dropped here rather
    // than kept alongside it. `accent`/`mask` params are gone — this box no longer needs either.
    private var stepCountBadgeTotalWidth: CGFloat { 44 }
    private func stepCountBadge(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(patternSelectedText)
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

        func verticalSlider(_ field: EuclideousSliderField) -> some View {
            EuclideousSlider(
                field: field, line: line, accent: accent, width: leftSliderW, height: rowHeight, horizontal: false,
                onCommit: { mutate in edit(idx, mutate) },
                onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(field, &$0) } },
                onRevertToEuclid: { edit(idx) { $0.customHits = nil } })
        }
        func horizontalSlider(_ field: EuclideousSliderField) -> some View {
            EuclideousSlider(
                field: field, line: line, accent: accent, width: halfW, height: rightRowH, horizontal: true,
                onCommit: { mutate in edit(idx, mutate) },
                onDoubleTap: { edit(idx) { euclideousSliderDoubleTapDefault(field, &$0) } },
                onRevertToEuclid: { edit(idx) { $0.customHits = nil } })
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
                    case .mask: return line.maskResolved.enabledResolved
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
                .contentShape(Rectangle())
                .onTapGesture { if idx < laneTab.count { laneTab[idx] = t } }
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
        case .mask:
            let maskCometH = max(1, contentAreaH - contentLineH - sp4)
            VStack(spacing: sp4) {
                maskCometRow(idx, line, accent, width: fullWidth, height: maskCometH)
                maskLine2(idx, line, accent, rowH: contentLineH, width: fullWidth)
            }
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
                let active = ((mask >> UInt8(b)) & 1 != 0) && ((mainOutMask >> UInt8(b)) & 1 != 0)
                // ROUND (Paul 2026-10-14: "like the buttons on top of the page, strictly no more space") —
                // mirrors `mainOutToggle`'s own plain `Circle()` fill/stroke exactly; the OUTER footprint
                // (`.frame(maxWidth: .infinity).frame(height: rowH)`, the tap target) is BYTE-IDENTICAL to
                // before — only the drawn shape inside it shrinks from a cell-filling RoundedRectangle to a
                // true circle sized to `rowH` (the row's own existing height, never larger), centred in the
                // unchanged cell, so the row's total width/height can't grow.
                Text(names[b]).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(active ? patternEmitterActiveText : patternUnselectedText)
                    .frame(width: rowH, height: rowH)
                    .background(Circle().fill(active ? lane100(accent) : patternUnselectedFill))
                    .overlay(Circle().stroke(active ? lane100(accent) : Color.clear, lineWidth: 1))
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
                    .accessibilityLabel("Emitter \(names[b])")
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
        .frame(width: halfW, height: blockH)

        let outHalf = VStack(spacing: gap) {
            HStack(spacing: 3) {   // exact-dimensions ferry: 3pt between the direction group and INV
                directionRow(idx, line, accent, rowH: rowH).frame(maxWidth: .infinity)
                invButton(idx, line, accent, rowH: rowH)
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
        let stepRanks = euclideousRiffStepRanks(ranks: riff.ranksResolved, invert: line.riffInvertResolved, transpose: line.melodyTransposeResolved)
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
        VStack(spacing: sp8) {
            riffTopRow(idx, line, accent, height: 90)
            riffModesRow(idx, line, accent, fullWidth: fullWidth).frame(height: 48)
            melodyValuesRow(idx, line, accent, fullWidth: fullWidth).frame(height: 48)
                .opacity(line.riffOnResolved ? 1.0 : 0.42)
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
                                 extendedPool: [Int], flatKey: Bool, highRanks: Set<Int>, reachable: Set<Int>,
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
            return euclideousNoteViewName(UInt8(raw), flatKey: flatKey)
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
            rotate: line.riffRotateResolved, ranks: riff.ranksResolved, invert: line.riffInvertResolved,
            transpose: line.melodyTransposeResolved) : []
        let extendedPool = euclideousGlobalPoolExtended(sortedRaw: riffLivePool.map { Int($0) })
        let flatKey = noteSource == .key ? euclideousKeyIsFlat(keyRoot, scaleType: keyType) : true
        return HStack(spacing: 3) {
            ForEach(1...8, id: \.self) { rank in
                notesKeyColumn(idx, line, accent, rank: rank, poolCount: poolCount, extendedPool: extendedPool,
                                flatKey: flatKey, highRanks: highRanks, reachable: reachable,
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
                    Text("NOTES VEL").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
                    Spacer()
                    Text(euclideousSigned(value)).font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0xF2F4F7)).lineLimit(1)
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
        return HStack(spacing: sp4) {
            notesStrip(idx, line, accent, height: 210)
            VStack(spacing: sp4) {
                notesKeysRow(idx, line, accent, keyHeight: 92, chipHeight: 24)
                notesOctaveTopRow(idx, line, accent, height: 40)
                notesVelBar(idx, line, accent)
            }
            .opacity(isOn ? 1.0 : 0.42)
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
    private func maskStepBar(_ idx: Int, _ m: EuclidLineMask, _ accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let n = max(2, min(16, m.stepsResolved))
        let k = max(0, min(n, m.pulsesResolved))
        let rotate = m.rotate ?? 0
        let pos = idx < maskPositions.count ? maskPositions[idx] : -1
        let insetL: CGFloat = 6, insetR: CGFloat = 6
        // SENSITIVITY, matching `EuclidCometBar`'s own convention exactly (Router.swift's box geometry, not
        // the gesture pad's SEPARATE 14pt visual padding below — that padding only shrinks the pad's own
        // touch area, it was never part of the box-pitch calculation EuclidCometBar itself uses either).
        let rotateStepPt = euclidBoxGeometry(n: n, usableWidth: max(1, width - insetL - insetR)).pitch
        return ZStack {
            Canvas { ctx, size in
                var buf = [Bool](repeating: false, count: n)
                euclidPatternInto(&buf, pulses: k, steps: n, rotation: rotate)
                let midY = size.height / 2
                let usableW = max(1, size.width - insetL - insetR)
                let (boxW, gap, _) = euclidBoxGeometry(n: n, usableWidth: usableW)
                // RAISED 30→60 (Paul 2026-10-11, the PATTERN/MASK layout move — this bar now has real
                // extra height to use, where it used to sit capped inside a flat 36pt row regardless; a
                // judgment call on the new ceiling itself, not device-verified against how it actually
                // looks at the new, much taller container height.
                let boxH = min(60, size.height - 6)
                let corner = min(5, boxW / 2.2)
                for i in 0..<n {
                    let rect = CGRect(x: insetL + CGFloat(i) * (boxW + gap), y: midY - boxH / 2, width: boxW, height: boxH)
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
            maskStepBar(idx, m, accent,
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
    private func euclideousApplyAllRhythmX(_ d: Int) {
        onEdit { lines in for i in lines.indices { let n = max(2, min(16, lines[i].steps)); lines[i].rotate = ((lines[i].rotate - d) % n + n) % n } }
    }
    private func euclideousApplyAllRhythmY(_ d: Int) {
        onEdit { lines in for i in lines.indices { let n = max(2, min(16, lines[i].steps)); lines[i].pulses = max(0, min(n, lines[i].pulses + d)) } }
    }
    /// Captures the gesture-start snapshot ONCE (the first non-nil point of a NEW gesture — `onDragState`
    /// reports a non-nil point on every `.changed` tick, so a naive "always capture" would silently re-
    /// freeze the snapshot every tick, breaking the round-trip-to-start guarantee `euclideousSliderCommit`'s
    /// own HITS rebuild depends on) and clears all gesture state at gesture-end (nil point).
    private func euclideousRhythmDragState(_ idx: Int, _ point: CGPoint?, _ allRows: Bool) {
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
        dragHUDInfo = EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
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
    private func riffGridView(maxWidth: CGFloat, rowH: CGFloat) -> some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        // MIDI IN/CHORD/KEY moved to the header (2026-10-14) — the grid reclaims the width the old
        // vertical source tabs used to occupy; only the label column's own gap is left to account for.
        let sideOverhead = riffLabelColW + sp4
        let gridW = max(1, maxWidth - sideOverhead)
        let cellW = max(1, (gridW - sp8 * 2 - sp4 * CGFloat(n - 1)) / CGFloat(n))
        // RULE 6, LITERAL: "keeping them square" — the cell is the smaller of its width-derived and
        // height-derived candidate, matching this page's own established "fit always wins over a target"
        // convention elsewhere (the lane grid/riff-panel split uses the identical idea).
        let cellH = min(max(1, rowH), cellW)
        let source = noteSource
        let pool = riffLivePool
        // LIVE STATE (rule, "Live states" §1): MIDI IN with nothing held — no arrows anywhere on the grid.
        // `riffGridCell` already draws nothing for a lane with no `riffMarker`/dot cell match, and an empty
        // pool means NO rank can resolve a note at all, so this falls out of the existing per-cell logic
        // without a special case — confirmed by reading, not assumed, since `riffMarker` is only ever set
        // from a genuine NOTE VIEW event or a non-rest grid read, neither of which a silent lane produces.
        let midiEmpty = source == .midi && pool.isEmpty
        return VStack(alignment: .leading, spacing: sp4) {
            Text("RIFF · SHARED").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            if midiEmpty {
                Text("HOLD NOTES TO PLAY").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xAAB0BA))
            }
            // COLUMN NUMBERS (Part 1 rule 8, kept from the markers ferry): "number the riff columns 1-8
            // above the grid, 10pt, #8a909a" — now offset by the label column's own width + gap so the
            // numbers still land directly over the grid, not the label column.
            HStack(spacing: sp4) {
                Color.clear.frame(width: riffLabelColW)
                ForEach(0..<n, id: \.self) { col in
                    Text("\(col + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: 0x8A909A))
                        .frame(width: cellW, height: riffDotRowH)
                }
            }
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
                                    riffGridCell(col: col, rank: rank, ranks: ranks, cellW: cellW, cellH: cellH, n: n, suppressMarkers: midiEmpty)
                                }
                            }
                        }
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
        let flatKey = source == .key ? euclideousKeyIsFlat(keyRoot, scaleType: keyType) : true
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
                let label: String = hasNote ? euclideousNoteViewName(noteValue, flatKey: flatKey) : "–"
                Text(label).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(hasNote ? (isReal ? Color(hex: 0xDFE3EA) : Color(hex: 0xDFE3EA).opacity(0.55)) : Color(hex: 0x4A4E57))
                    .frame(width: riffLabelColW, height: cellH, alignment: .trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hasNote ? "Rank \(rank), \(euclideousAccessibleNoteName(noteValue, flatKey: flatKey))" : "Rank \(rank), no note")
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
        onEditRiff { r in
            var rr = (0..<n).map { k -> Int in let rv = r.ranksResolved; return k < rv.count ? rv[k] : 0 }
            if col < rr.count { rr[col] = (toggle && rr[col] == rank) ? 0 : rank }
            r.ranks = rr; r.steps = n
        }
    }

    /// One riff-grid matrix cell — an "occupant" is either a riff-on lane whose `riffMarker` sits here (an
    /// arrow) or a riff-off lane whose fixed-note dot sits here (a dot). REDESIGNED (Paul 2026-10-13: "the
    /// arrows... have black background, please fix this. I'd like the arrow to fill the corner of the cell
    /// that corresponds with the position of the Euclid lane controls") — SUPERSEDES the 2026-10-12 ferry's
    /// own rules 5/6 entirely (whole-cell `#15171C` dark fill + horizontal lane-order banding). The "black
    /// background" WAS that whole-cell fill, not anything the glyph itself drew — removed outright; a
    /// marker-holding cell now keeps the SAME plain on/off fill every other cell has, unconditionally. Each
    /// lane gets ONE FIXED CORNER, mirroring exactly where that lane's own card sits in the real 2×2 lane-
    /// card grid (`portraitLayout`/`landscapeLayout`'s own literal `HStack{0,1}` top row / `HStack{2,3}`
    /// bottom row) — lane 0 top-left, lane 1 top-right, lane 2 bottom-left, lane 3 bottom-right — so the
    /// corner a marker lights up in always points at that lane's own control card. Since each lane owns a
    /// DISTINCT corner, two lanes sharing one cell can never collide or need count-dependent sizing the way
    /// banding did; glyph size is now a function of the quadrant's own (half-cell) size alone.
    private func riffGridCell(col: Int, rank: Int, ranks: [Int], cellW: CGFloat, cellH: CGFloat, n: Int, suppressMarkers: Bool = false) -> some View {
        struct Occupant { let lane: Int; let isArrow: Bool; let onRest: Bool }
        var occupants: [Occupant] = []
        // LIVE STATE (ferry "Live states" §1, literal): MIDI IN with nothing held draws NO arrows anywhere
        // on the grid — `suppressMarkers` is the one explicit override (`riffMarker` can briefly still hold
        // a STALE position from before the pool went empty, since nothing clears it on its own).
        if !suppressMarkers {
            for i in 0..<min(4, lines.count) {
                // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry): "a lane with the riff
                // off draws no marker" — the old `riffOffDotCell` branch (a dot for a riff-off lane's own
                // fixed note pick) is removed entire, not just disabled; `riffMarker[i]` is already nil for
                // a riff-off lane (`updateRiffMarkers`'s own guard), so this is now the ONLY source of an
                // occupant. `Occupant.isArrow`/`riffMarkerGlyph`'s own dot-drawing branch are left in place,
                // unreachable — harmless, flagged rather than silently left for a future reader to puzzle
                // over why a dot branch never fires.
                if let m = riffMarker[i], m.col == col, m.row == rank {
                    let onRest = col < ranks.count && ranks[col] == 0
                    occupants.append(Occupant(lane: i, isArrow: true, onRest: onRest))
                }
            }
        }
        let on = col < ranks.count && ranks[col] == rank
        // LANE → CORNER, matching the real lane-card grid exactly (see this function's own doc comment).
        let corners: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        // OVERFLOW FIX (2026-10-13 adversarial review): the old flat `max(8, ...)` floor could exceed the
        // glyph's own half-cell quadrant whenever `min(cellW,cellH) < 16` — this codebase's own history
        // already documents cells shrinking to ~7.4pt on a real narrow portrait panel, so this wasn't
        // theoretical. `halfCell` is the true available space (the quadrant's own smaller dimension); the
        // floor is now `min(4, halfCell)` instead of a flat `8` — mathematically provably never exceeds
        // `halfCell` (both arguments to the outer `max` are individually ≤ halfCell, so their max is too,
        // and wrapping in `min(16, ...)` can only shrink further) — the glyph can no longer push past its
        // own quadrant into the neighbouring one.
        let halfCell = min(cellW, cellH) / 2
        let glyphSize = min(16, max(halfCell * 0.84, min(4, halfCell)))
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                // rule 5: "keeps its light selection border" — an ambient 1pt light border on every cell,
                // unconditionally (unaffected by this redesign).
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.12), lineWidth: 1))
            ForEach(occupants, id: \.lane) { o in
                let accent = laneAccents[o.lane % laneAccents.count]
                let corner = corners[o.lane % corners.count]
                Group {
                    if o.isArrow && o.onRest {
                        // rule 7, now scoped to just this lane's own corner (not the whole cell, which no
                        // longer has a single exclusive "occupied" state to dash) — a FILL/TIE landing on a
                        // rest still reads as distinct from a normal real-rank hit.
                        riffMarkerGlyph(lane: o.lane, isArrow: o.isArrow, accent: accent, glyphSize: glyphSize)
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0x8A909A), style: StrokeStyle(lineWidth: 1, dash: [2, 1])))
                    } else {
                        riffMarkerGlyph(lane: o.lane, isArrow: o.isArrow, accent: accent, glyphSize: glyphSize)
                    }
                }
                // CENTERING FIX (Paul 2026-10-14, "use exactly quarter of the button and ensure the direction
                // arrow is centered within that and fills the maximum space without changing the size"): this
                // inner frame IS exactly one quarter of the cell (cellW/2 × cellH/2, unchanged) — the bug was
                // its alignment: `corner` (e.g. `.topLeading`) pushed the glyph toward the OUTER cell's own
                // corner A SECOND TIME, inside its own quarter — so the arrow sat tucked into a sub-corner of
                // the quarter rather than centred within it. `.center` fixes that; `glyphSize` itself (already
                // ~84% of the quarter's own smaller dimension, unchanged below) is what "fills the maximum
                // space" — only the alignment, not the size, changes here.
                .frame(width: max(1, cellW / 2), height: max(1, cellH / 2), alignment: .center)
                // CONTRAST FIX (Paul 2026-10-13, third same-day ferry: "the arrows... [are] feint against the
                // background, [ape] the colour scheme on the processor box play button, so use the same
                // background colour but only in the active corner"): the glyph used to sit directly on the
                // cell's own on/off fill (white 0.85 or 0.08) with nothing behind it, which washed out against
                // a lit (bright white) cell especially. `patternUnselectedFill` (#2A2D34) is the EXACT chip
                // colour `playButton(on:)`'s compact variant already uses for its own background — reused
                // here, not a new colour, so the marker's corner reads as the same "control chip" language as
                // the lane's own PLAY/STOP button. Scoped to ONLY this occupant's own quadrant (the `ForEach`
                // already confines it to the lane's one active corner) — an empty corner with no occupant
                // keeps the cell's plain on/off fill, unchanged.
                .background(RoundedRectangle(cornerRadius: 3).fill(patternUnselectedFill))
                // This OUTER frame is the one that places the whole quarter (background + centred glyph) at
                // this lane's own corner of the FULL cell — unchanged, still `corner`, not `.center`.
                .frame(width: cellW, height: cellH, alignment: corner)
            }
        }
        .frame(width: cellW, height: cellH)
        // The per-cell gesture is GONE — `riffGridView`'s own drag overlay now owns tap AND drag for the
        // whole matrix at once (see `riffDragLastCell`'s doc comment), so a plain tap on a single cell and a
        // continuous drag across several both land here, in `riffSetRank`.
        // ACCESSIBILITY (ferry's own literal text: "Step 3, E♭, lane 1 here, next up"). The note name
        // resolves `riffLivePool` (already a live page property — "the ascending notes currently feeding the
        // riff's own pool") at this cell's own rank, reusing `euclideousNoteViewName`/`euclideousKeyIsFlat`
        // (Derivations.swift) exactly as this page's own NOTE VIEW panel already does elsewhere — omitted
        // (falls back to the bare "Step N" form) only when the pool doesn't currently reach this rank.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(occupants.isEmpty ? "" : {
            let flatKey = euclideousKeyIsFlat(keyRoot, scaleType: keyType)
            let noteName = (rank >= 1 && rank <= riffLivePool.count) ? euclideousNoteViewName(riffLivePool[rank - 1], flatKey: flatKey) : nil
            let stepPart = noteName.map { "Step \(col + 1), \($0)" } ?? "Step \(col + 1)"
            return occupants.map { o in
                o.isArrow ? "\(stepPart), lane \(o.lane + 1) here, \(riffMarkerDirectionWord(o.lane, lines[o.lane]))"
                          : "Lane \(o.lane + 1)'s fixed note here"
            }.joined(separator: "; ")
        }())
    }
    /// "next up" / "next down" for the accessibility label — a plain-English gloss of the SAME comparison
    /// `riffMarkerGlyph` uses for its own arrow glyph, so the two can never disagree.
    private func riffMarkerDirectionWord(_ lane: Int, _ line: EuclidLine) -> String {
        guard riffMarker[lane] != nil, let pointsRight = riffMarkerPointsRight(lane, line) else { return "here" }
        return pointsRight ? "next up" : "next down"
    }
    /// One occupant's own glyph (rule 2/3): an arrow (riff-on) pointing toward its next move, with stride-
    /// based extra arrowheads/a number; a plain dot (riff-off, rule 4).
    private func riffMarkerGlyph(lane: Int, isArrow: Bool, accent: Color, glyphSize: CGFloat) -> some View {
        Group {
            if !isArrow {
                Circle().fill(lane100(accent)).frame(width: min(10, glyphSize * 0.4), height: min(10, glyphSize * 0.4))
            } else {
                let line = lane < lines.count ? lines[lane] : EuclidLine(noteSel: .all)
                let hasMarker = lane < riffMarker.count && riffMarker[lane] != nil
                let pointsRight = hasMarker ? (riffMarkerPointsRight(lane, line) ?? true) : true
                let glyph = pointsRight ? "▶" : "◀"
                let stride = line.riffStrideResolved
                HStack(spacing: 1) {
                    if stride <= 3 {
                        ForEach(0..<max(1, stride), id: \.self) { _ in
                            Text(glyph).font(.system(size: glyphSize, weight: .heavy)).foregroundColor(lane100(accent))
                        }
                    } else {
                        Text(glyph).font(.system(size: glyphSize, weight: .heavy)).foregroundColor(lane100(accent))
                        Text("\(stride)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(lane100(accent))
                    }
                }
            }
        }
    }

    // MARK: - NOTE VIEW, phase 1 (Paul 2026-10-10 ferry — working name, final name to come): four lane strips,
    // each a continuously-moving rhythm timeline + a note box showing the pitch actually struck, plus (a
    // direct follow-up ferry) a 14pt per-strip summary label. Replaces the dashed placeholder the layout
    // ferry removed — "supersedes the previous ferry's instruction to delete that placeholder: replace it
    // with NOTE VIEW instead" (§0.1).
    //
    // PANEL CHROME (§0.2, "same panel style as the riff panel"): the SAME `.padding(sp8)` +
    // `RoundedRectangle(cornerRadius: 12).fill(white 3.5%)` treatment `riffGridView` uses above — read as
    // covering the container treatment specifically, not a literal requirement for a title row too (riff's
    // own title exists to NAME a shared, page-level control; NOTE VIEW's 4 strips are self-evidently their
    // own content, and the panel's real height budget here is tight enough — shared 50/50 with riff, then
    // split 4 ways — that a title row would meaningfully squeeze the one thing this ferry actually specifies
    // in detail). Flagged as a judgment call, not silently assumed.
    private func noteViewPanel(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let innerH = max(1, maxHeight - sp8 * 2)
        let stripH = max(1, (innerH - sp4 * 3) / 4)   // §1.1: "equal height, 4pt gaps"
        let innerW = max(1, maxWidth - sp8 * 2)
        // §2.3, literal: ONE shared window size for all 4 strips, computed ONCE here (not re-derived per
        // strip, which would recompute the identical answer 4 times from the same inputs) — "fastest
        // PLAYING lane" excludes a disabled lane's own rate from the comparison (§2.6: a disabled lane
        // draws no marks at all, so its rate shouldn't be able to force the shared window narrower).
        let cyc = clock.stepBeats * Double(max(1, clock.cols))
        let fastestSub = lines.filter { $0.enabledResolved }.map { $0.rate?.beats ?? ArpRate.r1_16.beats }.min() ?? ArpRate.r1_16.beats
        let windowBeats = euclideousNoteViewWindowBars(fastestSub: max(0.03125, fastestSub), cyc: cyc, trackW: innerW - 56 - sp8) * cyc
        // DIVIDERS (UI polish ferry §3.6: "a subtle 1pt #22252C divider between strips") — `spacing: 0`
        // + an explicit divider slot replaces the old bare `spacing: sp4` gap; each divider slot is still
        // exactly `sp4` tall (the 1pt line centred within it via the second `.frame`), so the panel's total
        // height budget (`innerH`, computed above from `stripH*4 + sp4*3`) is byte-identical — the divider
        // rides IN the existing gap, it doesn't add a new one.
        // DSP FIX (Paul 2026-10-11, "review if there's a way we can keep the CPU down" — Euclideous is now
        // the app's default/always-open view, so its own steady-state cost matters far more than when it was
        // an occasional overlay): the 4 strips below used to each own TWO independent 60fps `TimelineView`s
        // (noteViewTrack + noteViewNoteBox) — 8 separate SwiftUI animation schedulers ticking concurrently
        // whenever the transport plays, EXACTLY the "per-cell TimelineView explosion" class this page's own
        // §1.2 DSP fix already named and fixed once for the riff-grid wipes. Re-checking here found the SAME
        // anti-pattern survived in NOTE VIEW: noteViewTrack's 4 instances were even gated IDENTICALLY
        // (`paused: !clock.playing`, no per-lane term at all) — pure redundancy, zero behaviour difference
        // between sharing one and running four. Consolidated into ONE shared `TimelineView` here, `liveBeat`
        // computed once and threaded down to every strip — collapses 8 schedulers into 1.
        // noteViewNoteBox's own pause WAS per-lane (`!(clock.playing && line.enabledResolved)`, to freeze a
        // disabled lane's box per §2.6) — checked rather than assumed safe to drop: `lastEvent`/`restFlash`
        // are themselves already frozen-by-construction once a lane stops striking (the engine simply never
        // pushes a new one), so the only residual effect of sharing this tick is letting an ALREADY-in-flight
        // brightness fade finish settling to its 40% floor instead of freezing mid-fade — a sub-beat-duration
        // difference (a GATE is a small fraction of one step), imperceptible in practice. Flagged as a
        // judgment call, not a silent assumption — worth a direct look if a disabled lane's box ever reads as
        // "still changing" on device.
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.playing)) { tl in
            let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { idx in
                    noteViewStrip(idx, width: innerW, height: stripH, cyc: cyc, windowBeats: windowBeats, liveBeat: liveBeat)
                    if idx < 3 {
                        Rectangle().fill(Color(hex: 0x22252C)).frame(height: 1).frame(height: sp4)
                    }
                }
            }
        }
        .padding(sp8)
        .frame(width: maxWidth, height: maxHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }

    /// One lane's strip (ferry 1 §1.1-§1.3 + ferry 2 §1.1-§1.4): a 14pt label row, then the track+playhead+
    /// note-box row filling whatever height remains. `liveBeat` rides down from `noteViewPanel`'s ONE
    /// shared `TimelineView` (the 2026-10-11 DSP fix) rather than each strip ticking its own.
    private func noteViewStrip(_ idx: Int, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double, liveBeat: Double) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let accent = laneAccents[idx % laneAccents.count]
        let labelH: CGFloat = 14
        let bodyH = max(1, height - labelH)
        return VStack(alignment: .leading, spacing: 0) {
            noteViewLabelRow(idx, line, accent: accent, width: width)
            noteViewTrackRow(idx, line, accent: accent, width: width, height: bodyH, cyc: cyc, windowBeats: windowBeats, liveBeat: liveBeat)
        }
        .frame(width: width, height: height, alignment: .leading)
        // CONNECT EACH LANE'S PARTS (usability ferry §5, literal): "its NOTE VIEW strip: a 1pt LANE-100
        // outline" when the lane is selected — the same `selectedLane` state the card outline already
        // reads (`laneCard`'s own `.overlay(...stroke(selectedLane == idx ? lane100...))`), so the two can
        // never disagree about which lane is highlighted.
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selectedLane == idx ? lane100(accent) : Color.clear, lineWidth: 1))
        // §5, literal: "tapping a NOTE VIEW strip's track area also selects that lane" — the BASE content's
        // own tap target, covering the strip's full bounds; the 30pt pop-up-opening overlay below is drawn
        // (and hit-tests) ON TOP of it, so a tap landing inside that 30pt zone is caught there first (opens
        // the pop-up, per "the label still opens the pop-up") while anything below it falls through to here.
        .contentShape(Rectangle())
        .onTapGesture { selectedLane = idx }
        .overlay(alignment: .top) {
            // THE TAP TARGET (§1.1, literal): "a 30pt-tall touch area, extending invisibly into the top
            // of the track." An `.overlay` never feeds back into its host's own layout size, so this
            // doesn't steal any height from the track below — it just paints/hit-tests an invisible 30pt
            // zone OVER the label (14pt) plus the track's own top 16pt. Scoped to exactly 30pt so "taps
            // on the track and note box must never open it" holds by construction: nothing below this
            // overlay's own bounds is affected.
            // §3.1's pressed-state: `minimumDuration: 0` fires `perform` immediately on release (functionally
            // a plain tap, byte-identical timing to the old `.onTapGesture`), while `pressing:` gives the
            // touch-down/touch-up signal `.onTapGesture` alone never exposed.
            // BEHAVIOUR RULE 6 (Paul 2026-10-13 ferry): tapping the summary label now selects this lane AND
            // switches it to a melodic tab — the melody pop-up it used to open is retired entire. RIFF/NOTES
            // SPLIT (third same-day ferry) replaced the single MELODY destination with two tabs; NOTES is
            // the chosen landing (a judgment call, flagged — the ferry never re-specified this one rule once
            // MELODY itself was split, and NOTES is the more direct successor to what this label used to
            // summarize: the lit-pitch/octave state, not the riff's own walk settings).
            Rectangle().fill(Color.clear).frame(width: width, height: 30)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity,
                                     pressing: { down in if idx < labelPressed.count { labelPressed[idx] = down } },
                                     perform: { selectedLane = idx; if idx < laneTab.count { laneTab[idx] = .notes } })
        }
    }

    // MARK: - The strip label (NOTE VIEW strip labels ferry, Paul 2026-10-10): display-only, 14pt,
    // updates automatically since it's a pure read of `line`'s own already-live fields every redraw — no
    // new state, no new poll. TAPPABLE as of the melody pop-up ferry (§1.1) — the actual tap handling
    // lives on `noteViewStrip`'s own 30pt overlay above, not here, so this row no longer declares
    // `.allowsHitTesting(false)` (that would otherwise read as contradicting "the label is tappable" to
    // a future reader, even though the overlay sitting above it in z-order would already intercept the
    // touch either way).

    /// §1.3/§1.4 (strip labels ferry), literal: a 6pt LANE-100 dot, then the joined text at 10pt `#AAB0BA`.
    private func noteViewLabelRow(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat) -> some View {
        // §3.1, literal: a "›" chevron at the right end (after "+n" if present — already the string's own
        // tail, so appending here always lands after it) + a pressed state (background lightens to
        // #22252C while touched). The chevron/dot-and-gap width is reserved OUTSIDE the text's own budget
        // so `noteViewLabelText`'s own fit/truncation math (textW) never has to account for it.
        let chevronW: CGFloat = 10
        let dotAndGap: CGFloat = 6 + 4
        let textW = max(1, width - dotAndGap - chevronW)
        let pressed = idx < labelPressed.count && labelPressed[idx]
        return HStack(spacing: 4) {
            Circle().fill(lane100(accent)).frame(width: 6, height: 6)
            Text(noteViewLabelText(line, maxWidth: textW))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
            Text("›").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0xAAB0BA).opacity(0.6))
        }
        .frame(width: width, height: 14, alignment: .leading)
        .background(pressed ? Color(hex: 0x22252C) : Color.clear)
    }
    /// The lit-notes layer's own resolved pitches, ascending, for display (summary label / note box). Reuses
    /// `euclideousGlobalPoolExtended` (already an exact mirror of `riffResolve(wrap:.fold)` for ranks 1...8 —
    /// the only ranks a lit-note button can ever address) so this can never show a pitch the engine wouldn't
    /// actually resolve to that same rank. `octaveResolved` (never `riffOctaveResolved`) applies, per "INV
    /// and TRANS do not apply" — only OCT does.
    private func euclideousLitPitches(_ line: EuclidLine) -> [Int] {
        let raw = riffLivePool.map { Int($0) }.sorted()
        guard !raw.isEmpty else { return [] }
        let extended = euclideousGlobalPoolExtended(sortedRaw: raw)
        let poolCount = min(raw.count, 8)
        let oct12 = 12 * line.octaveResolved
        var out: [Int] = []
        for rk in 1...8 where (line.litNotesResolved & (1 << (rk - 1))) != 0 {
            if rk - 1 < extended.count { out.append(extended[rk - 1] + oct12) }
        }
        if line.topLitResolved, poolCount - 1 < extended.count { out.append(extended[poolCount - 1] + oct12) }
        if line.top2LitResolved {
            let lo = max(1, poolCount) - 1
            for i in [lo, poolCount - 1] where i >= 0 && i < extended.count { out.append(extended[i] + oct12) }
        }
        return out.sorted()
    }
    /// LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Elsewhere-on-page §2, literal:
    /// riff on — the existing riff-item list (minus source, already removed) plus " + n" when something is
    /// lit; riff off — the lit notes in pitch order ("C3 G3"), TOP/TOP2 shown as "TOP"/"TOP 2"; nothing lit
    /// and riff off — the single item "NO NOTES" (handled by the caller returning early on an empty list
    /// from `noteViewLabelText`, mirroring how `euclideousSilenceReason`'s own "NO NOTES" already covers the
    /// note box for the identical condition).
    private func noteViewLabelItems(_ line: EuclidLine) -> [String] {
        guard line.riffOnResolved else {
            // RIFF OFF: list the lit pitches in pitch order; TOP/TOP2 render as themselves, not their
            // resolved note name, even though they're sorted into the SAME ascending position their pitch
            // occupies (per the ferry's own "TOP and TOP 2 show as 'TOP' and 'TOP 2'").
            let raw = riffLivePool.map { Int($0) }.sorted()
            guard !raw.isEmpty else {
                // No pool to resolve against at all — still list the TOGGLE names (dashes have no meaning
                // here; the note box's own silence-reason branch covers the empty-pool case).
                var names: [String] = []
                for rk in 1...8 where (line.litNotesResolved & (1 << (rk - 1))) != 0 { names.append("N\(rk)") }
                if line.topLitResolved { names.append("TOP") }
                if line.top2LitResolved { names.append("TOP 2") }
                return names
            }
            let extended = euclideousGlobalPoolExtended(sortedRaw: raw)
            let poolCount = min(raw.count, 8)
            let oct12 = 12 * line.octaveResolved
            let flatKey = euclideousKeyIsFlat(keyRoot, scaleType: keyType)
            var pairs: [(pitch: Int, label: String)] = []
            for rk in 1...8 where (line.litNotesResolved & (1 << (rk - 1))) != 0 {
                // RIFF/NOTES SPLIT: each rank's OWN per-note octave shift applies here too — a C3 shifted −1
                // must read C2 in this label, matching the key buttons' own display (NOTES tab) exactly.
                if rk - 1 < extended.count { let p = extended[rk - 1] + oct12 + 12 * line.noteOctShiftsResolved[rk - 1]; pairs.append((p, euclideousNoteViewName(UInt8(max(0, min(127, p))), flatKey: flatKey))) }
            }
            if line.topLitResolved, poolCount - 1 < extended.count { pairs.append((extended[poolCount - 1] + oct12, "TOP")) }
            if line.top2LitResolved {
                let lo = max(1, poolCount) - 1
                for i in [lo, poolCount - 1] where i >= 0 && i < extended.count { pairs.append((extended[i] + oct12, "TOP 2")) }
            }
            return pairs.sorted { $0.pitch < $1.pitch }.map { $0.label }
        }
        // RIFF ON: today's items list (source already removed, per the 2026-10-12 ferry); the direction
        // reads `euclideousRiffDirResolved` (DRUNK/RANDOM→FWD) so a legacy doc's display can't disagree
        // with what the WALK row itself shows as lit.
        var items: [String] = ["RIFF " + riffDirShortLabel(line.euclideousRiffDirResolved)]
        let n = line.riffLengthResolved
        let shift = ((line.riffRotateResolved % n) + n) % n
        if shift != 0 { items.append("SHIFT \(shift)") }
        if line.riffOctaveResolved != 0 { items.append("OCT \(euclideousSigned(line.riffOctaveResolved))") }
        if line.riffLockResolved { items.append("LOCK") }
        if line.riffInvertResolved { items.append("INV") }
        if line.riffOnRestResolved != .skip { items.append(line.riffOnRestResolved == .fill ? "REST FILL" : "REST TIE") }
        if line.riffStrideResolved != 1 { items.append("STRIDE \(line.riffStrideResolved)") }
        if line.riffLengthResolved != 8 { items.append("LEN \(line.riffLengthResolved)") }
        if line.melodyTransposeResolved != 0 { items.append("TRANS \(euclideousSigned(line.melodyTransposeResolved))") }
        if line.riffAdvanceStepResolved { items.append("ADV STEP") }
        // " + n" (ferry §2, literal spacing): n = how many DISTINCT lit pitches sound alongside the riff
        // note this hit, i.e. the lit-layer's own resolved set minus whatever coincides with the riff note
        // itself — an honest best-effort DISPLAY count (the real dedup happens note-by-note in Router.swift;
        // this reads the SAME live pool to stay consistent, not a second, disagreeing source).
        // RIFF/NOTES SPLIT: the notes layer's own master switch gates this count — nothing is "lit" in the
        // sense that sounds alongside the riff if the whole layer is off, regardless of what's remembered.
        let litCount = line.notesOnResolved ? euclideousLitPitches(line).count : 0
        if litCount > 0 { items.append("+ \(litCount)") }
        return items
    }
    /// §3.2, literal: "never truncate in the middle of a word or show an ellipsis. If the line doesn't fit,
    /// drop whole items from the end and finish with '+n'." No live text-measurement API is available here
    /// (the same disclosed limitation as the axis-label fit-check built for the previous ferry) — estimates
    /// width via this file's own established 0.6×point-size monospaced-character convention. Tries the full
    /// item list first, then drops one item from the end at a time (re-joining with "+n" once anything is
    /// dropped) until the estimate fits — read literally, not reserving Source/Mode as a protected floor
    /// beyond the natural consequence of them being FIRST in the list (so they're the last to ever be cut).
    ///
    /// SAFETY MARGIN (this ferry §1.2/§3.5: "the NOTE VIEW label runs off the edge"/"text currently runs to
    /// or past the right edge" despite this exact drop-items mechanism already existing) — a ×1.15 fudge on
    /// the hand-estimated width, not a change to the dropping algorithm itself: this function's own
    /// disclosed limitation ("no live text-measurement API") means the 0.6×-per-character estimate is a
    /// GUESS, and an UNDER-estimate is exactly what would let a string the algorithm judges "fits" actually
    /// overflow on the real device — the one-sided failure mode this bug report is consistent with. Erring
    /// conservative (dropping one MORE item than strictly necessary in the rare case the estimate undershot)
    /// is the safe direction; erring generous is the one that reproduces this exact complaint.
    private func noteViewLabelText(_ line: EuclidLine, maxWidth: CGFloat) -> String {
        let items = noteViewLabelItems(line)
        // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry): "nothing lit and riff off: NO
        // NOTES" — `noteViewLabelItems`'s riff-off branch returns an empty list in exactly this case; the
        // drop-items algorithm below has nothing to show for an empty list (it would silently produce ""),
        // so this is handled explicitly, matching the note box's own identical silent state.
        guard !items.isEmpty else { return "NO NOTES" }
        let charWidth: CGFloat = 10 * 0.6 * 1.15
        func estimate(_ s: String) -> CGFloat { CGFloat(s.count) * charWidth }
        func joined(_ n: Int) -> String {
            let shown = items.prefix(n).joined(separator: " · ")
            let dropped = items.count - n
            return dropped > 0 ? "\(shown) · +\(dropped)" : shown
        }
        for n in stride(from: items.count, through: 1, by: -1) {
            let s = joined(n)
            if estimate(s) <= maxWidth { return s }
        }
        return joined(1)
    }

    // MARK: - The track + playhead + note box (ferry 1 §1.2/§2/§3/§4)

    // FLIPPED (Paul 2026-10-11): "right-to-left is what you expect on any piano roll... it also makes the
    // note being played more visible as it's not tucked offscreen." The note box now leads on the LEFT,
    // immediately beside the playhead; the track fills the REMAINING width on the right, where upcoming
    // marks enter and travel leftward toward it.
    private func noteViewTrackRow(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double, liveBeat: Double) -> some View {
        let noteBoxW: CGFloat = 56
        let gap: CGFloat = 8
        let trackW = max(1, width - noteBoxW - gap)
        return HStack(spacing: 0) {
            noteViewNoteBox(idx, line, accent: accent, width: noteBoxW, height: height, liveBeat: liveBeat)
            Color.clear.frame(width: gap)
            noteViewTrack(idx, line, accent: accent, width: trackW, height: height, cyc: cyc, windowBeats: windowBeats, liveBeat: liveBeat)
        }
        .frame(width: width, height: height)
    }

    /// The continuously-moving rhythm track (ferry 1 §2/§3) — one `TimelineView` per strip (a disclosed,
    /// behaviourally-equivalent simplification of "one shared TimelineView per panel": all 4 read the SAME
    /// `clock` anchor/tempo, so they tick in lockstep off the same display-link schedule regardless of
    /// whether they share one `TimelineView` instance or each own one). CAPPED AT 1/60 (usability ferry
    /// §1.2 DSP fix, "NOTE VIEW" named explicitly) — SUPERSEDES the earlier ferry's own "render at the
    /// display refresh rate" instruction (no cap at all), now that a newer, more urgent priority (the
    /// reported DSP spike) explicitly calls this view out by name. 1/60 is still imperceptibly different
    /// from a mark landing "exactly on the beat" to any human eye (a ProMotion display's own 120Hz is pure
    /// headroom no one can see used), while roughly halving this view's worst-case per-frame cost.
    private func noteViewTrack(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double, liveBeat: Double) -> some View {
        let running = clock.playing && line.enabledResolved   // §2.6: a stopped lane draws no marks
        let sub = max(0.03125, line.rate?.beats ?? ArpRate.r1_16.beats)
        let buf = euclideousNoteViewPattern(pulses: line.pulses, steps: line.steps, rotate: line.rotate, tilt: line.tiltResolved, patternMiss: line.patternMissResolved, customHits: line.customHitsResolved(max(2, min(16, line.steps))))
        let spanBeats = euclideousNoteViewSpanBeats(resetSpanBars: resetSpanBars, cyc: cyc)
        let dir = line.directionResolved
        return Canvas { ctx, size in
                guard windowBeats > 0 else { return }
                // BASELINE (UI polish ferry §3.3: "stopped lanes currently show nothing under their
                // label... draw the track baseline... so all four strips always look the same shape") — a
                // constant 1pt #2A2D34 line, drawn UNCONDITIONALLY (running or stopped), so every strip
                // keeps an identical base shape regardless of each individual lane's own play state; marks
                // (below) layer on top of it only while actually running.
                ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)), with: .color(Color(hex: 0x2A2D34)))
                // RE-CHECKED, a real bug fixed on an earlier pass: `euclideousNoteViewMarkX` makes any tick
                // with `age = tickBeat - nowBeat` in `0...windowBeats` visible — meaning FUTURE ticks up to
                // a full `windowBeats` ahead must be scanned, not just one. The original loop's upper bound
                // was a bare `latestTick + 1` (one tick ahead, a leftover from an earlier, wrong mental
                // model that only "the next tick" needed drawing) while its LOWER bound wastefully scanned
                // `lookback` ticks that can never satisfy `age >= 0` in the first place (tick `latestTick`
                // itself already has `age <= 0` by construction — anything earlier is strictly more
                // negative). Fixed: scan forward from `latestTick` through the full lookahead the window
                // actually promises, nothing behind it (the position function's own guard discards anything
                // that doesn't belong, so a little slack here costs nothing).
                if running {
                    let latestTick = Int((liveBeat / sub).rounded(.down))
                    let aheadTicks = Int((windowBeats / sub).rounded(.up)) + 1
                    for t in latestTick...(latestTick + aheadTicks) {
                        let tickBeat = Double(t) * sub
                        guard let x = euclideousNoteViewMarkX(tickBeat: tickBeat, nowBeat: liveBeat, windowBeats: windowBeats, trackW: size.width) else { continue }
                        let isHit = euclideousNoteViewIsHit(buf: buf, tickBeat: tickBeat, sub: sub, spanBeats: spanBeats, dir: dir)
                        // FADE-IN AT THE ENTRY EDGE (UI polish ferry §3.4: "marks entering... are cut off
                        // hard (half-marks look like a 'D'). Fade marks in over the first 12pt of the track
                        // instead of clipping them.") The ferry's own wording names the LEFT edge, but
                        // describes the PRE-FLIP layout (marks used to enter left, travel right) — this
                        // session's own direction flip (Paul 2026-10-11, "right-to-left is what you expect
                        // on any piano roll") moved the entry edge to the RIGHT (`x` near `size.width`); the
                        // fade is applied at whichever edge marks actually enter from NOW, matching the
                        // ferry's INTENT (soften the entry, wherever it is) rather than its now-stale literal
                        // side. `distFromEntry` is simply how far `x` sits from the track's own entry edge.
                        let distFromEntry = size.width - x
                        let fadeIn = distFromEntry < 12 ? max(0, distFromEntry / 12) : 1
                        noteViewDrawMark(&ctx, x: x, midY: size.height / 2, isHit: isHit, accent: accent, opacity: fadeIn)
                    }
                }
                // PLAYHEAD (§1.2, flipped 2026-10-11; §3.3 unconditional): fixed 2pt white-60% line at the
                // track's trailing edge — the LEFT edge (right beside the note box) — drawn every frame
                // regardless of `running`, so a stopped lane's track still shows where marks WOULD land,
                // just with none currently approaching it.
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 2, height: size.height)), with: .color(Color.white.opacity(0.6)))
            }
        .frame(width: width, height: height)
    }
    /// §3, literal mark styles. The hit's own 16pt tail fades RIGHT (behind the direction of travel, since
    /// marks move right→left toward the playhead on the left — flipped 2026-10-11, Paul: "right-to-left is
    /// what you expect on any piano roll"). `opacity` (UI polish ferry §3.4) fades a mark in over its first
    /// 12pt from the track's entry edge, applied as a layer-wide multiplier so it scales the WHOLE mark
    /// (tail gradient + head/dot alike) uniformly rather than needing a second opacity baked into each draw.
    private func noteViewDrawMark(_ ctx: inout GraphicsContext, x: CGFloat, midY: CGFloat, isHit: Bool, accent: Color, opacity: CGFloat = 1) {
        ctx.drawLayer { layer in
            layer.opacity = opacity
            if isHit {
                var tail = Path(); tail.move(to: CGPoint(x: x, y: midY)); tail.addLine(to: CGPoint(x: x + 16, y: midY))
                layer.stroke(tail, with: .linearGradient(Gradient(colors: [lane100(accent).opacity(0.6), lane100(accent).opacity(0)]),
                                                          startPoint: CGPoint(x: x, y: midY), endPoint: CGPoint(x: x + 16, y: midY)), lineWidth: 2)
                layer.fill(Path(ellipseIn: CGRect(x: x - 4, y: midY - 4, width: 8, height: 8)), with: .color(lane100(accent)))
            } else {
                // the hollow-ring "miss-playing" mark RETIRED 2026-10-10 (ferry §4.2) — there's only ever
                // one voice per lane now, so a silent step is always this plain dim dot, never a second
                // mark style.
                layer.fill(Path(ellipseIn: CGRect(x: x - 2, y: midY - 2, width: 4, height: 4)), with: .color(Color(hex: 0x3A3E47)))
            }
        }
    }

    /// The note box (ferry 1 §4) — a pure function of (the reconciled last event / rest-flash for this
    /// lane, the live extrapolated beat), evaluated fresh every frame; no event-queue bookkeeping happens
    /// here, that's already done once in AudioUnitViewController's own poll.
    /// `liveBeat` rides down from `noteViewPanel`'s shared `TimelineView` (2026-10-11 DSP fix — see that
    /// function's own comment for why dropping this box's former PER-LANE pause is safe in practice: the
    /// upstream `lastEvent`/`restFlash` snapshots already freeze by construction once a lane stops striking,
    /// so sharing the tick only lets an already-in-flight sub-beat fade finish settling, nothing new appears).
    private func noteViewNoteBox(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat, liveBeat: Double) -> some View {
        let lastEvent = idx < noteViewLastEvent.count ? noteViewLastEvent[idx] : nil
        let restFlash = idx < noteViewRestFlash.count ? noteViewRestFlash[idx] : nil
        let flatKey = euclideousKeyIsFlat(keyRoot, scaleType: keyType)
        // EXPLAIN SILENCE (usability ferry §2) — evaluated only while the TRANSPORT is actually running
        // ("a lane that's playing but cannot produce a note"); a fully stopped transport leaves NOTE VIEW
        // exactly as it already was (frozen on whatever it last showed), nothing new to explain.
        let silenceReason = clock.playing
            ? euclideousSilenceReason(line: line, mainOutMask: mainOutMask,
                                       riffAllRest: riff.ranksResolved.allSatisfy { $0 == 0 })
            : nil
        return noteViewNoteBoxContent(liveBeat: liveBeat, lastEvent: lastEvent, restFlash: restFlash, accent: accent, flatKey: flatKey, silenceReason: silenceReason)
            .frame(width: width, height: height)
    }
    /// §4.4/§4.5 brightness: kind 0/1 fade continuously over the gate (1.0→0.4); kind 3 (a tied hit) is a
    /// step — full brightness throughout the whole extended span, settling only once it genuinely ends —
    /// per §4.5's own distinct wording. A plain function, not inlined into the `@ViewBuilder` body above,
    /// since an `if/else` assigning to a scalar `let` fails Swift's result-builder transform there.
    private func noteViewBrightness(kind: UInt8, onsetBeat: Double, durationBeat: Double, liveBeat: Double) -> Double {
        if kind == 3 { return liveBeat < onsetBeat + durationBeat ? 1.0 : 0.4 }
        let t = durationBeat > 0 ? max(0, min(1, (liveBeat - onsetBeat) / durationBeat)) : 1
        return 1.0 - 0.6 * t
    }
    @ViewBuilder private func noteViewNoteBoxContent(liveBeat: Double, lastEvent: Router.EuclideousNoteViewEventSnapshot?, restFlash: Router.EuclideousNoteViewEventSnapshot?, accent: Color, flatKey: Bool, silenceReason: String? = nil) -> some View {
        // THE BOX ITSELF IS CONSTANT (UI polish ferry §3.1, literal: "every lane shows its note box AT ALL
        // TIMES: ... #22252C background, 8pt corner radius... an empty box when the lane hasn't played
        // yet") — a single base layer, drawn identically regardless of state. ROOT CAUSE of "lanes 1–3 show
        // floating text with no box, lane 4 shows an empty box": the three states below used to each draw
        // their OWN differently-styled background (6pt radius, and either 4%/6% white or a `lane20(accent)`
        // fill further multiplied by `brightness`, as low as ~0.4 × 0.2 ≈ 8% opacity) — subtle enough to
        // read as "no box, just floating text" against the page's own dark ground, and inconsistent between
        // states besides. Superseded by this ferry's own explicit, constant spec — CONTENT (the text) is
        // now the only thing that varies; the container never does.
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x22252C))
            // EXPLAIN SILENCE (usability ferry §2, literal): "shows the reason... in place of a note name" —
            // checked FIRST, fully replacing whatever restFlash/lastEvent would otherwise show. Safe to check
            // unconditionally ahead of them: a lane in one of these 7 states can't be genuinely sounding, so
            // the engine wouldn't be posting a real restFlash/lastEvent for it to begin with — the two are
            // mutually exclusive in practice, not just by this ordering.
            if let reason = silenceReason {
                Text(reason).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xAAB0BA)).multilineTextAlignment(.center).lineLimit(2)
                    .padding(.horizontal, 2)
            }
            // §4.5, SKIP: "show a grey '—' for one step's duration, then return to the previous note at
            // 40%" — the flash is checked first and, while active, fully REPLACES whatever the note box
            // would otherwise show; once it ends, falls straight through to `lastEvent`'s own (already-
            // 40%, since real time has passed) state below, with no special-case code needed for the
            // "return to" part.
            else if let rf = restFlash, liveBeat >= rf.onsetBeat, liveBeat < rf.onsetBeat + rf.durationBeat {
                Text("—").font(.system(size: padValueSize, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0x8A909A))
            } else if let ev = lastEvent {
                // RE-CHECKED: §4.4's general rule ("fades linearly... over the note's gate length") is for
                // a plain hit/miss (kind 0/1) — but §4.5's TIE case is worded distinctly ("keep showing the
                // held note at FULL brightness, fading FROM THE END of the extended note"), not "use 4.4's
                // formula with a longer input." Read literally: a tied note stays fully lit for its WHOLE
                // held span (it's still genuinely sounding) and only settles to the 40% floor once that
                // span is actually over — a step, not a second gradual ramp (the ferry names no separate
                // post-release fade duration, and §4.4's own closing line — "stays at 40% until the next
                // note" — already describes that floor as a plain settled state, not something reached via
                // its own fade). `kind == 3` (Router.swift, a tied hit) is the one case this applies to;
                // kind 0/1 keep the continuous ramp. (An `if/else` STATEMENT assigning to this `let`
                // directly, written inline here, fails to compile inside a `@ViewBuilder` body — Swift's
                // result-builder transform tries to treat the `if` as View-producing control flow, not a
                // plain scalar computation; moved to a bare (non-@ViewBuilder) function so ordinary
                // imperative code works as expected.)
                let brightness = noteViewBrightness(kind: ev.kind, onsetBeat: ev.onsetBeat, durationBeat: ev.durationBeat, liveBeat: liveBeat)
                let (primary, plusN) = noteViewPrimaryPlusN(ev, flatKey: flatKey)
                // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Elsewhere-on-page §1,
                // literal: "the riff note at the current size [padValueSize]. If lit notes sound with it,
                // add '+n' at 11pt" (riff on) / "the lowest sounding note plus '+n'" (riff off) — supersedes
                // the prior ferry's own "up to 3 names stacked" rule (§4.6) entire, not layered on top of it.
                VStack(spacing: 1) {
                    if let primary { Text(primary).font(.system(size: padValueSize, weight: .heavy, design: .monospaced)).lineLimit(1) }
                    if let plusN { Text(plusN).font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1) }
                }
                .foregroundColor(.white).opacity(brightness)
            }
            // else: nothing — the constant #22252C box above, with no content, IS "an empty box."
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    /// Elsewhere-on-page §1, literal: `ev.hasRiffNote` (Router.swift) tells us whether `ev.notes[0]` is
    /// genuinely the riff's own resolved pitch for this hit — if so, it's the primary (riff on); otherwise
    /// (riff off, or a FILL/degraded hit with no distinct riff pitch) the LOWEST sounding note is primary,
    /// matching "riff off: the lowest sounding note" read literally even when riff happens to be on but
    /// produced nothing of its own this hit. `plusN` is nil when there's nothing else sounding.
    private func noteViewPrimaryPlusN(_ ev: Router.EuclideousNoteViewEventSnapshot, flatKey: Bool) -> (primary: String?, plusN: String?) {
        guard !ev.notes.isEmpty else { return (nil, nil) }
        let primaryPitch = ev.hasRiffNote ? ev.notes[0] : (ev.notes.min() ?? ev.notes[0])
        let primary = euclideousNoteViewName(primaryPitch, flatKey: flatKey)
        let n = ev.notes.count - 1
        return (primary, n > 0 ? "+\(n)" : nil)
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
