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

/// One lane's 3 gesture PADS (Paul 2026-10-06: square buttons, each its own independent x/y drag
/// surface — superseding the original toggle-then-drag-the-comet-bar design). HITS/OFFSET's mapping
/// exactly matches the comet bar's own original drag (X=rotate, Y=hits); the other two reinterpret
/// the SAME `(Int) -> Void` callback slots `EuclidGesturePad` already exposes — no changes needed to
/// that component itself, since its callback type was already a bare, meaning-free `(Int) -> Void`.
/// RESHUFFLED (Paul 2026-10-08): "a TILT control... this should be the horizontal axis on the first xy box,
/// with hits being the vertical. Next to that is another with offset on x and count on y, then another with
/// x as gate and y as velocity, then the final x/y as it is now." Widened 3→4; HITS and OFFSET (rotate), which
/// used to share ONE pad, now split across the first two pads each paired with a NEW axis (TILT, step COUNT);
/// GATE/VELOCITY swap which axis drives which (gate now X, velocity now Y — was the reverse); NOTE/OCT is
/// unchanged, per Paul's own "the final x/y as it is now." Labels name X first, matching Paul's own dictation
/// order for all three changed pads.
// `label` (the old combined "TILT/HITS" etc. heading string) REMOVED 2026-10-09, XY pad redesign — the
// new pad layout has no heading at all; each axis now names itself on its own edge (`euclideousAxisNames`).
enum EuclideousGestureTab: Int, CaseIterable { case tiltHits = 0, offsetCount = 1, gateVelocity = 2, noteOctave = 3 }

/// A gesture pad's two drag axes (Paul 2026-10-09 ferry: "XY pad redesign" — one axis LOCKS per drag,
/// decided once 8pt of travel picks whichever moved further; held until finger-lift).
enum EuclideousXYAxis { case x, y }

/// Publishes a VIEW's own on-screen frame up to an ancestor — there was previously no mechanism on this
/// page for a view to learn its own position (every existing overlay anchors off the raw UIKit TOUCH
/// point instead, via `EuclidDragHUDInfo.point`). The new per-pad value bubble needs the opposite: it
/// must stay anchored to the PAD'S OWN frame even once a drag has carried the finger well outside it
/// (the new gesture model explicitly keeps tracking past the pad's bounds) — so each of the 16 pads
/// reports its frame once per layout pass, merged by key ("laneIdx-tabRawValue") into one dictionary.
struct EuclideousPadFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// A direct sibling of `EuclideousPadFramePreferenceKey` above, for the melody pop-up (Paul 2026-10-10
/// ferry §1.2: "anchored to the strip with a small pointer") — the SAME need, a popover that must stay
/// anchored to the control that opened it rather than floating at a fixed page position, just keyed by
/// plain lane index (0...3) since there's only one strip per lane, not a (lane, tab) pair.
struct EuclideousStripFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The two un-abbreviated value strings a pad shows (ferry §3/§4: "2 centered text lines for Y/X
/// values"... "explicit, non-abbreviated value-format strings") — Y above X, matching every pad's own
/// Y-axis-first dictation order. Reused for both the pad's own permanent face and the floating bubble
/// (whichever axis is actively locked), so the two can never show conflicting text for the same value.
struct EuclideousPadValues { let yText: String; let xText: String }

/// The new XY pad gesture bridge (Paul 2026-10-09 ferry), replacing `EuclidGesturePad` at this ONE call
/// site (`gesturePadRow`) — the shared component itself (EuclidLaneUI.swift, still used by the regular
/// BUILD-page EUCLID editor, Euclideous's own neutered per-lane comet bar, and the MASK pad) is
/// untouched; this is a SEPARATE, purpose-built bridge, not a variant bolted onto the old one, since the
/// interaction shapes genuinely differ (a dead zone + single-axis lock has no equivalent in the old
/// both-axes-always-live model).
///
/// SINGLE-FINGER: `.began` latches whether this is a 1- or 2-finger gesture (never re-read mid-drag,
/// mirroring `EuclidGesturePad`'s own established reasoning for why this must be latched, not polled).
/// Below an 8pt dead zone, nothing is reported (`onAxisDrag(nil, 0, 0)`) beyond the plain touch-down/up
/// signal (`onDragState`, still used for the "a finger is down" 2pt border highlight). At/past 8pt, the
/// axis that moved FURTHEST locks for the rest of the gesture — a plain UIKit `UIPanGestureRecognizer`
/// already keeps tracking a touch that leaves the view's own bounds (it tracks by touch, not by frame),
/// so "held until finger-lift even if it leaves the pad" needs no extra code.
///
/// TWO TRAVEL VALUES are reported once locked, because the ONE axis that needs the raw, un-rebased
/// value (TILT, whose own "-8" detent term IS this same 8pt dead zone, so feeding it the raw value
/// combines the two into exactly one threshold, not a doubled one) differs from the other seven fields
/// (which want travel REBASED to 0 at the exact instant of lock, so their own committed value starts
/// cleanly at its baseline with no visible pop the moment the axis decides).
///
/// 2-FINGER ALL LANES: reimplemented from scratch (Paul's own §2 interaction rules never mention
/// 2-finger dragging at all — "anything not mentioned stays as built") but behaviourally the SAME
/// continuous, no-dead-zone, no-axis-lock shape the old HITS/OFFS pad's own 2-finger gesture already
/// had — both axes report independently and continuously, discretized into whole units via the SAME
/// per-axis `pointsPerUnit` the single-finger path uses (a deliberate unification — the two gestures
/// controlling the SAME field at two different granularities would have been a stranger inconsistency
/// than sharing one sensitivity constant).
struct EuclideousXYPad: UIViewRepresentable {
    let xPointsPerUnit: CGFloat
    let yPointsPerUnit: CGFloat
    /// (lockedAxis, rawTravel, travelSinceLock) — nil axis + zero travel during the dead zone, at
    /// touch-down, or once the touch lifts. Y is pre-negated (screen-down is +y; "up" reads as
    /// positive travel, matching every Y-axis field's own "more = up" convention, same as the
    /// established `EuclidGesturePad` vertical-axis convention).
    let onAxisDrag: (EuclideousXYAxis?, CGFloat, CGFloat) -> Void
    let onAllDelta: (EuclideousXYAxis, Int) -> Void
    /// (location, isAllRows) — window-space; mirrors `EuclidGesturePad.onDragState` exactly, driving
    /// the 2pt "I'm touched" border.
    let onDragState: (CGPoint?, Bool) -> Void
    let onDoubleTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.backgroundColor = .clear; v.isOpaque = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        tap.numberOfTapsRequired = 2
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.owner = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: EuclideousXYPad
        init(_ o: EuclideousXYPad) { owner = o }
        private var twoFinger = false
        private var locked: EuclideousXYAxis? = nil
        private var lockRawTravel: CGFloat = 0   // the raw travel value AT the instant of lock, for rebasing
        private var appliedAllX = 0, appliedAllY = 0
        private let deadZone: CGFloat = 8
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) { owner.onDoubleTap() }
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                twoFinger = g.numberOfTouches >= 2
                locked = nil; lockRawTravel = 0
                appliedAllX = 0; appliedAllY = 0
                owner.onDragState(g.location(in: g.view?.window), twoFinger)
            case .changed:
                let t = g.translation(in: g.view)
                if twoFinger {
                    let stepsX = Int((t.x / owner.xPointsPerUnit).rounded())
                    let stepsY = Int((-t.y / owner.yPointsPerUnit).rounded())
                    if stepsX != appliedAllX { owner.onAllDelta(.x, stepsX - appliedAllX); appliedAllX = stepsX }
                    if stepsY != appliedAllY { owner.onAllDelta(.y, stepsY - appliedAllY); appliedAllY = stepsY }
                    owner.onDragState(g.location(in: g.view?.window), true)
                } else {
                    if locked == nil, max(abs(t.x), abs(t.y)) >= deadZone {
                        locked = abs(t.x) >= abs(t.y) ? .x : .y
                        lockRawTravel = locked == .x ? t.x : -t.y
                    }
                    if let axis = locked {
                        let raw = axis == .x ? t.x : -t.y
                        owner.onAxisDrag(axis, raw, raw - lockRawTravel)
                    }
                    owner.onDragState(g.location(in: g.view?.window), false)
                }
            case .ended, .cancelled, .failed:
                owner.onAxisDrag(nil, 0, 0)
                owner.onDragState(nil, twoFinger)
            default: break
            }
        }
    }
}

/// PER-LANE TABS (Paul 2026-10-07): PATTERN/RIFF/MASK, switching independently per lane — replaces
/// the old always-visible stacked DIRECTION/HIT-MISS-RATE/RIFF-direction rows with one tabbed slot.
/// I/O (Paul 2026-10-08) joins as the FIRST tab — per-lane MIDI IN/KEY/CHORDS source + the lane's own OUT
/// toggles (moved here from their old always-visible placement below every tab, see `laneCard`). This enum's
/// `laneTab` state is purely ephemeral (never persisted), so reordering its raw values here has no migration
/// concern — a fresh page open still starts every lane on PATTERN (unchanged default), I/O just sits first.
// RIFF TAB RETIRED (Paul 2026-10-10 ferry §1.2) — its own direction/FREE-LOCK/INVERT/ON-REST controls moved
// to the melody pop-up's WALK section. `laneTab` is purely ephemeral (never persisted, never defaults to a
// removed case — confirmed by its own declaration), so there's no "stuck on a now-gone tab" migration needed.
enum EuclideousLaneTab: Int, CaseIterable {
    case io = 0, pattern = 1, mask = 2
    var label: String { switch self { case .io: "I/O"; case .pattern: "PATTERN"; case .mask: "MASK" } }
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
    // PAGE REWORK (Paul 2026-10-07): the new global reset-span/key/source-mode/main-out config (§2.2-§2.4).
    let resetSpanBars: Int
    let keyRoot: Int
    let keyType: ScaleType
    // PER-LANE I/O (Paul 2026-10-08): the old GLOBAL riffSourceMidi/lanesSourceMidi switches + their setters
    // are REMOVED from this view entirely — each lane now owns its own MIDI IN/KEY/CHORDS choice directly on
    // EuclidLine (sourceMode), edited via the SAME generic `onEdit` every other per-lane field already uses
    // (see `ioSourceRow`) — no separate onSet* closure needed for this feature at all. The riff's own shared
    // PATTERN (steps/ranks) still has no page-level control of its own, but each lane's resolution of it now
    // reads that SAME lane's own I/O choice (Paul 2026-10-09, ferry §2.4 — supersedes an earlier "follows
    // lane 1" design entirely); see `riffGridView`'s own header note.
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
    let onClose: () -> Void

    @State private var selectedLane = 0
    @State private var singleTouchedLanes: Set<Int> = []
    @State private var allRowsTouched = false
    @State private var dragHUDInfo: EuclidDragHUDInfo? = nil
    // ALTERNATIVE GESTURE CONTROL (Paul 2026-10-06): "change the toggle buttons to be square... each will act
    // as an x/y pad in itself" — REPLACES the old toggle-then-drag-the-comet-bar model (which needed a
    // persisted "which tab is selected" flag) with 3 independent, always-live gesture pads per lane; nothing
    // is "selected" anymore, so there's nothing to persist. `touchedPad[lane]` is purely ephemeral — which of
    // the 3 pads (if any) currently has a finger down, for visual highlight only, matching the SAME
    // "local @State, never persisted" convention as `selectedLane`/`singleTouchedLanes` above.
    @State private var touchedPad: [Int?] = [nil, nil, nil, nil]
    // XY PAD REDESIGN (Paul 2026-10-09 ferry): per-LANE drag state for the new dead-zone + axis-lock
    // gesture model — `xyLockedAxis[idx]` is nil until 8pt of movement decides which axis this lane's
    // CURRENT touch controls (see `EuclideousXYPad`); `xyBaseline[idx]` is the (x,y) value captured
    // ONCE at touch-down (`padBaseline`), read back by `commitAxis` as the reference point every
    // absolute value is computed from. Both purely ephemeral/local, same convention as `touchedPad`.
    @State private var xyLockedAxis: [Int: EuclideousXYAxis] = [:]
    @State private var xyBaseline: [Int: (x: Double, y: Double)] = [:]
    // Per-pad on-screen frame, published by each of the 16 pads via `EuclideousPadFramePreferenceKey`
    // (a GeometryReader+PreferenceKey — there was previously no mechanism on this page for a view to
    // learn its OWN frame) — read by the new floating value bubble to anchor itself just above/below
    // whichever pad is currently being dragged, keyed "idx-tabRawValue".
    @State private var padFrames: [String: CGRect] = [:]
    // MELODY POP-UP (Paul 2026-10-10 ferry): which lane's pop-up is open (nil = none — the `Int?`
    // precedent already established by `ratePopupLane`), and each strip's own
    // on-screen frame (published via `EuclideousStripFramePreferenceKey`, the direct sibling of
    // `padFrames` above), so the pop-up can anchor itself to the tapped strip rather than floating at a
    // fixed page position.
    @State private var melodyPopupLane: Int? = nil
    @State private var melodyStripFrames: [Int: CGRect] = [:]
    // HIT|MISS is now the persisted `EuclidLine.patternMiss` field itself (Paul 2026-10-10 ferry) — no local
    // @State needed; `hitMissRateRow` reads/writes it directly via `edit(idx)`.
    // RATE POPUP (Paul 2026-10-06): "I hate the current [tap-to-cycle] control and want a pop-up" — replaces
    // cycling through all 18 ArpRate cases one tap at a time (and never offering a way back to nil/"inherit
    // the machine rate") with a single list the user picks from directly. nil = no popup open.
    @State private var ratePopupLane: Int? = nil
    // PER-LANE TABS: which of I/O/PATTERN/MASK each lane currently shows (RIFF retired 2026-10-10, folded into
    // the melody pop-up) — purely local/ephemeral, same convention as touchedPad above (not persisted; a fresh
    // page open always starts every lane on PATTERN).
    @State private var laneTab: [EuclideousLaneTab] = [.pattern, .pattern, .pattern, .pattern]
    @State private var resetSpanPopupOpen = false
    @State private var keyPopupOpen = false
    @State private var chordsPopupOpen = false
    // riffDirPopupLane RETIRED 2026-10-10 alongside the RIFF tab — direction selection lives inline in the
    // melody pop-up's WALK section now, no separate nested popup needed.

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

    // --- PROTECTED ABSOLUTE SIZES (ferry §3, 2026-10-08 — component dimensions, not spacing, so the 4/8/16
    // scale doesn't apply to them): MAIN OUT and lane OUT circles never shrink below these. ---
    private let laneOutSize: CGFloat = 30
    private let mainOutSize: CGFloat = 36

    // --- TYPE SCALE (this ferry §5.5/§6, superseding the layout-system ferry's own original derivation —
    // its "~43pt usable pad width" estimate was computed against the now-superseded six-equal-boxes layout
    // and no longer applies under §1's full-width fix). Two explicit rules now PIN two of these three
    // sizes directly, rather than deriving every size from a hand-measured worst-case fit:
    //   - §5.5: axis labels (`padHeadingSize`) are "at least 10pt" — a literal floor, not a fit-derived
    //     number — paired with an explicit FALLBACK (`euclideousAxisLabelFits`, below) for any name that
    //     genuinely doesn't fit a given pad at that size: show the bare arrow glyph(s) instead of the full
    //     "← NAME →" string, rather than shrinking under the floor.
    //   - §6.2: "pad readout line 1... must be larger than the tab labels. Set the tab labels to the pad
    //     readout line-2 size" — so `padSubtitleSize` (line 2) IS the tab-label size (read by
    //     `laneTabRow`, not just this pad), and `padValueSize` (line 1) must exceed it. Both ≥10pt, per
    //     §6.1's own general floor.
    // NOTHING using these three sizes gets `.minimumScaleFactor` — a render below the chosen size is
    // exactly what §6.1 forbids.
    private let padHeadingSize: CGFloat = 10
    private let padValueSize: CGFloat = 13
    private let padSubtitleSize: CGFloat = 11
    /// §5.5's fit check: "if a name doesn't fit at 10pt, show the arrows only." No live text-measurement
    /// API is reached for here (same reasoning as the bubble's own fixed-width estimate elsewhere in this
    /// file) — a character-count heuristic, hand-derived against the narrowest axis-label space this new
    /// layout can produce (the bottom edge, bounded by the pad's own width): OFFSET/STEPS/SHIFT (5–6
    /// chars) are the names most likely to overflow; HITS/TILT/VEL/GATE/OCT/NOTE (3–4 chars) comfortably
    /// fit alongside their own flanking arrows. Flagged, not measured — the one thing this environment
    /// cannot verify against real on-device text metrics.
    private func euclideousAxisLabelFits(_ name: String) -> Bool { name.count <= 4 }

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
                // THE RATE POP-UP (Paul 2026-10-06) — a scrim + centred card, the standard "tap outside to
                // dismiss" popup shape already used elsewhere in this app (e.g. the scale-pool/chord popups).
                if let lane = ratePopupLane {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { ratePopupLane = nil }
                        .zIndex(3)
                    ratePopupCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                // RIFF DIRECTION POPUP RETIRED (ferry 2026-10-10 §1.2) — direction selection now lives inline
                // in the melody pop-up's own WALK section below; `riffDirGrid`/`riffDirPopupCard` are deleted.
                // THE MELODY POP-UP (Paul 2026-10-10 ferry §1.2/§1.3) — anchored to the tapped strip with a
                // pointer, NOT the centered scrim+card every popup above uses. Dismissal still needs a
                // full-screen tap-catcher, but it's `Color.clear` (no darkening) — a modal-style dim
                // doesn't fit "anchored... with a pointer" popover language, and nothing else floating on
                // this page (the XY-pad drag bubble) dims the background either; a reasoned, disclosed
                // choice, not a literal instruction.
                if let lane = melodyPopupLane {
                    Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                        .onTapGesture { melodyPopupLane = nil }
                        .zIndex(3)
                    if let frame = melodyStripFrames[lane] {
                        let anchor = euclideousMelodyAnchor(frame, in: geo.size)
                        // `.position()` centers a view — but the card's own near edge (bottom, if it grew
                        // above; top, if below) must touch the strip, and its natural height isn't known
                        // ahead of render. Fixing the OUTER frame's height to the full `availableH` budget
                        // (alignment pinning the actual, possibly-shorter card content to that same near
                        // edge) makes the CENTER-based math solvable: center = near-edge ∓ availableH/2.
                        melodyPopupCard(lane, availableHeight: anchor.availableH, grewAbove: anchor.grewAbove)
                            .frame(height: anchor.availableH, alignment: anchor.grewAbove ? .bottom : .top)
                            .position(x: anchor.centerX, y: anchor.grewAbove
                                      ? frame.minY - 12 - anchor.availableH / 2
                                      : frame.maxY + 12 + anchor.availableH / 2)
                            .zIndex(4)
                    }
                }
                // RESET SPAN + KEY POPUPS (Paul 2026-10-07) — the SAME scrim+card shape, reused rather than
                // reinvented, for the two new global pickers.
                if resetSpanPopupOpen {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { resetSpanPopupOpen = false }
                        .zIndex(3)
                    resetSpanPopupCard.position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
                }
                if keyPopupOpen {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { keyPopupOpen = false }
                        .zIndex(3)
                    keyPopupCard.position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
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
                // THE XY PAD VALUE BUBBLE (Paul 2026-10-09 ferry §3): one per lane currently mid-drag on one
                // of its 4 gesture pads (axis already locked, past the dead zone) — multiple can show at once,
                // matching this page's existing multi-touch support (`singleTouchedLanes`). Anchored to the
                // TOUCHED PAD'S OWN on-screen frame (`padFrames`, published below), not the finger position —
                // a drag that leaves the pad's bounds (explicitly allowed by the new gesture model) must not
                // drag the bubble away from the control it's reporting on.
                ForEach(activeXYBubbles, id: \.idx) { b in
                    let line = b.idx < lines.count ? lines[b.idx] : EuclidLine(noteSel: .all)
                    let values = euclideousPadValues(line, b.tab)
                    let text = b.axis == .x ? values.xText : values.yText
                    let accent = laneAccents[b.idx % laneAccents.count]
                    if let frame = padFrames["\(b.idx)-\(b.tab.rawValue)"] {
                        let pos = euclideousBubblePosition(frame, in: geo.size)
                        euclideousXYBubble(text, accent: accent)
                            .position(pos)
                            .allowsHitTesting(false)
                            .zIndex(5)
                    }
                }
            }
            .coordinateSpace(name: "euclideousXY")
            .onPreferenceChange(EuclideousPadFramePreferenceKey.self) { padFrames = $0 }
            .onPreferenceChange(EuclideousStripFramePreferenceKey.self) { melodyStripFrames = $0 }
        }
    }
    /// Every (lane, locked-axis) pair currently mid-drag, past the dead zone — drives the bubble above.
    private var activeXYBubbles: [(idx: Int, tab: EuclideousGestureTab, axis: EuclideousXYAxis)] {
        (0..<4).compactMap { idx in
            guard let tabRaw = touchedPad[idx], let axis = xyLockedAxis[idx],
                  let tab = EuclideousGestureTab(rawValue: tabRaw) else { return nil }
            return (idx, tab, axis)
        }
    }
    /// Positions the bubble above the pad's own frame, flipping below only when there's no room above
    /// (ferry §2.8: "If there is no room above, show it below. It must stay inside the page.") — BOTH
    /// axes are clamped to the real page bounds, not just the vertical flip: a pad near the left/right
    /// edge could otherwise push a wider bubble string partway off-screen. `bubbleHalfW` is a fixed,
    /// generous estimate (no convenient live-text-measurement API here) covering the longest realistic
    /// bubble string (e.g. "OFFSET +15"), the same fixed-width-estimate idiom this page's existing
    /// `dragHUDInfo` HUD already uses for the same reason.
    private func euclideousBubblePosition(_ frame: CGRect, in pageSize: CGSize) -> CGPoint {
        let bubbleHalfW: CGFloat = 55
        let margin: CGFloat = 20
        let aboveY = frame.minY - margin
        let y = aboveY >= margin ? aboveY : min(frame.maxY + margin, pageSize.height - margin)
        let x = min(max(frame.midX, bubbleHalfW), max(bubbleHalfW, pageSize.width - bubbleHalfW))
        return CGPoint(x: x, y: y)
    }
    private func euclideousXYBubble(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: padValueSize, weight: .heavy, design: .monospaced))
            .foregroundColor(.black).lineLimit(1)
            .padding(.horizontal, sp8).padding(.vertical, sp4)
            .background(RoundedRectangle(cornerRadius: 6).fill(accent))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
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
    private let cometRowH: CGFloat = 56
    private let tabRowH: CGFloat = 30
    private let contentLineH: CGFloat = 36
    /// A tab's 2-row content is `36 + sp4 + 36` (each tab's own inner VStack uses `spacing: sp4` between its
    /// 2 rows, confirmed by reading all four: `ioSourceRow`+`laneOutRow`, `directionRow`+`hitMissRateRow`,
    /// `riffDirGrid`'s own 2 rows (OFF/direction-chip/FREE-LOCK, then INVERT/ON-REST — ferry 2026-10-09),
    /// `maskCometRow`+`maskStubRow`) — not a bare `36×2`.
    private var tabContentH: CGFloat { contentLineH * 2 + sp4 }
    /// A lane card's own fixed overhead — every row EXCEPT the gesture-pad row, which stretches to fill
    /// whatever's left (see `laneCard`). Used only to protect a lane-grid floor in `portraitLayout` below.
    private var laneCardFixedOverhead: CGFloat { cometRowH + tabRowH + tabContentH + sp8 * 2 + sp4 * 3 }

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
            portraitHeader().padding(.horizontal, sp16).padding(.top, sp16)
            VStack(spacing: sp16) {
                VStack(spacing: sp8) {
                    HStack(spacing: sp8) { laneCard(0, width: laneW, height: laneH); laneCard(1, width: laneW, height: laneH) }
                    HStack(spacing: sp8) { laneCard(2, width: laneW, height: laneH); laneCard(3, width: laneW, height: laneH) }
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
                VStack(spacing: sp8) {
                    HStack(spacing: sp8) { laneCard(0, width: laneW, height: laneH); laneCard(1, width: laneW, height: laneH) }
                    HStack(spacing: sp8) { laneCard(2, width: laneW, height: laneH); laneCard(3, width: laneW, height: laneH) }
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
            Spacer(minLength: sp4)
            headerResetChip()
            headerKeyGroup()
            headerChordsChip()
            headerMainOutGroup()
            headerOnChip()
            headerCloseButton()
        }
        .frame(height: headerRowH)
    }

    /// PORTRAIT row 1 (this ferry §3.2, literal): EUCLIDEOUS · MAIN OUT A B C D · ON · close — RESET moved
    /// OUT to row 2 (it was here in the prior ferry; this one explicitly re-homes it).
    private func headerRow1() -> some View {
        HStack(spacing: sp4) {
            headerTitle()
            Spacer(minLength: sp4)
            headerMainOutGroup()
            headerOnChip()
            headerCloseButton()
        }
    }
    /// PORTRAIT row 2 (this ferry §3.2, literal): RESET · KEY −/chip/+ · CHORDS.
    private func headerRow2() -> some View {
        HStack(spacing: sp4) {
            headerResetChip()
            headerKeyGroup()
            Spacer(minLength: sp4)
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
        }
    }
    private func headerKeyGroup() -> some View {
        HStack(spacing: sp4) {
            Text("KEY").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            keyStepButton("−")
            Text("\(noteNames[((keyRoot % 12) + 12) % 12]) \(keyType.label)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .lineLimit(1)
                .padding(.horizontal, sp4).frame(height: headerBtnH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.9)))
                .contentShape(Rectangle())
                .onTapGesture { keyPopupOpen = true }
            keyStepButton("+")
        }
    }
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

    private func keyStepButton(_ label: String) -> some View {
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            .frame(width: headerBtnH, height: headerBtnH)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture { label == "−" ? onSetKeyRoot(((keyRoot - 1) % 12 + 12) % 12) : onSetKeyRoot((keyRoot + 1) % 12) }
    }

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


    @ViewBuilder private func laneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        let tab = idx < laneTab.count ? laneTab[idx] : .pattern
        // ONE INNER WIDTH FOR EVERY ROW (ferry §3: "every row inside a lane card spans the same inner width
        // ... no row may run to the card edge, and none may be narrower than the others" — this is the direct
        // fix for "the pads sit flush against the card edge" and "some rows run to the card edge and others
        // are inset, compare MASK in lane 2 with PATTERN in lane 4": every row below is built from THIS one
        // width, never the raw card `width`.
        let innerWidth = max(1, width - sp8 * 2)
        let padSize = max(1, (innerWidth - sp4 * 2) / 3)   // DIRECTION/HIT-MISS-RATE: 3 equal columns, sp4 gaps
        // GESTURE PADS — down to 3 (ferry 2026-10-10 §1.1: SHIFT/OCT dropped, now in the melody pop-up). The
        // 3 survivors share the freed width equally, same formula as padSize above.
        let gesturePadW = max(1, (innerWidth - sp4 * 2) / 3)
        // NO EMPTY BANDS (ferry §1.3): the gesture-pad row's HEIGHT is computed explicitly as "exactly what's
        // left" after every other fixed-height row + the card's own sp8 padding (top+bottom) + the sp4 gaps
        // between this VStack's 4 children — the pads STRETCH to fill it, never centred-with-slack.
        let outerVPad: CGFloat = sp8 * 2
        let rowGaps: CGFloat = sp4 * 3     // VStack(spacing: sp4) between the 4 children = 3 gaps
        let gestureRowH = max(1, height - cometRowH - tabRowH - tabContentH - outerVPad - rowGaps)
        let steps = max(2, min(16, line.steps))
        VStack(alignment: .leading, spacing: sp4) {
            EuclidLaneBox(idx: idx, line: line, width: innerWidth, height: cometRowH, accent: accent,
                          // WHOLE-CARD OUTLINE (ferry §1.4): `selected` here used to draw EuclidLaneBox's own
                          // border/fill around just this row (the step-bar area) — always `false` now; the
                          // selection indicator moved to a single outline around the ENTIRE card below.
                          selected: false, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: line.rate ?? .r1_16, spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          onRotateDelta: { _ in }, onHitsDelta: { _ in },      // NEUTERED — the 4 square pads below own this now
                          onStepsDelta: { d in edit(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },   // PINCH — the one thing explicitly kept on the comet bar itself
                          onAllRotateDelta: { _ in }, onAllHitsDelta: { _ in },   // NEUTERED, same reason
                          onDragState: { _, _ in },                              // no HUD/highlight from the comet bar anymore — the pads report their own
                          onSelect: { selectedLane = idx },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          stepCountBadge: AnyView(stepCountBadge(steps, mask: line.emitterMask ?? 0, accent: accent)),
                          stepCountBadgeWidth: stepCountBadgeTotalWidth)
            gesturePadRow(idx, line, accent, cellSize: gesturePadW, rowHeight: gestureRowH)
            laneTabRow(idx, line, accent, rowH: tabRowH)
            tabContent(idx, line, tab, accent, cellSize: padSize, rowH: contentLineH, fullWidth: innerWidth)
        }
        .padding(sp8)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
        // WHOLE-CARD SELECTION OUTLINE (ferry §1.4): replaces the narrower step-bar-only outline above.
        // LANE-100 (this ferry §4.1): the selected card's own outline is the full-strength lane colour,
        // not a softened opacity.
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedLane == idx ? lane100(accent) : Color.clear, lineWidth: 2))
        .clipped()
    }

    /// PASSIVE STEP-COUNT NUMERAL (Paul 2026-10-07, §3: "step count shown as a number") + an ALWAYS-VISIBLE
    /// OUTPUT INDICATOR (Paul 2026-10-09, ferry §3.1: "the OUT row only appears on the I/O tab... add a small
    /// always-visible output indicator... showing which outputs the lane is routed to, or NO OUTPUT when
    /// none"). Both share `EuclidLaneBox`'s one optional `stepCountBadge` slot (nil everywhere else, so the
    /// regular BUILD-page EUCLID editor is unaffected) — stacked rather than adding a second slot, since the
    /// comet row has no more spare width to give a wholly separate widget.
    // OUTPUT CHIPS + SOURCE BADGE (this ferry §8, literal). The chip grid's own footprint (2 columns wide,
    // however many rows 0-4 routed outputs need) — `EuclidLaneBox` needs this number explicitly (see
    // `stepCountBadgeWidth` there) so the comet bar beside it is never told it has more room than it
    // actually gets.
    private let stepCountChipCol: CGFloat = 16, stepCountChipGap: CGFloat = 2
    // 2 chip columns + the gap between them + the sp4 gap before the source badge + the source badge's own
    // The per-lane source badge ("MIDI"/"KEY"/"CHD") RETIRED 2026-10-10 (ferry §1.4) — NOTE VIEW's own label
    // already shows the source, so this is now just the step-count + output-chip block on its own.
    private var stepCountBadgeTotalWidth: CGFloat { stepCountChipCol * 2 + stepCountChipGap + sp4 * 2 }
    /// §8.1, literal: "replace the bare letter under the step count with mini output chips, 16pt circles
    /// with a 10pt letter, LANE-40 fill, one chip per routed output. If none are routed, show 'NO OUT' in
    /// amber."
    private func stepCountBadge(_ n: Int, mask: UInt8, accent: Color) -> some View {
        let routed = (0..<4).filter { (mask >> UInt8($0)) & 1 != 0 }
        let rows = stride(from: 0, to: routed.count, by: 2).map { Array(routed[$0..<min($0 + 2, routed.count)]) }
        return VStack(spacing: 1) {
            Text("\(n)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            if mask == 0 {
                Text("NO OUT").font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: 0xFFB454)).lineLimit(1)
            } else {
                VStack(spacing: 1) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: stepCountChipGap) {
                            ForEach(rows[r], id: \.self) { b in
                                Text(["A", "B", "C", "D"][b]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: stepCountChipCol, height: stepCountChipCol)
                                    .background(Circle().fill(lane40(accent)))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, sp4)
        .frame(width: stepCountBadgeTotalWidth, height: 44)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
    }

    // MARK: - The 4 gesture pads (Paul 2026-10-09 ferry: "XY pad redesign" — dead-zone + axis-lock drag,
    // no heading, 2 centered value lines + a live Canvas "picture" + edge axis-name labels, a per-pad
    // floating value bubble replacing the old shared page-level HUD, double-tap-to-reset.)

    private let padAxisLabelColor = Color(hex: 0x8A909A)

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

    /// The 4 gesture PADS (RHYTHM · LENGTH · NOTE/GATE · RIFF, by their own axis pairing — labels now
    /// live on the pad's edges, not a heading) — `cellSize` wide, `rowHeight` tall, `sp4` gaps between
    /// them (unchanged). Each is its own independent `EuclideousXYPad` drag surface; PINCH stays on the
    /// comet bar, untouched by this redesign.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowHeight: CGFloat) -> some View {
        // DOWN TO 3 PADS (ferry 2026-10-10 §1.1): the 4th pad (SHIFT/OCT with riff on, NOTE/OCT with riff
        // off) moved to the melody pop-up entirely. Iterating a literal subset instead of `.allCases` is a
        // deliberate minimal-diff choice — the enum keeps its `.noteOctave` case and the 8 switches keyed off
        // it (`euclideousPadValues`/`euclideousAxisNames`/`pointsPerUnit`/`euclideousPadPicture`/`padBaseline`/
        // `commitAxis`/`doubleTapReset`/`applyAllDelta`) keep their now-unreachable `.noteOctave` arms as
        // harmless dead code, rather than forcing an edit to all 8 for this one real call site that matters.
        HStack(spacing: sp4) {
            ForEach([EuclideousGestureTab.tiltHits, .offsetCount, .gateVelocity], id: \.rawValue) { t in
                let touched = touchedPad[idx] == t.rawValue
                // RIFF ADVANCE (Paul 2026-10-06): once a lane's useRiff is on, this pad's tint + picture +
                // axis labels switch from NOTE/OCT to SHIFT/OCT — unchanged by this redesign, just now
                // expressed via `euclideousAxisNames`/`euclideousPadValues`/`euclideousPadPicture` instead
                // of a swapped heading string.
                let isRiffPad = t == .noteOctave && line.useRiffResolved
                let values = euclideousPadValues(line, t)
                let names = euclideousAxisNames(line, t)
                let ppu = pointsPerUnit(t)
                ZStack {
                    // LANE-20 (this ferry §4.4): "the riff pad's background tint becomes LANE-20, not the
                    // current stronger tint" (was 0.22).
                    RoundedRectangle(cornerRadius: 6).fill(isRiffPad ? lane20(accent) : Color(hex: 0x22252C))
                    VStack(spacing: sp4) {
                        VStack(spacing: 1) {
                            Text(values.yText)
                                .font(.system(size: padValueSize, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.92)).lineLimit(1)
                            Text(values.xText)
                                .font(.system(size: padSubtitleSize, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6)).lineLimit(1)
                        }
                        euclideousPadPicture(line, t, accent: accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.top, sp4).padding(.bottom, 9).padding(.horizontal, 9)
                }
                // BOTTOM EDGE (ferry §3.4/§5.5, literal): "← TILT →" at ≥10pt — plain arrow glyphs
                // (U+2190/U+2192). If the name doesn't fit at 10pt (§5.5), fall back to "◀ ▶" alone (the
                // readout at the top already names the value, per the ferry's own justification).
                .overlay(alignment: .bottom) {
                    Text(euclideousAxisLabelFits(names.x) ? "← \(names.x) →" : "◀ ▶")
                        .font(.system(size: padHeadingSize, weight: .heavy, design: .monospaced))
                        .foregroundColor(padAxisLabelColor).lineLimit(1)
                        .padding(.bottom, 1)
                }
                // LEFT EDGE (ferry §3.5/§5.5, literal): "HITS →" — ONE string, the arrow trailing the
                // name — rotated as a single unit so the arrow (originally pointing right/east) ends up
                // pointing up/north once rotated. If the name doesn't fit at 10pt (§5.5), fall back to a
                // bare "▲" — already pointing up in its own resting orientation, so it needs no rotation.
                .overlay(alignment: .leading) {
                    Group {
                        if euclideousAxisLabelFits(names.y) {
                            Text("\(names.y) →")
                                .font(.system(size: padHeadingSize, weight: .heavy, design: .monospaced))
                                .lineLimit(1).fixedSize()
                                .rotationEffect(.degrees(-90))
                        } else {
                            Text("▲").font(.system(size: padHeadingSize, weight: .heavy))
                        }
                    }
                    .foregroundColor(padAxisLabelColor)
                    .frame(width: 10)
                    .padding(.leading, 1)
                }
                // THE 2pt TOUCH BORDER (ferry §3) — the new, single "I'm being dragged" cue; the old
                // whole-pad accent-fill-while-touched treatment is gone, since it would otherwise fight
                // the riff-tint fill above for the same visual channel.
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(touched ? accent : Color.clear, lineWidth: 2))
                .frame(width: cellSize, height: rowHeight)
                .contentShape(Rectangle())
                // PAD FRAME PUBLISHING (ferry §3: the bubble anchors to the pad, not the finger) —
                // see `EuclideousPadFramePreferenceKey`'s own doc comment.
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: EuclideousPadFramePreferenceKey.self,
                                                value: ["\(idx)-\(t.rawValue)": g.frame(in: .named("euclideousXY"))])
                    }
                )
                .overlay(
                    EuclideousXYPad(
                        xPointsPerUnit: ppu.x, yPointsPerUnit: ppu.y,
                        onAxisDrag: { axis, raw, sinceLock in
                            guard let axis else { xyLockedAxis[idx] = nil; return }
                            xyLockedAxis[idx] = axis
                            let base = xyBaseline[idx] ?? padBaseline(line, t)
                            // TILT's X axis wants the RAW travel (its own detent formula IS the dead
                            // zone); every other axis wants travel rebased to 0 at the lock instant, so
                            // its committed value starts exactly at baseline with no pop — see
                            // `EuclideousXYPad`'s own doc comment.
                            let travel = (t == .tiltHits && axis == .x) ? raw : sinceLock
                            edit(idx) { commitAxis(&$0, t, axis: axis, baseline: axis == .x ? base.x : base.y, travel: travel) }
                        },
                        onAllDelta: { axis, d in euclideousApplyAllDelta(t, axis: axis, d) },
                        onDragState: { point, _ in
                            if point == nil {
                                if touchedPad[idx] == t.rawValue { touchedPad[idx] = nil }
                                xyLockedAxis[idx] = nil
                            } else if touchedPad[idx] != t.rawValue {
                                // A FRESH touch on this pad — capture the baseline exactly once, before
                                // any commit can run, so a nudge is always relative to where the value
                                // was when the finger first landed.
                                touchedPad[idx] = t.rawValue
                                xyLockedAxis[idx] = nil
                                xyBaseline[idx] = padBaseline(line, t)
                            }
                        },
                        onDoubleTap: { edit(idx) { doubleTapReset(&$0, t) } })
                )
            }
        }
    }

    // SHIFT's wrap is a LITERAL 8 (ferry §2.5 "SHIFT wraps within 0–7" / §5.4 "a grid with 8 columns") —
    // NOT `riff.stepsResolved` (which an untouched, never-edited riff pattern defaults to 16). In
    // practice the riff grid's own UI (`riffGridView`) hardcodes 8 columns and writes `steps: 8` on every
    // edit, so this is byte-identical to `riff.stepsResolved` for any session that has ever touched the
    // riff grid — this constant only matters, and only differs, for an untouched-default document.
    private let shiftSteps = 8
    /// Signed value text matching the ferry's own literal examples exactly: "+2" / "−1" (a true minus
    /// sign, U+2212, not the ASCII hyphen Swift's own string interpolation of a negative Int produces) /
    /// a bare "0" with NO sign at all. Used by TILT and OCT — the two fields whose §4 examples show a
    /// sign-free zero ("TILT 0", "OCT 0") alongside signed nonzero values.
    private func euclideousSigned(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "0") }
    /// The two un-abbreviated value strings a pad shows (ferry §4) — Y above X, reused by both the
    /// permanent face (above) and the floating drag bubble (the body's own `activeXYBubbles`), so the
    /// two can never disagree about what a value currently reads.
    private func euclideousPadValues(_ line: EuclidLine, _ t: EuclideousGestureTab) -> EuclideousPadValues {
        switch t {
        case .tiltHits:
            // TILT (ferry §4, literal): "TILT +20%", "TILT −30%", "TILT 0" — zero carries NEITHER a sign
            // NOR a "%" at all; only a nonzero value gets both.
            let pct = Int((line.tiltResolved * 100).rounded())
            let hitWord = line.pulses == 1 ? "HIT" : "HITS"
            let tiltText = pct == 0 ? "TILT 0" : "TILT \(euclideousSigned(pct))%"
            return EuclideousPadValues(yText: "\(line.pulses) \(hitWord)", xText: tiltText)
        case .offsetCount:
            // OFFSET (ferry §4, literal): "OFFSET +5" — ALWAYS carries a "+", even at 0 ("OFFSET +0");
            // it can never go negative (a wrapped 0...STEPS-1 value), so this isn't a sign, just the
            // field's own fixed display convention.
            let n = max(2, min(16, line.steps))
            let r = ((line.rotate % n) + n) % n
            return EuclideousPadValues(yText: "\(line.steps) STEPS", xText: "OFFSET +\(r)")
        case .gateVelocity:
            let gatePct = Int((line.gateResolved * 100).rounded())
            return EuclideousPadValues(yText: "VEL \(line.velocityAbsoluteResolved)", xText: "GATE \(gatePct)%")
        case .noteOctave:
            if line.useRiffResolved {
                // SHIFT (melody pop-up ferry 2026-10-10 §2/§3.3): wraps within LENGTH now, not the old
                // literal 8 — this pad and the new pop-up's own SHIFT stepper must agree on the same
                // domain, or the two controls could disagree the moment LENGTH ≠ 8.
                let n = line.riffLengthResolved
                let shift = ((line.riffRotateResolved % n) + n) % n
                let oct = line.riffOctaveResolved
                return EuclideousPadValues(yText: "OCT \(euclideousSigned(oct))", xText: "SHIFT \(shift)")
            }
            // NOTE choice (ferry §4, literal): "its existing name, e.g. 'ALL'" — the BARE name, no "NOTE"
            // prefix (the edge label already names the axis; §5.5 calls this "text only").
            let oct = line.octaveResolved
            return EuclideousPadValues(yText: "OCT \(euclideousSigned(oct))", xText: line.noteSelResolved.rawValue)
        }
    }
    /// The edge-label axis names (ferry §3) — short, un-abbreviated field names, Y then X.
    private func euclideousAxisNames(_ line: EuclidLine, _ t: EuclideousGestureTab) -> (y: String, x: String) {
        switch t {
        case .tiltHits: return ("HITS", "TILT")
        case .offsetCount: return ("STEPS", "OFFSET")
        case .gateVelocity: return ("VEL", "GATE")
        case .noteOctave: return ("OCT", line.useRiffResolved ? "SHIFT" : "NOTE")
        }
    }
    /// Per-(tab,axis) drag sensitivity — points of finger travel per ONE WHOLE UNIT of that field's own
    /// natural step (ferry §2.4) — shared by the single-finger locked-axis commit (`travel / ppu`
    /// against a captured baseline, see `commitAxis`) AND the 2-finger ALL-LANES path (the bridge itself
    /// quantizes continuous travel into discrete Int ticks at this same rate — a deliberate
    /// unification: the ferry never addresses 2-finger sensitivity, and two different sensitivities for
    /// the same field depending on finger count would have been a stranger inconsistency than sharing one).
    private func pointsPerUnit(_ t: EuclideousGestureTab) -> (x: CGFloat, y: CGFloat) {
        switch t {
        case .tiltHits: return (1, 12)        // TILT 1pt/1% · HITS 12pt/step
        case .offsetCount: return (12, 12)    // OFFSET 12pt/step · STEPS 12pt/step
        case .gateVelocity: return (2, 1.5)   // GATE 2pt/1% · VEL 1.5pt/unit
        case .noteOctave: return (12, 12)     // SHIFT/NOTE 12pt/step · OCT 12pt/step
        }
    }

    // MARK: - The 5 pictures (ferry §5) — bespoke live Canvas visualizations, one per pad (NOTE/OCT has
    // two: riff-on shows the RIFF picture, riff-off shows its own single-column OCT picture).

    @ViewBuilder private func euclideousPadPicture(_ line: EuclidLine, _ t: EuclideousGestureTab, accent: Color) -> some View {
        switch t {
        case .tiltHits: euclideousRhythmPicture(line, accent: accent)
        case .offsetCount: euclideousLengthPicture(line, accent: accent)
        case .gateVelocity: euclideousNoteGatePicture(line, accent: accent)
        case .noteOctave:
            if line.useRiffResolved { euclideousRiffPicture(line, accent: accent) }
            else { euclideousNoteOctPicture(line, accent: accent) }
        }
    }
    /// RHYTHM (this ferry §5.2, literal — replaces the old tall-vertical-bars layout): a single
    /// HORIZONTAL row of STEPS cells, vertically CENTRED, at ~30% of the picture's own height — still
    /// reusing the exact same pure functions, in the same order, `Router.runEuclidLine` itself calls
    /// (`euclidPatternInto` then `euclidTiltPattern`), so the picture can never silently disagree with
    /// what's struck, and the tilt-driven bunching of hits stays visible along the row regardless of its
    /// new shorter height. Hit cells LANE-40 (was LANE-100); rest cells unchanged (#3A3E47). No direction
    /// handling, matching `EuclidCometBar`'s own established precedent.
    private func euclideousRhythmPicture(_ line: EuclidLine, accent: Color) -> some View {
        let n = max(2, min(16, line.steps))
        let k = max(0, min(n, line.pulses))
        var buf = [Bool](repeating: false, count: n)
        euclidPatternInto(&buf, pulses: k, steps: n, rotation: line.rotate)
        if line.tiltResolved != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: line.tiltResolved) }
        // MISS STYLE (ferry §3.3, "the rhythm pad's picture follows the same rule"): the SAME single-point
        // invert the step bar and the engine both apply, so this picture can never disagree with either.
        let missStyle = line.patternMissResolved
        if missStyle { for i in 0..<n { buf[i].toggle() } }
        return Canvas { ctx, size in
            let gap: CGFloat = 1   // ferry §5.2: "with a 1pt minimum gap"
            let rowH = size.height * 0.3
            let y = (size.height - rowH) / 2   // vertically centred
            let cellW = max(1, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            for i in 0..<n {
                let rect = CGRect(x: CGFloat(i) * (cellW + gap), y: y, width: cellW, height: rowH)
                let box = Path(roundedRect: rect, cornerRadius: 1)
                if buf[i] {
                    ctx.fill(box, with: .color(lane40(accent)))
                } else if missStyle {
                    // the ORIGINAL (now-silent) Euclid hit — outline only, no fill. §3.3: "the rhythm pad's
                    // picture follows the SAME rule" as §3.2's step bar — 1.5pt literally, not a scaled-down
                    // approximation (caught on review: a first draft used 1pt here, an unflagged inconsistency).
                    ctx.stroke(box, with: .color(lane100(accent)), lineWidth: 1.5)
                } else {
                    ctx.fill(box, with: .color(Color(hex: 0x3A3E47)))
                }
            }
        }
    }
    /// LENGTH (this ferry §5.3, literal — "raise the contrast of the ring"): `steps` dots arranged
    /// clockwise around a circle (12 o'clock = step 0). Ordinary dots 4pt/#6A707A; step 1 (index 0) ALSO
    /// 4pt, just a lighter #C8CDD5 (same size as every other ordinary dot now — only the colour marks it,
    /// not a larger radius); the OFFSET step is 8pt/LANE-100 — the SAME wrap `euclideousPadValues`'s own
    /// OFFSET readout uses, so the picture and the value line can never disagree about which dot is
    /// current. Ring radius: 40% of the picture's smaller dimension, centred.
    private func euclideousLengthPicture(_ line: EuclidLine, accent: Color) -> some View {
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        return Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let radius = min(size.width, size.height) * 0.4
            for i in 0..<n {
                let angle = -Double.pi / 2 + 2 * .pi * Double(i) / Double(n)
                let x = cx + CGFloat(cos(angle)) * radius
                let y = cy + CGFloat(sin(angle)) * radius
                let on = i == r
                let dotR: CGFloat = on ? 4 : 2   // 8pt / 4pt DIAMETERS, per the ferry's own literal numbers
                let color: Color = on ? lane100(accent) : (i == 0 ? Color(hex: 0xC8CDD5) : Color(hex: 0x6A707A))
                ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(color))
            }
        }
    }
    /// NOTE/GATE (this ferry §5.1, literal): a dashed #3A3E47 max-extent box (unchanged) containing a
    /// 1.5pt LANE-100 OUTLINE rectangle with a LANE-20 fill — replaces the old solid lane-colour block.
    /// Same geometry: width = GATE%, height = VEL/127, anchored bottom-left.
    private func euclideousNoteGatePicture(_ line: EuclidLine, accent: Color) -> some View {
        let gateFrac = max(0.05, min(1, line.gateResolved))
        let velFrac = Double(line.velocityAbsoluteResolved) / 127.0
        return Canvas { ctx, size in
            ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 2),
                       with: .color(Color(hex: 0x3A3E47)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            let w = size.width * CGFloat(gateFrac)
            let h = size.height * CGFloat(velFrac)
            let barRect = CGRect(x: 0, y: size.height - h, width: w, height: h)
            ctx.fill(Path(roundedRect: barRect, cornerRadius: 1.5), with: .color(lane20(accent)))
            ctx.stroke(Path(roundedRect: barRect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.5), with: .color(lane100(accent)), lineWidth: 1.5)
        }
    }
    /// RIFF (this ferry §5.4, literal — replaces the fine 8×7 grid entirely with TWO separate strips, no
    /// grid lines): a row of 8 SHIFT slots along the bottom, a column of OCT slots (the existing -3...+3
    /// range) along the left — they meet at, but don't overlap, the bottom-left corner. Slots are at
    /// least 6pt with 2pt gaps. The current shift slot and the current octave slot are each filled
    /// LANE-100 independently (this is two 1-D strips, not one 2-D cell — there's no single "(shift,oct)"
    /// cell to light the way the old grid had); other slots are #3A3E47. The HIGHLIGHTED slot now wraps
    /// at LENGTH (melody pop-up ferry 2026-10-10), matching `euclideousPadValues`/`commitAxis` — but the
    /// STRIP ITSELF still always draws the fixed `shiftSteps`(8) slots below (deliberately NOT resized
    /// to LENGTH this round — redesigning the visual to a true LENGTH-sized strip is a decision that
    /// belongs to the deferred §6 lane-card redesign, not a numeric-correctness fix; a LENGTH<8 lane's
    /// highlighted slot is still accurate, it just never reaches the slots past LENGTH on an 8-wide strip).
    private func euclideousRiffPicture(_ line: EuclidLine, accent: Color) -> some View {
        let riffLen = line.riffLengthResolved
        let shift = ((line.riffRotateResolved % riffLen) + riffLen) % riffLen
        let oct = line.riffOctaveResolved
        let octRows = 7
        return Canvas { ctx, size in
            let gap: CGFloat = 2
            let thickness = max(6, min(size.width, size.height) * 0.18)   // the strips' own perpendicular thickness
            // LEFT strip: OCT column, full picture height.
            let octSlotH = max(6, (size.height - gap * CGFloat(octRows - 1)) / CGFloat(octRows))
            for row in 0..<octRows {
                let rowOct = 3 - row
                let rect = CGRect(x: 0, y: CGFloat(row) * (octSlotH + gap), width: thickness, height: octSlotH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(rowOct == oct ? lane100(accent) : Color(hex: 0x3A3E47)))
            }
            // BOTTOM strip: SHIFT row, starting past the OCT column so the two strips never overlap.
            let shiftOriginX = thickness + gap
            let shiftAvailW = max(1, size.width - shiftOriginX)
            let shiftSlotW = max(6, (shiftAvailW - gap * CGFloat(shiftSteps - 1)) / CGFloat(shiftSteps))
            for col in 0..<shiftSteps {
                let rect = CGRect(x: shiftOriginX + CGFloat(col) * (shiftSlotW + gap), y: size.height - thickness, width: shiftSlotW, height: thickness)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(col == shift ? lane100(accent) : Color(hex: 0x3A3E47)))
            }
        }
    }
    /// NOTE/OCT (riff off) (this ferry §5.5, literal: "same rows as 5.4"): the SAME discrete-slot OCT
    /// column style 5.4's own left strip uses (6pt+ slots, 2pt gaps, LANE-100/#3A3E47) — spans the full
    /// picture width since there's no SHIFT strip to share it with here. The NOTE choice itself has no
    /// picture — it's text only, line 2 of the readout (§5.5's own words).
    private func euclideousNoteOctPicture(_ line: EuclidLine, accent: Color) -> some View {
        let oct = line.octaveResolved
        let octRows = 7
        return Canvas { ctx, size in
            let gap: CGFloat = 2
            let slotH = max(6, (size.height - gap * CGFloat(octRows - 1)) / CGFloat(octRows))
            for row in 0..<octRows {
                let rowOct = 3 - row
                let rect = CGRect(x: 0, y: CGFloat(row) * (slotH + gap), width: size.width, height: slotH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(rowOct == oct ? lane100(accent) : Color(hex: 0x3A3E47)))
            }
        }
    }

    // MARK: - Single-finger commit + double-tap reset + 2-finger ALL-LANES (ferry §2)

    /// Captures BOTH axes' reference value the moment a touch lands (axis lock isn't decided until 8pt
    /// of movement, so both candidates must be ready before then) — a nudge from wherever the value
    /// currently is, not a fresh-each-touch absolute set. TILT is the one exception (computed from raw
    /// travel alone in `commitAxis`) — its own X baseline here is never read.
    private func padBaseline(_ line: EuclidLine, _ t: EuclideousGestureTab) -> (x: Double, y: Double) {
        switch t {
        case .tiltHits: return (0, Double(line.pulses))
        case .offsetCount:
            let n = max(2, min(16, line.steps))
            return (Double(((line.rotate % n) + n) % n), Double(line.steps))
        case .gateVelocity: return (line.gateResolved * 100, Double(line.velocityAbsoluteResolved))
        case .noteOctave:
            if line.useRiffResolved {
                // SHIFT wraps within LENGTH now, not the old literal 8 (melody pop-up ferry 2026-10-10).
                let n = line.riffLengthResolved
                return (Double(((line.riffRotateResolved % n) + n) % n), Double(line.riffOctaveResolved))
            }
            let idx = euclideousNoteSelCycle.firstIndex(of: line.noteSelResolved) ?? 0
            return (Double(idx), Double(line.octaveResolved))
        }
    }
    /// Commits ONE locked axis's value from (baseline captured at touch-down, cumulative travel since —
    /// RAW for TILT, rebased-to-0-at-lock for every other field, see `EuclideousXYPad`'s own doc comment
    /// for why the two differ). Replaces the OLD delta-accumulation `applyX`/`applyY` for the single-
    /// finger path entirely — the 2-finger ALL-LANES path gets its own, separate delta model below
    /// (`applyAllDelta`), since a continuous accumulation and a baseline+travel commit are genuinely
    /// different shapes, not two readings of the same formula.
    private func commitAxis(_ line: inout EuclidLine, _ t: EuclideousGestureTab, axis: EuclideousXYAxis, baseline: Double, travel: CGFloat) {
        switch (t, axis) {
        case (.tiltHits, .x):
            // TILT — a center DETENT (ferry §2.6, literal): "within ±3% of 0 it rests at exactly 0, and
            // leaving 0 needs 8pt of movement." Under §2.4's own 1pt=1% ratio these are two genuinely
            // DIFFERENT numbers, not one threshold restated — read as a real two-part detent: the first
            // 8pt of travel (fed RAW, not rebased — this IS the axis-lock dead zone itself, so the two
            // combine into one 8pt threshold, not a doubled one) produces no change at all, and the
            // output then picks up from 3% (not 0%) the instant the gate releases — so 0%/1%/2%/3% are
              // the ONLY readings while resting (exactly matching "rests at 0... within ±3%" — nothing
            // reachable in between ever shows as a nonzero 1/2/3%), and the value is continuous from 3%
            // outward once past the gate, with no further discontinuity.
            let a = abs(Double(travel))
            let pct: Double = a <= 8 ? 0 : (3 + (a - 8))
            line.tilt = max(-1, min(1, (travel < 0 ? -pct : pct) / 100))
        case (.tiltHits, .y):
            // FLOOR AT 1, NOT 0 (found on this re-check pass, likely THE actual cause of ferry §9.1's
            // "lane 1 shows 0 hits" report): an earlier, explicitly Paul-ratified ferry established that
            // 0 hits must be reachable ONLY as lanes 2-4's own document default (`euclideousDefaultLine`,
            // Models.swift) — "never reachable through the gesture" — specifically so the HITS pad can't
            // silently zero out a lane a user is actively dragging. The XY-pad-redesign ferry's own
            // planning table (this session, before this one) wrote this clamp as `0...steps` without
            // re-deriving it against that established rule, so it shipped able to drag ANY lane, including
            // lane 1, down to 0 — exactly reproducible by a stray drag while first trying the new pads,
            // then persisting on save and reading as "a fresh instance shows 0 hits" on next launch (a
            // genuinely fresh, never-touched instance can't show this — `euclideousDefaultLine` always
            // opens lane 1 at 1 — so this is the far more likely explanation than a stale document).
            let steps = max(2, min(16, line.steps))
            line.pulses = max(1, min(steps, Int(baseline) + Int((travel / 12).rounded())))
        case (.offsetCount, .x):
            // OFFSET — a flat 12pt/step (ferry §2.4, abandoning the comet bar's own adaptive box-pitch
            // sensitivity for this one control) · SIGN preserved from the established 2026-10-03 fix:
            // dragging right DECREASES rotate, matching the comet bar's own on-screen box movement.
            let n = max(2, min(16, line.steps))
            let v = Int(baseline) - Int((travel / 12).rounded())
            line.rotate = ((v % n) + n) % n
        case (.offsetCount, .y):
            let v = max(2, min(16, Int(baseline) + Int((travel / 12).rounded())))
            line.steps = v
            if line.pulses > v { line.pulses = v }
        case (.gateVelocity, .x):
            let pct = baseline + Double(travel) / 2
            line.gate = max(0.05, min(1, pct / 100))
        case (.gateVelocity, .y):
            line.velocityAbsolute = max(1, min(127, Int(baseline) + Int((travel / 1.5).rounded())))
        case (.noteOctave, .x):
            if line.useRiffResolved {
                let n = line.riffLengthResolved   // wraps within LENGTH now, not the old literal 8 (melody pop-up ferry 2026-10-10)
                let v = Int(baseline) + Int((travel / 12).rounded())
                line.riffRotate = ((v % n) + n) % n
            } else {
                let list = euclideousNoteSelCycle
                let idx = max(0, min(list.count - 1, Int(baseline) + Int((travel / 12).rounded())))
                line.noteSel = list[idx]
            }
        case (.noteOctave, .y):
            let v = max(-3, min(3, Int(baseline) + Int((travel / 12).rounded())))
            if line.useRiffResolved { line.riffOctave = v } else { line.octave = v }
        }
    }
    /// Double-tap reset targets (ferry §2.7) — never HITS/STEPS/NOTE choice.
    private func doubleTapReset(_ line: inout EuclidLine, _ t: EuclideousGestureTab) {
        switch t {
        case .tiltHits: line.tilt = 0
        case .offsetCount: line.rotate = 0
        case .gateVelocity: line.velocityAbsolute = 100; line.gate = 0.9
        case .noteOctave:
            if line.useRiffResolved { line.riffOctave = 0; line.riffRotate = 0 } else { line.octave = 0 }
        }
    }
    /// The 2-finger ALL-LANES path's own mutation — a plain delta accumulation (unlike the single-finger
    /// path's baseline+travel commit above), since this gesture has no dead zone/axis-lock to rebase
    /// against. Mirrors the OLD applyX/applyY exactly in SHAPE (continuous, unconditional, every lane at
    /// once) — only the per-(tab,axis) sensitivity/range rules were unified onto the redesigned single-
    /// finger path's own (see `pointsPerUnit`'s own doc comment for why).
    private func applyAllDelta(_ line: inout EuclidLine, _ t: EuclideousGestureTab, axis: EuclideousXYAxis, _ d: Int) {
        switch (t, axis) {
        case (.tiltHits, .x): line.tilt = max(-1, min(1, line.tiltResolved + Double(d) / 100))
        case (.tiltHits, .y):
            // Same floor-at-1 fix as `commitAxis`'s own HITS case above, applied to the 2-finger ALL-LANES
            // path too — both were found reachable down to 0 on this re-check pass.
            let steps = max(2, min(16, line.steps))
            line.pulses = max(1, min(steps, line.pulses + d))
        case (.offsetCount, .x):
            let n = max(2, min(16, line.steps))
            line.rotate = ((line.rotate - d) % n + n) % n
        case (.offsetCount, .y):
            let v = max(2, min(16, line.steps + d)); line.steps = v; if line.pulses > v { line.pulses = v }
        case (.gateVelocity, .x): line.gate = max(0.05, min(1, line.gateResolved + Double(d) / 100))
        case (.gateVelocity, .y): line.velocityAbsolute = max(1, min(127, line.velocityAbsoluteResolved + d))
        case (.noteOctave, .x):
            if line.useRiffResolved {
                let n = line.riffLengthResolved   // wraps within LENGTH now, not the old literal 8 (melody pop-up ferry 2026-10-10) — this is the 2-finger ALL-LANES commit, missed in the first pass since it's a separate call site from the single-finger one above
                line.riffRotate = ((line.riffRotateResolved + d) % n + n) % n
            } else {
                let list = euclideousNoteSelCycle
                let idx = max(0, min(list.count - 1, (list.firstIndex(of: line.noteSelResolved) ?? 0) + d))
                line.noteSel = list[idx]
            }
        case (.noteOctave, .y):
            let v = max(-3, min(3, (line.useRiffResolved ? line.riffOctaveResolved : line.octaveResolved) + d))
            if line.useRiffResolved { line.riffOctave = v } else { line.octave = v }
        }
    }
    private func euclideousApplyAllDelta(_ t: EuclideousGestureTab, axis: EuclideousXYAxis, _ d: Int) {
        onEdit { lines in for i in lines.indices { applyAllDelta(&lines[i], t, axis: axis, d) } }
    }

    // MARK: - Per-lane tab row + content (Paul 2026-10-07, §2.6)

    private func laneTabRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(EuclideousLaneTab.allCases, id: \.rawValue) { t in
                let sel = (idx < laneTab.count ? laneTab[idx] : .pattern) == t
                // DOT: ONLY MASK carries a dot now (RIFF's own dot retired 2026-10-10 along with its tab) —
                // lane-coloured when "this lane has a mask configured at all" (line.mask != nil). PATTERN
                // never shows one (always "on"); I/O never does either (a lane always has some source).
                let dotOn: Bool = t == .mask && line.mask != nil
                // VIEWS (this ferry §4.3, "the tab row" named explicitly): white text with a 2pt LANE-100
                // underline for the active one, grey text (no fill/outline) when inactive. Label size is
                // §6.2's own literal rule: "set the tab labels to the pad readout line-2 size" —
                // `padSubtitleSize`, not an independently-chosen number, so the two can never drift apart.
                HStack(spacing: 5) {
                    Text(t.label).font(.system(size: padSubtitleSize, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? .white : .white.opacity(0.45))
                        .lineLimit(1)
                    if t == .mask {
                        // LANE-100 (this ferry §4.1: "the RIFF/MASK on-dots" — RIFF's own dot retired).
                        Circle().fill(dotOn ? lane100(accent) : Color.clear)
                            .overlay(Circle().stroke(dotOn ? lane100(accent) : Color.white.opacity(0.35), lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: rowH)
                .overlay(Rectangle().fill(sel ? lane100(accent) : Color.clear).frame(height: 2), alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { if idx < laneTab.count { laneTab[idx] = t } }
            }
        }
    }

    @ViewBuilder private func tabContent(_ idx: Int, _ line: EuclidLine, _ tab: EuclideousLaneTab, _ accent: Color, cellSize: CGFloat, rowH: CGFloat, fullWidth: CGFloat) -> some View {
        switch tab {
        case .io:
            // SOURCE SELECTOR REMOVED (ferry 2026-10-10 §1.3/§1.5) — now lives in the melody pop-up's own
            // SOURCE row; this tab's sole remaining job is the OUT toggles, kept exactly as they are.
            laneOutRow(idx, line, accent: accent).frame(height: rowH)
        case .pattern:
            VStack(spacing: sp4) {
                directionRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
                hitMissRateRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
            }
        case .mask:
            VStack(spacing: sp4) {
                maskCometRow(idx, line, accent, width: fullWidth, height: rowH)
                maskStubRow(rowH)
            }
        }
    }

    /// The 3 DIRECTION buttons — short (not square), same 3 column widths as the gesture pads directly
    /// above, so the two rows line up. Left-to-right: BACKWARDS · PING-PONG · FORWARDS, glyphs "<" / "><" /
    /// ">" (the SAME convention the regular BUILD-page EUCLID editor's own DIRECTION control already uses).
    /// SELECTED CHOICE (this ferry §4.2, "pattern direction" named explicitly): LANE-20 fill, 1pt LANE-100
    /// border, white text — not the old solid-ish fill + black text.
    private func directionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let order: [(EuclidDir, String)] = [(.bkw, "<"), (.pingpong, "><"), (.fwd, ">")]
        return HStack(spacing: sp4) {
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .white : .white.opacity(0.6))
                    .frame(width: cellSize, height: rowH)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? lane20(accent) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.direction = dir } }
            }
        }
    }

    /// HIT | MISS, separated from RATE. REBUILT (Paul 2026-10-10 ferry §2.5/§2.1): MISS is no longer a second
    /// voice to swap into — it's a genuine persisted per-lane setting (`patternMiss`) that inverts which steps
    /// of the pattern sound. Styled as a "selected choice" now (LANE-20 fill, 1pt LANE-100 border, white text
    /// for the active side), matching `directionRow`'s own convention above it — SUPERSEDES the 2026-10-09
    /// view/underline styling, which existed only because the old swap mechanism had no real value of its own
    /// to represent as "selected." RATE is unchanged: its own small group, opens the pop-up on tap, shows
    /// FOLLOW when the line's rate is genuinely unset.
    private func hitMissRateRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let missOn = line.patternMissResolved
        // THREE EQUAL SEGMENTS (ferry §3: "the four pads... equal width, with 4pt gaps" extended consistently
        // to every segmented-button row on the page) — HIT/MISS/RATE each get the SAME `cellSize` directionRow
        // above uses (already sized for 3 columns + 2 sp4 gaps across the card's own inner width), with sp4
        // between all three, not just between the pair and RATE.
        func sideButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(selected ? .white : .white.opacity(0.6))
                .frame(width: cellSize, height: rowH)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? lane20(accent) : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? lane100(accent) : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        return HStack(spacing: sp4) {
            sideButton("HIT", selected: !missOn) { edit(idx) { $0.patternMiss = false } }
            sideButton("MISS", selected: missOn) { edit(idx) { $0.patternMiss = true } }
            VStack(spacing: 1) {
                Text("RATE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Text(line.rate == nil ? "FOLLOW" : line.rate!.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
            .frame(width: cellSize, height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { ratePopupLane = idx }
        }
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

    // MARK: - THE MELODY POP-UP (Paul 2026-10-10 ferry) — anchored to the tapped NOTE VIEW strip with a
    // small pointer (§1.2), NOT the centered scrim+card every other popup above uses — a popover, not a
    // modal. Positioned from the strip's own measured frame (`melodyStripFrames`, published via
    // `EuclideousStripFramePreferenceKey`), the same shape as the XY-pad drag bubble's own
    // `EuclideousPadFramePreferenceKey`/`euclideousBubblePosition` mechanism, generalized here to also
    // decide which DIRECTION it grows (there's real content to fit, unlike the small transient bubble)
    // and to size its own scroll area from the REAL available space in that direction — never a flat
    // guess — so §1.5 ("must never be clipped by the page") holds by construction, not by hope.
    /// Decides whether the pop-up grows above or below the strip (whichever has more room), the real
    /// available height in that direction, and a page-clamped horizontal center — mirrors
    /// `euclideousBubblePosition`'s own clamp idiom, generalized for a much bigger, scrollable card.
    private func euclideousMelodyAnchor(_ frame: CGRect, in pageSize: CGSize) -> (grewAbove: Bool, availableH: CGFloat, centerX: CGFloat) {
        let margin: CGFloat = 12
        let pageInset: CGFloat = 8
        let spaceAbove = frame.minY - pageInset - margin
        let spaceBelow = pageSize.height - frame.maxY - pageInset - margin
        let grewAbove = spaceAbove >= spaceBelow
        let availableH = max(160, grewAbove ? spaceAbove : spaceBelow)
        let cardHalfW: CGFloat = 200   // half of the 400pt card width (§4.1)
        let centerX = min(max(frame.midX, cardHalfW + 16), max(cardHalfW + 16, pageSize.width - cardHalfW - 16))
        return (grewAbove, availableH, centerX)
    }
    /// A small triangular pointer (§1.2, "a small pointer") — the first on this page; no existing shape
    /// to copy wholesale, modeled conceptually on a standard callout/popover notch.
    private func melodyPointer(pointingDown: Bool) -> some View {
        Path { p in
            if pointingDown {
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 16, y: 0)); p.addLine(to: CGPoint(x: 8, y: 8))
            } else {
                p.move(to: CGPoint(x: 0, y: 8)); p.addLine(to: CGPoint(x: 16, y: 8)); p.addLine(to: CGPoint(x: 8, y: 0))
            }
            p.closeSubpath()
        }
        .fill(Color(red: 0.1, green: 0.11, blue: 0.13))
        .frame(width: 16, height: 8)
    }
    /// §4.1/§4.2 colour hierarchy, followed literally even though it diverges slightly from this page's
    /// own pre-existing `Color.white.opacity(0.06)` unselected-button fill elsewhere (`directionRow`/
    /// `ioSourceRow`) — this section explicitly cites "the colour-hierarchy ferry" as its authority, so
    /// its own exact hex is used as given: selected = LANE-20 fill + 1pt LANE-100 border + white text;
    /// unselected = literal #2A2D34 fill + grey text. 40pt tall (§4.4).
    private func melodyButton(_ label: String, on: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .white : Color.white.opacity(0.55))
            .lineLimit(1)   // §4.6: nothing under 10pt — truncate, never shrink (no .minimumScaleFactor call at all, SwiftUI's own default already never scales below 1.0)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? lane20(accent) : Color(hex: 0x2A2D34)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? lane100(accent) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
    /// §4.4: `[−] value [+]`, 36pt −/+ buttons. No existing generic stepper on this page (confirmed by
    /// direct search) — `headerKeyGroup`'s hand-assembled two-single-glyph-buttons shape is the only
    /// precedent to crib from, properly parameterized here instead of re-hand-assembled per call site.
    private func melodyStepper(_ label: String, value: Int, range: ClosedRange<Int>, unit: String? = nil, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: sp4) {
                Text("−").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { onChange(max(range.lowerBound, value - 1)) }
                Text(unit != nil ? "\(euclideousSigned(value)) \(unit!)" : "\(value)")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white).lineLimit(1)
                    .frame(minWidth: 44)
                Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { onChange(min(range.upperBound, value + 1)) }
            }
        }
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
    private func melodySourceSection(_ idx: Int, line: EuclidLine, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: sp4) {
            melodySectionTitle("SOURCE")
            HStack(spacing: sp4) {
                ForEach([EuclideousLaneSource.midi, .key, .chords], id: \.self) { src in
                    melodyButton(src == .midi ? "MIDI IN" : (src == .key ? "KEY" : "CHORDS"), on: line.sourceModeResolved == src, accent: accent) {
                        edit(idx) { $0.sourceMode = src }
                    }
                }
            }
        }
    }
    private func melodyModeSection(_ idx: Int, line: EuclidLine, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: sp4) {
            melodySectionTitle("MODE")
            HStack(spacing: sp4) {
                melodyButton("RIFF", on: line.useRiffResolved, accent: accent) { edit(idx) { $0.useRiff = true } }
                melodyButton("NOTE", on: !line.useRiffResolved, accent: accent) { edit(idx) { $0.useRiff = false } }
            }
        }
    }
    /// §4.3: "the NOTE choices as segmented buttons, wrapping onto further rows as needed" — chunked 4
    /// per row from the SAME RANDOM-free `euclideousNoteSelCycle` the old 4th pad's drag-cycle also
    /// reads, so the two can never offer a different set.
    private func melodyNoteSection(_ idx: Int, line: EuclidLine, accent: Color) -> some View {
        let items = euclideousNoteSelCycle
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        return VStack(alignment: .leading, spacing: sp4) {
            melodySectionTitle("NOTE")
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: sp4) {
                    ForEach(rows[r], id: \.self) { sel in
                        melodyButton(melodyNoteSelLabel(sel), on: line.noteSelResolved == sel, accent: accent) {
                            edit(idx) { $0.noteSel = sel }
                        }
                    }
                }
            }
        }
    }
    /// §4.3's 4 WALK rows exactly: DIRECTION (5, RANDOM dropped per §2.1) · FREE/LOCK+INVERT+HIT/STEP ·
    /// ON REST, labelled · STRIDE+LENGTH steppers, labelled.
    private func melodyWalkSection(_ idx: Int, line: EuclidLine, accent: Color) -> some View {
        let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong, .drunk]
        return VStack(alignment: .leading, spacing: sp4) {
            melodySectionTitle("WALK")
            HStack(spacing: sp4) {
                ForEach(dirs, id: \.self) { d in
                    melodyButton(riffDirShortLabel(d), on: line.riffDirResolved == d, accent: accent) { edit(idx) { $0.riffDir = d } }
                }
            }
            HStack(spacing: sp4) {
                melodyButton(line.riffLockResolved ? "LOCK" : "FREE", on: line.riffLockResolved, accent: accent) {
                    edit(idx) { $0.riffLock = !($0.riffLockResolved) }
                }
                melodyButton("INVERT", on: line.riffInvertResolved, accent: accent) {
                    edit(idx) { $0.riffInvert = !($0.riffInvertResolved) }
                }
                melodyButton(line.riffAdvanceStepResolved ? "STEP" : "HIT", on: line.riffAdvanceStepResolved, accent: accent) {
                    edit(idx) { $0.riffAdvanceStep = !($0.riffAdvanceStepResolved) }
                }
            }
            HStack(spacing: sp4) {
                Text("ON REST").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                ForEach([EuclidRiffOnRest.skip, .fill, .tie], id: \.self) { r in
                    melodyButton(r.rawValue, on: line.riffOnRestResolved == r, accent: accent) { edit(idx) { $0.riffOnRest = r } }
                }
            }
            HStack(spacing: sp16) {
                melodyStepper("STRIDE", value: line.riffStrideResolved, range: 1...7) { v in edit(idx) { $0.riffStride = v } }
                melodyStepper("LENGTH", value: line.riffLengthResolved, range: 1...8) { v in edit(idx) { $0.riffLength = v } }
            }
        }
    }
    /// §4.3's final row: SHIFT (RIFF-only, hidden in NOTE mode per the ratified reading — its own range
    /// depends on LENGTH, a WALK-only concept) + TRANSPOSE (both modes) + OCT (both modes), one row.
    private func melodyPlacementSection(_ idx: Int, line: EuclidLine, accent: Color) -> some View {
        let transposeUnit = line.sourceModeResolved == .key ? "st" : "pos"   // §4.5
        return VStack(alignment: .leading, spacing: sp4) {
            melodySectionTitle("PLACEMENT")
            HStack(spacing: sp16) {
                if line.useRiffResolved {
                    let n = line.riffLengthResolved
                    let shift = ((line.riffRotateResolved % n) + n) % n
                    melodyStepper("SHIFT", value: shift, range: 0...(n - 1)) { v in edit(idx) { $0.riffRotate = v } }
                }
                melodyStepper("TRANSPOSE", value: line.melodyTransposeResolved, range: -7...7, unit: transposeUnit) { v in
                    edit(idx) { $0.melodyTranspose = v }
                }
                melodyStepper("OCT", value: line.useRiffResolved ? line.riffOctaveResolved : line.octaveResolved, range: -3...3) { v in
                    edit(idx) { l in if l.useRiffResolved { l.riffOctave = v } else { l.octave = v } }
                }
            }
        }
    }
    /// §4.2: lane-colour dot + "LANE n · MELODY" + ✕ — combines three previously-separate precedents
    /// (the dot from `noteViewLabelRow`, the "LANE n ..." title phrasing from `ratePopupCard`/
    /// `riffDirPopupCard`, the ✕ from `chordsPopupCard`); no single existing popup header has all three.
    private func melodyPopupCard(_ idx: Int, availableHeight: CGFloat, grewAbove: Bool) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let accent = laneAccents[idx % laneAccents.count]
        let cardWidth: CGFloat = 400
        let headerH: CGFloat = 28
        let pointerH: CGFloat = 8
        // §1.5: the ScrollView's own height budget comes from the REAL space available in whichever
        // direction the card grew (`availableHeight`, from `euclideousMelodyAnchor`), minus the header/
        // pointer/padding this same card adds around it — never a flat, unverified guess.
        let scrollMaxH = max(100, availableHeight - headerH - pointerH - sp16 * 2 - sp16)
        let header = HStack(spacing: sp8) {
            Circle().fill(lane100(accent)).frame(width: 8, height: 8)
            Text("LANE \(idx + 1) · MELODY").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
            Spacer()
            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.5))
                .contentShape(Rectangle()).onTapGesture { melodyPopupLane = nil }
        }
        .frame(height: headerH)
        let body = ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: sp16) {
                melodySourceSection(idx, line: line, accent: accent)
                melodyModeSection(idx, line: line, accent: accent)
                if line.useRiffResolved { melodyWalkSection(idx, line: line, accent: accent) }
                else { melodyNoteSection(idx, line: line, accent: accent) }
                melodyPlacementSection(idx, line: line, accent: accent)
            }
        }
        .frame(maxHeight: scrollMaxH)
        let card = VStack(alignment: .leading, spacing: sp16) { header; body }
            .padding(sp16)
            .frame(width: cardWidth)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        return VStack(spacing: 0) {
            if !grewAbove { melodyPointer(pointingDown: false) }
            card
            if grewAbove { melodyPointer(pointingDown: true) }
        }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - Per-lane EUCLID MASK (Paul 2026-10-07, §2.7 — pattern/transport only, effect deferred §4.1)

    /// A SECOND, independent `EuclidCometBar` + play/stop pair, driven by the lane's own `mask` field — NOT
    /// `EuclidLaneBox` (that component's `selected`/`onSelect`/`trailingContent` machinery has no meaning
    /// for a mask), but the SAME shared `EuclidCometBar`/`EuclidGesturePad` the lane's own box uses, per the
    /// spec's own wording ("the same lane control — step box / comet bar, play button and count control").
    /// Rotation is a drag directly on this grid (`onRotateDelta`) — no separate rotate control, per §2.7.
    /// Fed the page's shared `clock` and a nominal `.r1_16`/`spanN: 0` purely for the cosmetic comet-sweep —
    /// the mask has no engine consumer yet (it isn't read anywhere in Router.swift), so this is decoration,
    /// not a live transport.
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
            EuclidCometBar(pulses: m.pulsesResolved, steps: steps, rotate: m.rotate ?? 0, invert: false, dir: .fwd,
                           rate: .r1_16, spanN: 0, tint: accent, lanePlaying: m.enabledResolved, clock: clock,
                           // 36(play)+36(step count)+2×sp4(the HStack's own gaps either side of this view)
                           width: max(1, width - 36 - 36 - sp4 * 2),
                           onRotateDelta: { d in euclideousApplyMaskX(idx, d) },
                           onHitsDelta: { d in euclideousApplyMaskY(idx, d) },
                           onStepsDelta: { d in editMask(idx) { let v = max(2, min(16, $0.stepsResolved + d)); $0.steps = v; if $0.pulsesResolved > v { $0.pulses = v } } },
                           onAllRotateDelta: { d in euclideousApplyAllMaskX(d) },
                           onAllHitsDelta: { d in euclideousApplyAllMaskY(d) },
                           onDragState: { point, allRows in
                               guard let point else { dragHUDInfo = nil; return }
                               dragHUDInfo = EuclidDragHUDInfo(label: allRows ? "ALL MASKS" : "LANE \(idx + 1) MASK",
                                                                primary: "\(m.pulsesResolved) OF \(steps)", secondary: "ROTATE \(m.rotate ?? 0)", point: point)
                           })
                .frame(height: max(36, height))
            Text("\(steps)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .frame(width: 36, height: max(36, height))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
        }
        .frame(height: max(36, height))
    }

    private func applyMaskRotate(_ m: inout EuclidLineMask, _ d: Int) { let steps = m.stepsResolved; m.rotate = (((m.rotate ?? 0) - d) % steps + steps) % steps }
    private func applyMaskHits(_ m: inout EuclidLineMask, _ d: Int) { m.pulses = max(1, min(m.stepsResolved, m.pulsesResolved + d)) }
    private func euclideousApplyMaskX(_ idx: Int, _ d: Int) { editMask(idx) { applyMaskRotate(&$0, d) } }
    private func euclideousApplyMaskY(_ idx: Int, _ d: Int) { editMask(idx) { applyMaskHits(&$0, d) } }
    private func euclideousApplyAllMaskX(_ d: Int) { onEdit { lines in for i in lines.indices { var m = lines[i].mask ?? EuclidLineMask(); applyMaskRotate(&m, d); lines[i].mask = m } } }
    private func euclideousApplyAllMaskY(_ d: Int) { onEdit { lines in for i in lines.indices { var m = lines[i].mask ?? EuclidLineMask(); applyMaskHits(&m, d); lines[i].mask = m } } }

    /// MASK line 2 — the effect picker / amount / hit-count the ratified mockup drew is explicitly DEFERRED
    /// (spec §4.1: "Build the MASK tab's line 1... and leave line 2 as a marked stub. The mask must not
    /// change the lane's output until its effects are ruled.") A plain, visibly inert placeholder — not a
    /// dead-looking-but-tappable control, and not silently omitted.
    private func maskStubRow(_ rowH: CGFloat) -> some View {
        Text("EFFECT — NOT YET AVAILABLE")
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.3)).lineLimit(1)
            .frame(maxWidth: .infinity).frame(height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // MARK: - The I/O tab (Paul 2026-10-08): per-lane MIDI IN | KEY | CHORDS + the lane's own OUT toggles

    // ioSourceRow RETIRED (ferry 2026-10-10 §1.3) — the MIDI IN/KEY/CHORDS selector now lives in the melody
    // pop-up's own SOURCE row; the I/O tab's sole remaining content is `laneOutRow` below (§1.5: unchanged).

    // MARK: - OUT row (Paul 2026-10-07, §2.8/§3: smaller toggles, NO OUTPUT, dashed/hollow main-held chips)

    /// `laneControls` from the pre-rework page collapses to just this one row — the two `EuclidBeacon` calls
    /// that used to sit above it are REMOVED entirely (§2.8: "remove the hit/miss beacons"). Fixed at 30pt
    /// (ferry §3: "do not make lane OUT... any smaller than they are now") regardless of any outer scale.
    /// MOVED (Paul 2026-10-08) into the lane's own new I/O tab, row 2 — no longer always-visible below every
    /// tab; switching to PATTERN/RIFF/MASK hides it, by design ("a new tab for input/output... the four
    /// emitter toggles on the second row").
    /// SELECTED CHOICE (this ferry §4.2, "active OUT toggles" named explicitly): a FULLY-active bus
    /// (routed AND the MAIN OUT master is on) gets LANE-20 fill + 1pt LANE-100 border + white text — not
    /// the old solid fill + black text. The DASHED/hollow "routed but MAIN-gated" state is a genuinely
    /// THIRD, separate condition §4.2 doesn't name — left as-is. No `.minimumScaleFactor` (§6.1's floor);
    /// the "OUT"/"NO OUTPUT" captions, previously 9pt, are bumped to the same 10pt floor.
    @ViewBuilder private func laneOutRow(_ idx: Int, _ line: EuclidLine, accent: Color) -> some View {
        let mask = line.emitterMask ?? 0
        HStack(spacing: sp4) {
            Text("OUT").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            ForEach(0..<4, id: \.self) { b in
                let routed = (mask >> UInt8(b)) & 1 != 0
                let mainOn = (mainOutMask >> UInt8(b)) & 1 != 0
                // TWO SEPARATE CONDITIONS (spec audit item 3, not one "something's wrong" treatment): a bit
                // that's SET but whose MAIN toggle is off draws dashed/hollow (still shows routing intent);
                // "no output at all" is handled separately below via the trailing NO OUTPUT label.
                ZStack {
                    if routed && mainOn {
                        Circle().fill(lane20(accent)).overlay(Circle().stroke(lane100(accent), lineWidth: 1))
                    } else if routed {
                        Circle().fill(Color.clear).overlay(Circle().stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
                    } else {
                        Circle().fill(Color.white.opacity(0.08))
                    }
                    Text(["A", "B", "C", "D"][b]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(routed && mainOn ? .white : (routed ? accent : .white.opacity(0.5)))
                }
                .frame(width: laneOutSize, height: laneOutSize)
                .contentShape(Circle())
                .onTapGesture { edit(idx) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
            }
            Spacer(minLength: 4)
            if mask == 0 {
                Text("NO OUTPUT").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(red: 1, green: 0.71, blue: 0.33))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - The RATE pop-up (Paul 2026-10-06, unchanged — spec §4.8: "not discussed")

    private func ratePopupCard(_ idx: Int) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let groups = stride(from: 0, to: ArpRate.allCases.count, by: 6).map { Array(ArpRate.allCases[$0..<min($0 + 6, ArpRate.allCases.count)]) }
        return VStack(spacing: 10) {
            Text("LANE \(idx + 1) RATE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Text("— (MACHINE RATE)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(line.rate == nil ? .black : .white.opacity(0.75))
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(line.rate == nil ? laneAccents[idx % laneAccents.count] : Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { edit(idx) { $0.rate = nil }; ratePopupLane = nil }
            ForEach(groups.indices, id: \.self) { g in
                HStack(spacing: 4) {
                    ForEach(groups[g], id: \.self) { r in
                        let on = line.rate == r
                        Text(r.rawValue).font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.75))
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? laneAccents[idx % laneAccents.count] : Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                            .onTapGesture { edit(idx) { $0.rate = r }; ratePopupLane = nil }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

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
    private func riffGridView(maxWidth: CGFloat, rowH: CGFloat) -> some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        let cellW = max(1, (maxWidth - sp8 * 2 - sp4 * CGFloat(n - 1)) / CGFloat(n))
        let cellH = max(1, rowH)
        return VStack(alignment: .leading, spacing: sp4) {
            // TITLE ONLY (this ferry §7.1, literal): "remove the subtitle... the title is just 'RIFF'."
            Text("RIFF").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            // POSITION DOTS ONLY (this ferry §7.2, literal): "the thin row of half-height cells above the
            // grid looks like a rendering fault. Do not draw cells there." The old per-column background
            // rect (`Color.white.opacity(0.04)`, drawn for EVERY column whether or not a dot sits on it)
            // was exactly that fault — removed entirely; this row now draws NOTHING but the dots
            // themselves, in the reserved `riffDotRowH` (10pt) height.
            HStack(spacing: sp4) {
                ForEach(0..<n, id: \.self) { col in
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] == col {
                                Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .frame(width: cellW, height: riffDotRowH)
                }
            }
            VStack(spacing: sp4) {
                ForEach((1...8).reversed(), id: \.self) { rank in
                    HStack(spacing: sp4) {
                        ForEach(0..<n, id: \.self) { col in
                            let on = col < ranks.count && ranks[col] == rank
                            RoundedRectangle(cornerRadius: 3)
                                .fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                                .frame(width: cellW, height: cellH)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onEditRiff { r in
                                        var rr = (0..<n).map { k -> Int in let rv = r.ranksResolved; return k < rv.count ? rv[k] : 0 }
                                        if col < rr.count { rr[col] = (rr[col] == rank ? 0 : rank) }
                                        r.ranks = rr; r.steps = n
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding(sp8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
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
        return VStack(spacing: sp4) {
            ForEach(0..<4, id: \.self) { idx in
                noteViewStrip(idx, width: innerW, height: stripH, cyc: cyc, windowBeats: windowBeats)
            }
        }
        .padding(sp8)
        .frame(width: maxWidth, height: maxHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }

    /// One lane's strip (ferry 1 §1.1-§1.3 + ferry 2 §1.1-§1.4): a 14pt label row, then the track+playhead+
    /// note-box row filling whatever height remains.
    private func noteViewStrip(_ idx: Int, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let accent = laneAccents[idx % laneAccents.count]
        let labelH: CGFloat = 14
        let bodyH = max(1, height - labelH)
        return VStack(alignment: .leading, spacing: 0) {
            noteViewLabelRow(line, accent: accent, width: width)
            noteViewTrackRow(idx, line, accent: accent, width: width, height: bodyH, cyc: cyc, windowBeats: windowBeats)
        }
        .frame(width: width, height: height, alignment: .leading)
        // STRIP FRAME PUBLISHING (melody pop-up ferry §1.2, "anchored to the strip") — the direct sibling
        // of the XY pad's own frame-publishing background (`EuclideousPadFramePreferenceKey`), same
        // coordinate space, so the pop-up can anchor itself here.
        .background(
            GeometryReader { g in
                Color.clear.preference(key: EuclideousStripFramePreferenceKey.self,
                                        value: [idx: g.frame(in: .named("euclideousXY"))])
            }
        )
        .overlay(alignment: .top) {
            // THE TAP TARGET (§1.1, literal): "a 30pt-tall touch area, extending invisibly into the top
            // of the track." An `.overlay` never feeds back into its host's own layout size, so this
            // doesn't steal any height from the track below — it just paints/hit-tests an invisible 30pt
            // zone OVER the label (14pt) plus the track's own top 16pt. Scoped to exactly 30pt so "taps
            // on the track and note box must never open it" holds by construction: nothing below this
            // overlay's own bounds is affected.
            Rectangle().fill(Color.clear).frame(width: width, height: 30)
                .contentShape(Rectangle())
                .onTapGesture { melodyPopupLane = idx }
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
    private func noteViewLabelRow(_ line: EuclidLine, accent: Color, width: CGFloat) -> some View {
        let dotAndGap: CGFloat = 6 + 4
        let textW = max(1, width - dotAndGap)
        return HStack(spacing: 4) {
            Circle().fill(lane100(accent)).frame(width: 6, height: 6)
            Text(noteViewLabelText(line, maxWidth: textW))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0xAAB0BA)).lineLimit(1)
        }
        .frame(width: width, height: 14, alignment: .leading)
    }
    /// The ordered content items (ferry 2 §2, literal order) — always Source + Mode, then only the
    /// non-default modifiers that apply, in the stated order.
    private func noteViewLabelItems(_ line: EuclidLine) -> [String] {
        var items: [String] = []
        items.append(line.sourceModeResolved == .midi ? "MIDI" : (line.sourceModeResolved == .key ? "KEY" : "CHD"))
        if line.useRiffResolved {
            items.append("RIFF " + riffDirShortLabel(line.riffDirResolved))
        } else {
            // §2.2, literal: "the lane's NOTE choice name (e.g. LOWEST, ALL)". The ferry's own worked
            // examples repeat "LOWEST" (not the raw "LOW") twice, consistently — strong enough to read
            // as the intended DISPLAY text for this one case, not just a loose gloss (ALL's own example
            // matches its raw value exactly, so this isn't a blanket rename — just LOW, which reads
            // abruptly short as a standalone label where HIGH/ALL/etc. already read as complete words).
            items.append(line.noteSelResolved == .low ? "LOWEST" : line.noteSelResolved.rawValue)
        }
        if line.useRiffResolved {
            // SHIFT wraps within LENGTH now, not the old literal 8 (melody pop-up ferry 2026-10-10).
            let n = line.riffLengthResolved
            let shift = ((line.riffRotateResolved % n) + n) % n
            if shift != 0 { items.append("SHIFT \(shift)") }
        }
        let oct = line.useRiffResolved ? line.riffOctaveResolved : line.octaveResolved
        if oct != 0 { items.append("OCT \(euclideousSigned(oct))") }
        if line.useRiffResolved {
            if line.riffLockResolved { items.append("LOCK") }
            if line.riffInvertResolved { items.append("INV") }   // riffInvert — NOT the separate HIT/MISS swap toggle
            if line.riffOnRestResolved != .skip { items.append(line.riffOnRestResolved == .fill ? "REST FILL" : "REST TIE") }
            // STRIDE/LENGTH (melody pop-up ferry 2026-10-10 §5), after the existing riff items — WALK-
            // section, RIFF-mode-only fields per §2's own table.
            if line.riffStrideResolved != 1 { items.append("STRIDE \(line.riffStrideResolved)") }
            if line.riffLengthResolved != 8 { items.append("LEN \(line.riffLengthResolved)") }
        }
        // TRANSPOSE (§5) applies in both modes — PLACEMENT isn't WALK-only, matching the pop-up's own
        // layout. §5's own literal order is STRIDE·LEN·TRANS·ADV STEP, so TRANS lands here, between the
        // two RIFF-only groups above and below, even though it isn't itself RIFF-gated.
        if line.melodyTransposeResolved != 0 { items.append("TRANS \(euclideousSigned(line.melodyTransposeResolved))") }
        // ADVANCE (§5, last in the ferry's own order) has no engine effect at all outside RIFF mode —
        // gated here too, not shown as a dangling, inert setting in NOTE mode.
        if line.useRiffResolved && line.riffAdvanceStepResolved { items.append("ADV STEP") }
        return items
    }
    /// §3.2, literal: "never truncate in the middle of a word or show an ellipsis. If the line doesn't fit,
    /// drop whole items from the end and finish with '+n'." No live text-measurement API is available here
    /// (the same disclosed limitation as the axis-label fit-check built for the previous ferry) — estimates
    /// width via this file's own established 0.6×point-size monospaced-character convention. Tries the full
    /// item list first, then drops one item from the end at a time (re-joining with "+n" once anything is
    /// dropped) until the estimate fits — read literally, not reserving Source/Mode as a protected floor
    /// beyond the natural consequence of them being FIRST in the list (so they're the last to ever be cut).
    private func noteViewLabelText(_ line: EuclidLine, maxWidth: CGFloat) -> String {
        let items = noteViewLabelItems(line)
        let charWidth: CGFloat = 10 * 0.6
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

    private func noteViewTrackRow(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double) -> some View {
        let noteBoxW: CGFloat = 56
        let gap: CGFloat = 8
        let trackW = max(1, width - noteBoxW - gap)
        return HStack(spacing: 0) {
            noteViewTrack(idx, line, accent: accent, width: trackW, height: height, cyc: cyc, windowBeats: windowBeats)
            Color.clear.frame(width: gap)
            noteViewNoteBox(idx, line, accent: accent, width: noteBoxW, height: height)
        }
        .frame(width: width, height: height)
    }

    /// The continuously-moving rhythm track (ferry 1 §2/§3) — one `TimelineView` per strip (a disclosed,
    /// behaviourally-equivalent simplification of "one shared TimelineView per panel": all 4 read the SAME
    /// `clock` anchor/tempo, so they tick in lockstep off the same display-link schedule regardless of
    /// whether they share one `TimelineView` instance or each own one). `.animation()` with NO
    /// `minimumInterval` override (§5.2: "render at the display refresh rate") — a deliberate departure
    /// from `EuclidCometBar`'s own 1/30 cap elsewhere on this page, since this is a new, explicit
    /// instruction, not an inherited convention.
    private func noteViewTrack(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat, cyc: Double, windowBeats: Double) -> some View {
        let running = clock.playing && line.enabledResolved   // §2.6: a stopped lane draws no marks
        let sub = max(0.03125, line.rate?.beats ?? ArpRate.r1_16.beats)
        let buf = euclideousNoteViewPattern(pulses: line.pulses, steps: line.steps, rotate: line.rotate, tilt: line.tiltResolved, patternMiss: line.patternMissResolved)
        let spanBeats = euclideousNoteViewSpanBeats(resetSpanBars: resetSpanBars, cyc: cyc)
        let dir = line.directionResolved
        return TimelineView(.animation(paused: !clock.playing)) { tl in
            let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            Canvas { ctx, size in
                guard running, windowBeats > 0 else { return }
                // RE-CHECKED, a real bug fixed on this pass: `euclideousNoteViewMarkX` makes any tick with
                // `age = tickBeat - nowBeat` in `0...windowBeats` visible — meaning FUTURE ticks up to a
                // full `windowBeats` ahead must be scanned, not just one. The original loop's upper bound
                // was a bare `latestTick + 1` (one tick ahead, a leftover from an earlier, wrong mental
                // model that only "the next tick" needed drawing) while its LOWER bound wastefully scanned
                // `lookback` ticks that can never satisfy `age >= 0` in the first place (tick `latestTick`
                // itself already has `age <= 0` by construction — anything earlier is strictly more
                // negative). Fixed: scan forward from `latestTick` through the full lookahead the window
                // actually promises, nothing behind it (the position function's own guard discards anything
                // that doesn't belong, so a little slack here costs nothing).
                let latestTick = Int((liveBeat / sub).rounded(.down))
                let aheadTicks = Int((windowBeats / sub).rounded(.up)) + 1
                for t in latestTick...(latestTick + aheadTicks) {
                    let tickBeat = Double(t) * sub
                    guard let x = euclideousNoteViewMarkX(tickBeat: tickBeat, nowBeat: liveBeat, windowBeats: windowBeats, trackW: size.width) else { continue }
                    let isHit = euclideousNoteViewIsHit(buf: buf, tickBeat: tickBeat, sub: sub, spanBeats: spanBeats, dir: dir)
                    noteViewDrawMark(&ctx, x: x, midY: size.height / 2, isHit: isHit, accent: accent)
                }
                // PLAYHEAD (§1.2): fixed 2pt white-60% line at the track's trailing edge — drawn every
                // frame regardless of `running`, so a stopped lane's track still shows where marks WOULD
                // land, just with none currently approaching it.
                ctx.fill(Path(CGRect(x: size.width - 2, y: 0, width: 2, height: size.height)), with: .color(Color.white.opacity(0.6)))
            }
        }
        .frame(width: width, height: height)
    }
    /// §3, literal mark styles. The hit's own 16pt tail fades LEFT (behind the direction of travel, since
    /// marks move left→right toward the playhead on the right).
    private func noteViewDrawMark(_ ctx: inout GraphicsContext, x: CGFloat, midY: CGFloat, isHit: Bool, accent: Color) {
        if isHit {
            var tail = Path(); tail.move(to: CGPoint(x: x, y: midY)); tail.addLine(to: CGPoint(x: x - 16, y: midY))
            ctx.stroke(tail, with: .linearGradient(Gradient(colors: [lane100(accent).opacity(0.6), lane100(accent).opacity(0)]),
                                                    startPoint: CGPoint(x: x, y: midY), endPoint: CGPoint(x: x - 16, y: midY)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: midY - 4, width: 8, height: 8)), with: .color(lane100(accent)))
        } else {
            // the hollow-ring "miss-playing" mark RETIRED 2026-10-10 (ferry §4.2) — there's only ever one
            // voice per lane now, so a silent step is always this plain dim dot, never a second mark style.
            ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: midY - 2, width: 4, height: 4)), with: .color(Color(hex: 0x3A3E47)))
        }
    }

    /// The note box (ferry 1 §4) — a pure function of (the reconciled last event / rest-flash for this
    /// lane, the live extrapolated beat), evaluated fresh every frame; no event-queue bookkeeping happens
    /// here, that's already done once in AudioUnitViewController's own poll.
    private func noteViewNoteBox(_ idx: Int, _ line: EuclidLine, accent: Color, width: CGFloat, height: CGFloat) -> some View {
        let lastEvent = idx < noteViewLastEvent.count ? noteViewLastEvent[idx] : nil
        let restFlash = idx < noteViewRestFlash.count ? noteViewRestFlash[idx] : nil
        let flatKey = euclideousKeyIsFlat(keyRoot)
        // RE-CHECKED, a real gap closed on this pass: this used to pause only on the GLOBAL transport
        // (`!clock.playing`) — but §2.6 says "a stopped LANE... its note box keeps its last state," and a
        // single lane can be individually disabled (PLAY/STOP) while the transport keeps running elsewhere.
        // Without this, a just-disabled lane's box kept animating its OWN already-in-flight fade (driven by
        // `liveBeat`, which keeps advancing with the still-running transport) even though no new engine
        // events could possibly arrive for it — a box that's supposed to be frozen kept visibly changing.
        return TimelineView(.animation(paused: !(clock.playing && line.enabledResolved))) { tl in
            let liveBeat = clock.anchor + tl.date.timeIntervalSince(clock.anchorAt) * clock.tempo / 60.0
            noteViewNoteBoxContent(liveBeat: liveBeat, lastEvent: lastEvent, restFlash: restFlash, accent: accent, flatKey: flatKey)
                .frame(width: width, height: height)
        }
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
    @ViewBuilder private func noteViewNoteBoxContent(liveBeat: Double, lastEvent: Router.EuclideousNoteViewEventSnapshot?, restFlash: Router.EuclideousNoteViewEventSnapshot?, accent: Color, flatKey: Bool) -> some View {
        // §4.5, SKIP: "show a grey '—' for one step's duration, then return to the previous note at 40%" —
        // the flash is checked first and, while active, fully REPLACES whatever the note box would
        // otherwise show; once it ends, falls straight through to `lastEvent`'s own (already-40%, since
        // real time has passed) state below, with no special-case code needed for the "return to" part.
        if let rf = restFlash, liveBeat >= rf.onsetBeat, liveBeat < rf.onsetBeat + rf.durationBeat {
            Text("—").font(.system(size: padValueSize, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: 0x8A909A))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        } else if let ev = lastEvent {
            // RE-CHECKED: §4.4's general rule ("fades linearly... over the note's gate length") is for a
            // plain hit/miss (kind 0/1) — but §4.5's TIE case is worded distinctly ("keep showing the held
            // note at FULL brightness, fading FROM THE END of the extended note"), not "use 4.4's formula
            // with a longer input." Read literally: a tied note stays fully lit for its WHOLE held span
            // (it's still genuinely sounding) and only settles to the 40% floor once that span is actually
            // over — a step, not a second gradual ramp (the ferry names no separate post-release fade
          // duration, and §4.4's own closing line — "stays at 40% until the next note" — already describes
            // that floor as a plain settled state, not something reached via its own fade). `kind == 3`
            // (Router.swift, a tied hit) is the one case this applies to; kind 0/1 keep the continuous ramp.
            // (An `if/else` STATEMENT assigning to this `let` directly, written inline here, fails to
            // compile inside a `@ViewBuilder` body — Swift's result-builder transform tries to treat the
            // `if` as View-producing control flow, not a plain scalar computation; moved to a bare
            // (non-@ViewBuilder) function so ordinary imperative code works as expected.)
            let brightness = noteViewBrightness(kind: ev.kind, onsetBeat: ev.onsetBeat, durationBeat: ev.durationBeat, liveBeat: liveBeat)
            let names = noteViewStackedNames(ev.notes, flatKey: flatKey)
            // §4.2, literal: "white, bold, VALUE TYPE SIZE" — this was wrongly drawn at `padHeadingSize`
            // (10pt, this page's AXIS-LABEL size) instead of `padValueSize` (13pt, the page's own established
            // "value type size" from the layout-system ferry) — a real mismatch against an explicit
            // instruction, not a judgment call, caught only by re-reading the ferry's literal words again.
            let stack = VStack(spacing: 1) {
                ForEach(names.indices, id: \.self) { i in
                    Text(names[i]).font(.system(size: padValueSize, weight: .heavy, design: .monospaced)).lineLimit(1)
                }
            }
            // MISS-PLAYING's own outline style RETIRED 2026-10-10 (ferry §4.2: "every note shows in the normal
            // note-box style") — `kind == 1` is no longer pushed by anything (its one push site, the old
            // dual-voice miss branch, is gone from Router.swift), so this is now the only style.
            // §4.2, literal: "white, bold... on a LANE-20 fill."
            stack.foregroundColor(.white).opacity(brightness)
                .background(RoundedRectangle(cornerRadius: 6).fill(lane20(accent)).opacity(brightness))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04))
        }
    }
    /// §4.6, literal: up to 3 names stacked lowest-at-bottom; beyond 3, the top two plus "+n". Returned
    /// TOP-TO-BOTTOM (index 0 renders first/topmost in the plain VStack above) — highest pitch first, so
    /// the lowest (or, past 3, the "+n" summary) always lands last/bottom.
    private func noteViewStackedNames(_ notes: [UInt8], flatKey: Bool) -> [String] {
        guard !notes.isEmpty else { return [] }
        let sorted = notes.sorted()   // ascending
        if sorted.count <= 3 {
            return sorted.reversed().map { euclideousNoteViewName($0, flatKey: flatKey) }
        }
        let topTwo = sorted.suffix(2).reversed().map { euclideousNoteViewName($0, flatKey: flatKey) }
        return topTwo + ["+\(sorted.count - 2)"]
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
