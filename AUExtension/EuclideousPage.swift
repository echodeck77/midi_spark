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
enum EuclideousLaneTab: Int, CaseIterable {
    case io = 0, pattern = 1, riff = 2, mask = 3
    var label: String { switch self { case .io: "I/O"; case .pattern: "PATTERN"; case .riff: "RIFF"; case .mask: "MASK" } }
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
    // HIT|MISS SELECTOR (Paul 2026-10-06): "I want the outline of the hit button to look selected and the
    // misses to appear like hits do now" — a symmetric 2-way toggle (not the old single "INV" pill): exactly
    // one of HIT/MISS is "selected" (an outline, matching EuclidLaneBox's own `selected` convention) at a
    // time. There's no persisted "which side is primary" flag on EuclidLine itself — `euclideousInvertLine`
    // performs a destructive field SWAP, not a flag flip, so the swapped state alone can't say which side was
    // "originally" hit vs miss. Purely local/ephemeral, starting at HIT selected (not inverted) for all 4
    // lanes — tapping the NON-selected side triggers the actual invert and flips which one shows selected.
    @State private var missSelected: [Bool] = [false, false, false, false]
    // RATE POPUP (Paul 2026-10-06): "I hate the current [tap-to-cycle] control and want a pop-up" — replaces
    // cycling through all 18 ArpRate cases one tap at a time (and never offering a way back to nil/"inherit
    // the machine rate") with a single list the user picks from directly. nil = no popup open.
    @State private var ratePopupLane: Int? = nil
    // PER-LANE TABS (Paul 2026-10-07): which of PATTERN/RIFF/MASK each lane currently shows — purely local/
    // ephemeral, same convention as missSelected/touchedPad above (not persisted; a fresh page open always
    // starts every lane on PATTERN).
    @State private var laneTab: [EuclideousLaneTab] = [.pattern, .pattern, .pattern, .pattern]
    @State private var resetSpanPopupOpen = false
    @State private var keyPopupOpen = false
    @State private var chordsPopupOpen = false
    // RIFF DIRECTION POPUP (Paul 2026-10-09 ferry): the RIFF tab's direction chip opens a picker, mirroring
    // ratePopupLane's own "which lane's popup is open, nil = none" shape exactly.
    @State private var riffDirPopupLane: Int? = nil

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

    // --- TYPE SCALE (ferry §4): exactly three fixed sizes — heading/value/subtitle — identical in every
    // pad, lane, and orientation. NOTHING using these three sizes gets `.minimumScaleFactor` — the sizes
    // are chosen so the longest COMPACT string at each level fits the narrowest pad at the smallest
    // supported layout, worked by hand below (the one thing this environment cannot verify against real
    // on-device text metrics — flagged plainly, not silently assumed correct):
    //
    //   Worst-case CONTENT after compacting every pad's own strings (see the HUD formatters further down —
    //   "16 STP" not "16 STEPS", velocity as "200%" not a bare "200", RANDOM→"RND"/CYCLE→"CYC", etc.):
    //     heading:  "TILT/HITS" / "SHIFT/OCT"  → 9 characters
    //     value:    "16 HITS"                  → 7 characters
    //     subtitle: "OCT -3"                   → 6 characters
    //
    //   Narrowest SUPPORTED pad width: landscape at an assumed 768pt-wide panel (iPad mini's own portrait
    //   width, used here as a conservative floor — this environment has no access to AUM's actual enforced
    //   minimum window size, so this is a documented assumption, not a verified constant). Container = 768
    //   − 32 (page margins) = 736; lane grid = 64% of that ≈ 471; one of 2 columns, minus the 8pt inter-card
    //   gap, ≈ 231.5; one of 4 pads, minus 16pt card padding and 3×4pt inter-pad gaps, ≈ 50.9pt; minus 4pt
    //   text inset each side ≈ 42.9pt usable. A monospaced system font's advance width is ~0.6× its point
    //   size, so the ceiling at each level is usable/(chars×0.6): heading ≈7.9pt, value ≈10.2pt, subtitle
    //   ≈11.9pt. Picked comfortably under each ceiling, in a strict hierarchy (heading < subtitle < value,
    //   value being the pad's own "hero" number):
    private let padHeadingSize: CGFloat = 7
    private let padValueSize: CGFloat = 9
    private let padSubtitleSize: CGFloat = 8

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
                // RIFF DIRECTION POPUP (Paul 2026-10-09 ferry) — same scrim+card shape as the RATE popup above.
                if let lane = riffDirPopupLane {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { riffDirPopupLane = nil }
                        .zIndex(3)
                    riffDirPopupCard(lane).position(x: geo.size.width / 2, y: geo.size.height / 2).zIndex(4)
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
                        euclideousXYBubble(text, accent: accent)
                            .position(x: frame.midX, y: euclideousBubbleY(frame, pageHeight: geo.size.height))
                            .allowsHitTesting(false)
                            .zIndex(5)
                    }
                }
            }
            .coordinateSpace(name: "euclideousXY")
            .onPreferenceChange(EuclideousPadFramePreferenceKey.self) { padFrames = $0 }
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
    /// Flips below the pad when there isn't room above (ferry §3: "flips below when there's no room above").
    /// `pageHeight` isn't actually needed for the ABOVE case (a pad is never so close to the bottom that
    /// placing the bubble above it runs out of room there) — kept as an explicit parameter anyway, matching
    /// the "clamped inside the page" requirement, so a future vertical-clamp refinement has it in scope.
    private func euclideousBubbleY(_ frame: CGRect, pageHeight: CGFloat) -> CGFloat {
        let margin: CGFloat = 20
        let above = frame.minY - margin
        return above >= margin ? above : frame.maxY + margin
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

    // MARK: - ONE CONTAINER (ferry §2): "the plugin view's bounds minus 16pt on the left and right. Header,
    // lane grid and riff panel are all laid out inside it, and their left and right edges line up exactly
    // with its edges. Nothing is drawn outside the container. No horizontal scrolling." Applied on all four
    // sides for symmetry (top/bottom get the same sp16 — §2's own wording names left/right explicitly because
    // that's where the overflow bugs were, not because top/bottom should be bare).
    //
    /// The riff panel's total height at a given row height: top+bottom padding (sp8 each) + the header text
    /// row (~18pt) + a gap + the position-dot row (12pt) + a gap + 8 matrix rows with 7 gaps between them.
    private func riffPanelHeight(rowH: CGFloat) -> CGFloat {
        sp8 * 2 + 18 + sp4 + 12 + sp4 + rowH * 8 + sp4 * 7
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

    /// SIX EQUAL BOXES (Paul 2026-10-09, 4th ferry — SUPERSEDES the independent-riff-sizing design below
    /// entirely): "the plan is to have the app consisting of six equal sized boxes" — the 4 Euclid lanes, the
    /// riff grid, and ONE RESERVED/placeholder box (6th), all exactly the same size, filling the available
    /// space. PORTRAIT lays them out 2 columns × 3 rows (lanes fill rows 1–2, riff + placeholder share row
    /// 3) — the narrower, taller shape matching portrait's own aspect ratio. One `cellSize` drives every box
    /// on the page: whichever of the width- or height-derived candidate is smaller, so nothing overflows
    /// either axis and the whole grid genuinely uses all available space (no independent "riff gets 36%"-
    /// style carve-out anymore — riff is just another cell).
    private func portraitLayout(_ size: CGSize) -> some View {
        let headerH = portraitHeaderHeight
        let containerW = size.width - sp16 * 2
        let fixedVOverhead = sp16 * 3   // top margin + header↔grid gap + bottom margin
        let availableH = max(1, size.height - fixedVOverhead - headerH)
        let cellW = max(1, (containerW - sp8) / 2)
        let cellH = max(1, (availableH - sp8 * 2) / 3)
        let cellSize = min(cellW, cellH)
        let riffRowH = max(1, (cellSize - riffPanelHeight(rowH: 0)) / 8)
        return VStack(alignment: .leading, spacing: sp16) {
            portraitHeader().padding(.horizontal, sp16).padding(.top, sp16)
            VStack(spacing: sp8) {
                HStack(spacing: sp8) { laneCard(0, width: cellSize, height: cellSize); laneCard(1, width: cellSize, height: cellSize) }
                HStack(spacing: sp8) { laneCard(2, width: cellSize, height: cellSize); laneCard(3, width: cellSize, height: cellSize) }
                HStack(spacing: sp8) {
                    riffGridView(maxWidth: cellSize, rowH: riffRowH).frame(width: cellSize, height: cellSize)
                    euclideousPlaceholderBox(size: cellSize)
                }
            }
            .frame(width: containerW, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }

    /// LANDSCAPE (ferry 2026-10-09, 4th ferry): the SAME six-equal-boxes rule as portrait, transposed to
    /// landscape's wider-than-tall shape — 3 columns × 2 rows (lanes fill the first 2 columns, riff +
    /// placeholder share the 3rd column, one per row).
    private func landscapeLayout(_ size: CGSize) -> some View {
        let headerH = landscapeHeaderHeight
        let containerW = size.width - sp16 * 2
        let belowH = max(1, size.height - headerH - sp16 * 3)   // sp16 top + header↔grid gap + bottom margin
        let cellW = max(1, (containerW - sp8 * 2) / 3)
        let cellH = max(1, (belowH - sp8) / 2)
        let cellSize = min(cellW, cellH)
        let riffRowH = max(1, (cellSize - riffPanelHeight(rowH: 0)) / 8)
        return VStack(alignment: .leading, spacing: sp16) {
            landscapeHeader().padding(.horizontal, sp16).padding(.top, sp16)
            VStack(spacing: sp8) {
                HStack(spacing: sp8) {
                    laneCard(0, width: cellSize, height: cellSize)
                    laneCard(1, width: cellSize, height: cellSize)
                    riffGridView(maxWidth: cellSize, rowH: riffRowH).frame(width: cellSize, height: cellSize)
                }
                HStack(spacing: sp8) {
                    laneCard(2, width: cellSize, height: cellSize)
                    laneCard(3, width: cellSize, height: cellSize)
                    euclideousPlaceholderBox(size: cellSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }
    /// The 6th box (Paul 2026-10-09, 4th ferry: "have an empty space for now, or placeholder") — reserved
    /// for a not-yet-decided future feature. Deliberately inert (no tap target, no label) so it can't read
    /// as a broken control; the dashed border reuses this page's own existing "reserved/inactive" visual
    /// language (`laneOutRow`'s dashed chip for a routed-but-MAIN-OUT-gated bus) rather than inventing a new one.
    private func euclideousPlaceholderBox(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.02))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .frame(width: size, height: size)
    }

    // MARK: - Header (Paul 2026-10-09, ferry §5/§6: REBUILT as two genuinely different, FIXED-size layouts —
    // no more a single row that scales down to fit; §2 forbids horizontal scrolling as a safety net too, so
    // this has to genuinely fit at the assumed smallest supported width, not degrade toward it.
    //
    // PORTRAIT (§5) splits the content across two rows specifically because one row's worth of content (title
    // + RESET + KEY + CHORDS + MAIN OUT + ON + close) doesn't fit a narrow portrait container even at small
    // fixed sizes — confirmed by hand below. LANDSCAPE (§6) keeps everything in one row since a landscape
    // container is typically much wider. Both use FIXED font sizes (a light `.minimumScaleFactor` safety net
    // on text only — not the pads, which ferry §4 explicitly forbids any shrinking on) rather than a
    // width-driven scale factor, since §2's "no horizontal scrolling" removes the escape hatch a scale-down-
    // forever approach used to lean on.
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

    /// PORTRAIT row 1 (ferry §5): EUCLIDEOUS · RESET · MAIN OUT A B C D · ON · close.
    private func headerRow1() -> some View {
        HStack(spacing: sp4) {
            headerTitle()
            Spacer(minLength: sp4)
            headerResetChip()
            headerMainOutGroup()
            headerOnChip()
            headerCloseButton()
        }
    }
    /// PORTRAIT row 2 (ferry §5): KEY −/chip/+ · CHORDS.
    private func headerRow2() -> some View {
        HStack(spacing: sp4) {
            headerKeyGroup()
            Spacer(minLength: sp4)
            headerChordsChip()
        }
    }

    // Title trimmed 12→10pt and both chips below trimmed from sp8→sp4 horizontal padding (found while
    // numerically re-verifying portrait row 1's own content width, not reported directly): with every
    // element at its PREVIOUS size, row 1's content measures ~407pt — fits a 768pt-wide landscape-class
    // panel with room to spare, but overflows well before a genuinely narrow "windowed" portrait panel
    // (e.g. a 375pt-wide one, the narrowest width any iOS-family app plausibly renders at) — reproducing
    // exactly the "ON cut off, close missing" failure this very ferry opened with. Trimmed here (plus
    // dropping MAIN OUT's own caption below) to a verified ~342pt, fitting down to ~375pt wide with a thin
    // but real margin; the `.minimumScaleFactor` already on this row's text is the remaining safety net
    // for anything narrower, which this environment cannot verify against real device widths.
    private func headerTitle() -> some View {
        Text("EUCLIDEOUS").font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.85)
    }
    private func headerResetChip() -> some View {
        HStack(spacing: sp4) {
            Text("RESET").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            Text(euclideousResetSpanLabel(resetSpanBars))
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.horizontal, sp4).frame(height: headerBtnH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { resetSpanPopupOpen = true }
        }
    }
    private func headerKeyGroup() -> some View {
        HStack(spacing: sp4) {
            Text("KEY").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            keyStepButton("−")
            Text("\(noteNames[((keyRoot % 12) + 12) % 12]) \(keyType.label)")
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, sp8).frame(height: headerBtnH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.9)))
                .contentShape(Rectangle())
                .onTapGesture { keyPopupOpen = true }
            keyStepButton("+")
        }
    }
    // CHORDS (Paul 2026-10-08) — "next to [KEY] place a chords button that opens a pop-up to a chord grid
    // with rate control."
    private func headerChordsChip() -> some View {
        Text("CHORDS").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, sp8).frame(height: headerBtnH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture { chordsPopupOpen = true }
    }
    // The "MAIN OUT" text caption is DROPPED here (kept in the §5 spec's own wording as the group's
    // NAME, not a literal required on-screen label) — each circle already shows its own letter (A/B/C/D),
    // so the caption was informative but not load-bearing, and dropping it was the single largest
    // contributor to closing the portrait row-1 overflow risk documented above `headerTitle()`.
    private func headerMainOutGroup() -> some View {
        HStack(spacing: sp4) {
            ForEach(0..<4, id: \.self) { b in mainOutToggle(b) }
        }
    }
    private func headerOnChip() -> some View {
        Text(enabled ? "ON" : "OFF").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(enabled ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.85)
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
                            Text(r.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(on ? .black : .white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
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
        // GESTURE PADS (ferry §3: "the four pads in a lane are equal width, with 4pt gaps between them").
        let gesturePadW = max(1, (innerWidth - sp4 * 3) / 4)
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
                          stepCountBadge: AnyView(stepCountBadge(steps, mask: line.emitterMask ?? 0)))
            gesturePadRow(idx, line, accent, cellSize: gesturePadW, rowHeight: gestureRowH)
            laneTabRow(idx, line, accent, rowH: tabRowH)
            tabContent(idx, line, tab, accent, cellSize: padSize, rowH: contentLineH, fullWidth: innerWidth)
        }
        .padding(sp8)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
        // WHOLE-CARD SELECTION OUTLINE (ferry §1.4): replaces the narrower step-bar-only outline above.
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedLane == idx ? accent.opacity(0.85) : Color.clear, lineWidth: 2))
        .clipped()
    }

    /// PASSIVE STEP-COUNT NUMERAL (Paul 2026-10-07, §3: "step count shown as a number") + an ALWAYS-VISIBLE
    /// OUTPUT INDICATOR (Paul 2026-10-09, ferry §3.1: "the OUT row only appears on the I/O tab... add a small
    /// always-visible output indicator... showing which outputs the lane is routed to, or NO OUTPUT when
    /// none"). Both share `EuclidLaneBox`'s one optional `stepCountBadge` slot (nil everywhere else, so the
    /// regular BUILD-page EUCLID editor is unaffected) — stacked rather than adding a second slot, since the
    /// comet row has no more spare width to give a wholly separate widget.
    private func stepCountBadge(_ n: Int, mask: UInt8) -> some View {
        VStack(spacing: 1) {
            Text("\(n)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            Text(mask == 0 ? "NO OUT" : (0..<4).compactMap { (mask >> UInt8($0)) & 1 != 0 ? ["A", "B", "C", "D"][$0] : nil }.joined())
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(mask == 0 ? Color(red: 1, green: 0.71, blue: 0.33) : .white.opacity(0.55))
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(width: 36, height: 44)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
    }

    // MARK: - The 4 gesture pads (Paul 2026-10-09 ferry: "XY pad redesign" — dead-zone + axis-lock drag,
    // no heading, 2 centered value lines + a live Canvas "picture" + edge axis-name labels, a per-pad
    // floating value bubble replacing the old shared page-level HUD, double-tap-to-reset.)

    private let padAxisLabelColor = Color(hex: 0x8A909A)

    /// The 4 gesture PADS (RHYTHM · LENGTH · NOTE/GATE · RIFF, by their own axis pairing — labels now
    /// live on the pad's edges, not a heading) — `cellSize` wide, `rowHeight` tall, `sp4` gaps between
    /// them (unchanged). Each is its own independent `EuclideousXYPad` drag surface; PINCH stays on the
    /// comet bar, untouched by this redesign.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowHeight: CGFloat) -> some View {
        HStack(spacing: sp4) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
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
                    RoundedRectangle(cornerRadius: 6).fill(isRiffPad ? accent.opacity(0.22) : Color(hex: 0x22252C))
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
                .overlay(alignment: .bottom) {
                    HStack(spacing: 2) {
                        Text("◀").font(.system(size: padHeadingSize, weight: .heavy))
                        Text(names.x).font(.system(size: padHeadingSize, weight: .heavy, design: .monospaced))
                        Text("▶").font(.system(size: padHeadingSize, weight: .heavy))
                    }
                    .foregroundColor(padAxisLabelColor).lineLimit(1)
                    .padding(.bottom, 1)
                }
                .overlay(alignment: .leading) {
                    HStack(spacing: 2) {
                        Text("▲").font(.system(size: padHeadingSize, weight: .heavy))
                        Text(names.y).font(.system(size: padHeadingSize, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(padAxisLabelColor).lineLimit(1).fixedSize()
                    .rotationEffect(.degrees(-90))
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

    /// The two un-abbreviated value strings a pad shows (ferry §4) — Y above X, reused by both the
    /// permanent face (above) and the floating drag bubble (the body's own `activeXYBubbles`), so the
    /// two can never disagree about what a value currently reads.
    private func euclideousPadValues(_ line: EuclidLine, _ t: EuclideousGestureTab) -> EuclideousPadValues {
        switch t {
        case .tiltHits:
            let pct = Int((line.tiltResolved * 100).rounded())
            let hitWord = line.pulses == 1 ? "HIT" : "HITS"
            return EuclideousPadValues(yText: "\(line.pulses) \(hitWord)", xText: "TILT \(pct >= 0 ? "+" : "")\(pct)%")
        case .offsetCount:
            let n = max(2, min(16, line.steps))
            let r = ((line.rotate % n) + n) % n
            return EuclideousPadValues(yText: "\(line.steps) STEPS", xText: "OFFSET \(r)")
        case .gateVelocity:
            let gatePct = Int((line.gateResolved * 100).rounded())
            return EuclideousPadValues(yText: "VEL \(line.velocityAbsoluteResolved)", xText: "GATE \(gatePct)%")
        case .noteOctave:
            if line.useRiffResolved {
                let n = max(1, riff.stepsResolved)
                let shift = ((line.riffRotateResolved % n) + n) % n
                let oct = line.riffOctaveResolved
                return EuclideousPadValues(yText: "OCT \(oct >= 0 ? "+" : "")\(oct)", xText: "SHIFT \(shift)")
            }
            let oct = line.octaveResolved
            return EuclideousPadValues(yText: "OCT \(oct >= 0 ? "+" : "")\(oct)", xText: "NOTE \(line.noteSelResolved.rawValue)")
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
    /// RHYTHM: a row of hit/rest cells reflecting the lane's ACTUAL pattern — reuses the exact same pure
    /// functions, in the same order, `Router.runEuclidLine` itself calls (`euclidPatternInto` then
    /// `euclidTiltPattern`), so this can never silently disagree with what's struck. No direction
    /// handling, matching `EuclidCometBar`'s own established precedent (direction only affects the
    /// animated comet's sweep, never the static pattern's own screen layout).
    private func euclideousRhythmPicture(_ line: EuclidLine, accent: Color) -> some View {
        let n = max(2, min(16, line.steps))
        let k = max(0, min(n, line.pulses))
        var buf = [Bool](repeating: false, count: n)
        euclidPatternInto(&buf, pulses: k, steps: n, rotation: line.rotate)
        if line.tiltResolved != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: line.tiltResolved) }
        return Canvas { ctx, size in
            let gap: CGFloat = 1.5
            let cellW = max(1, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            for i in 0..<n {
                let rect = CGRect(x: CGFloat(i) * (cellW + gap), y: 0, width: cellW, height: size.height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(buf[i] ? accent : Color(white: 0.22)))
            }
        }
    }
    /// LENGTH: `steps` dots arranged clockwise around a circle (12 o'clock = step 0), the dot at the
    /// wrapped OFFSET index enlarged + lane-coloured — the SAME wrap `euclideousPadValues`'s own OFFSET
    /// readout uses, so the picture and the value line can never disagree about which dot is current.
    private func euclideousLengthPicture(_ line: EuclidLine, accent: Color) -> some View {
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        return Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let radius = min(size.width, size.height) / 2 - 3
            for i in 0..<n {
                let angle = -Double.pi / 2 + 2 * .pi * Double(i) / Double(n)
                let x = cx + CGFloat(cos(angle)) * radius
                let y = cy + CGFloat(sin(angle)) * radius
                let on = i == r
                let dotR: CGFloat = on ? 3.5 : (i == 0 ? 2.2 : 1.6)
                let color: Color = on ? accent : (i == 0 ? Color(white: 0.66) : Color(white: 0.3))
                ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(color))
            }
        }
    }
    /// NOTE/GATE: a dashed max-extent box with a lane-colour rect sized by GATE (width) × VEL (height) —
    /// the two things this pad actually controls, shown as one simple bar.
    private func euclideousNoteGatePicture(_ line: EuclidLine, accent: Color) -> some View {
        let gateFrac = max(0.05, min(1, line.gateResolved))
        let velFrac = Double(line.velocityAbsoluteResolved) / 127.0
        return Canvas { ctx, size in
            ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 2),
                       with: .color(Color(white: 0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            let w = size.width * CGFloat(gateFrac)
            let h = size.height * CGFloat(velFrac)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: size.height - h, width: w, height: h), cornerRadius: 1.5), with: .color(accent))
        }
    }
    /// RIFF: an 8×7 SHIFT(columns)/OCT(rows, +3 at top...-3 at bottom) grid, the cell at (wrapped SHIFT,
    /// current OCT) lane-coloured.
    private func euclideousRiffPicture(_ line: EuclidLine, accent: Color) -> some View {
        let n = max(1, riff.stepsResolved)
        let shiftCols = min(8, n)
        let shift = ((line.riffRotateResolved % n) + n) % n
        let oct = line.riffOctaveResolved
        return Canvas { ctx, size in
            let gap: CGFloat = 1
            let cellW = max(1, (size.width - gap * CGFloat(shiftCols - 1)) / CGFloat(shiftCols))
            let cellH = max(1, (size.height - gap * 6) / 7)
            for row in 0..<7 {
                let rowOct = 3 - row   // row 0 = +3 at the top
                for col in 0..<shiftCols {
                    let isCurrent = col == (shift % shiftCols) && rowOct == oct
                    let rect = CGRect(x: CGFloat(col) * (cellW + gap), y: CGFloat(row) * (cellH + gap), width: cellW, height: cellH)
                    let color: Color = isCurrent ? accent : (rowOct == 0 ? Color(white: 0.26) : Color(white: 0.18))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
            }
        }
    }
    /// NOTE/OCT (riff off): a single OCT column, the SAME 7-row geometry the RIFF picture's own rows
    /// use, current OCT marked lane-coloured.
    private func euclideousNoteOctPicture(_ line: EuclidLine, accent: Color) -> some View {
        let oct = line.octaveResolved
        return Canvas { ctx, size in
            let gap: CGFloat = 1
            let cellH = max(1, (size.height - gap * 6) / 7)
            for row in 0..<7 {
                let rowOct = 3 - row
                let rect = CGRect(x: 0, y: CGFloat(row) * (cellH + gap), width: size.width, height: cellH)
                let color: Color = rowOct == oct ? accent : (rowOct == 0 ? Color(white: 0.26) : Color(white: 0.18))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
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
                let n = max(1, riff.stepsResolved)
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
            // TILT — a center DETENT: the first 8pt of travel from touch-down (either direction) holds
            // at 0% — this 8pt IS the axis-lock dead zone itself (fed RAW, not rebased), so the two
            // combine into exactly one threshold rather than stacking into two.
            let signed = Double(travel)
            let adjusted = signed >= 0 ? max(0, signed - 8) : min(0, signed + 8)
            line.tilt = max(-1, min(1, adjusted / 100))
        case (.tiltHits, .y):
            let steps = max(2, min(16, line.steps))
            line.pulses = max(0, min(steps, Int(baseline) + Int((travel / 12).rounded())))
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
                let n = max(1, riff.stepsResolved)
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
            let steps = max(2, min(16, line.steps))
            line.pulses = max(0, min(steps, line.pulses + d))
        case (.offsetCount, .x):
            let n = max(2, min(16, line.steps))
            line.rotate = ((line.rotate - d) % n + n) % n
        case (.offsetCount, .y):
            let v = max(2, min(16, line.steps + d)); line.steps = v; if line.pulses > v { line.pulses = v }
        case (.gateVelocity, .x): line.gate = max(0.05, min(1, line.gateResolved + Double(d) / 100))
        case (.gateVelocity, .y): line.velocityAbsolute = max(1, min(127, line.velocityAbsoluteResolved + d))
        case (.noteOctave, .x):
            if line.useRiffResolved {
                let n = max(1, riff.stepsResolved)
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
                // DOT (Paul 2026-10-07, §3; narrowed 2026-10-09, ferry §3.2): ONLY RIFF/MASK carry a dot,
                // lane-coloured when the feature is on for the lane — they're the two tabs that genuinely
                // SWITCH ON AND OFF. PATTERN never shows one (it's always "on"). I/O never shows one either —
                // a lane always has SOME source selected, there's no on/off state to flag (the dot that used
                // to render here was always unlit — a hollow dot with nothing to say — removed entirely,
                // not just left dim). MASK's "on" reads as "this lane has a mask configured at all"
                // (line.mask != nil), the literal translation of the ratified mockup's own `!!d.mask` check —
                // there's no further "effect enabled" concept yet since the mask's effect itself is deferred
                // (§4.1).
                let dotOn: Bool = t == .riff ? line.useRiffResolved : (t == .mask ? (line.mask != nil) : false)
                HStack(spacing: 5) {
                    Text(t.label).font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? .white.opacity(0.95) : .white.opacity(0.45))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if t == .riff || t == .mask {
                        Circle().fill(dotOn ? accent : Color.clear)
                            .overlay(Circle().stroke(dotOn ? accent : Color.white.opacity(0.35), lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: rowH)
                .overlay(Rectangle().fill(sel ? accent : Color.white.opacity(0.12)).frame(height: 3), alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { if idx < laneTab.count { laneTab[idx] = t } }
            }
        }
    }

    @ViewBuilder private func tabContent(_ idx: Int, _ line: EuclidLine, _ tab: EuclideousLaneTab, _ accent: Color, cellSize: CGFloat, rowH: CGFloat, fullWidth: CGFloat) -> some View {
        switch tab {
        case .io:
            VStack(spacing: sp4) {
                ioSourceRow(idx, line, accent, rowH: rowH)
                laneOutRow(idx, line, accent: accent).frame(height: rowH)
            }
        case .pattern:
            VStack(spacing: sp4) {
                directionRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
                hitMissRateRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
            }
        case .riff:
            riffDirGrid(idx, line, accent, rowH: rowH)
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
    private func directionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let order: [(EuclidDir, String)] = [(.bkw, "<"), (.pingpong, "><"), (.fwd, ">")]
        return HStack(spacing: sp4) {
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6))
                    .frame(width: cellSize, height: rowH)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.55) : Color.white.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.direction = dir } }
            }
        }
    }

    /// HIT | MISS, separated from RATE (Paul 2026-10-09, ferry §3.3: "FOLLOW sits in the same strip as HIT/
    /// MISS with no label, so it reads as a third option of that choice — give it its RATE label back and
    /// separate it visibly"). HIT/MISS is a symmetric 2-way selector (see `missSelected`'s own doc comment) —
    /// tapping the NON-selected side performs the actual invert (`euclideousInvertLine`) and flips which one
    /// shows "selected"; tapping the already-selected side is a no-op. RATE now sits in its OWN small group
    /// (a visible 4pt gap + its own rounded background, not sharing HIT/MISS's clip shape) with a genuine
    /// "RATE" caption above the value — opens the pop-up (`ratePopupLane`) on tap; the value shows FOLLOW
    /// (Paul 2026-10-07, §3 — was "—") when the line's rate is genuinely unset (nil ⇒ inherit the machine-wide
    /// rate) rather than silently defaulting the display to 1/16.
    private func hitMissRateRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let missOn = idx < missSelected.count && missSelected[idx]
        // THREE EQUAL SEGMENTS (ferry §3: "the four pads... equal width, with 4pt gaps" extended consistently
        // to every segmented-button row on the page) — HIT/MISS/RATE each get the SAME `cellSize` directionRow
        // above uses (already sized for 3 columns + 2 sp4 gaps across the card's own inner width), with sp4
        // between all three, not just between the pair and RATE.
        func sideButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
                .frame(width: cellSize, height: rowH)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? accent.opacity(0.85) : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        return HStack(spacing: sp4) {
            sideButton("HIT", selected: !missOn) {
                guard missOn else { return }   // already selected — a no-op, not a second invert
                edit(idx) { $0 = euclideousInvertLine($0) }
                if idx < missSelected.count { missSelected[idx] = false }
            }
            sideButton("MISS", selected: missOn) {
                guard !missOn else { return }
                edit(idx) { $0 = euclideousInvertLine($0) }
                if idx < missSelected.count { missSelected[idx] = true }
            }
            VStack(spacing: 1) {
                Text("RATE").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Text(line.rate == nil ? "FOLLOW" : line.rate!.rawValue)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: cellSize, height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { ratePopupLane = idx }
        }
    }

    /// RIFF tab (Paul 2026-10-09 ferry, "three new per-lane riff options" — SUPERSEDES the 2026-10-07 7-button
    /// OFF+6-direction grid above entirely, not alongside it). Line 1: OFF · a direction CHIP (opens
    /// `riffDirPopupCard`, shows the current choice) · a FREE/LOCK toggle. Line 2: an INVERT toggle · an ON
    /// REST chip (tap cycles SKIP→FILL→TIE). Same spacing/type rules as the rest of the page (sp4 gaps, the
    /// shared 10pt row-button text size directionRow/hitMissRateRow/ioSourceRow already use — not a new size),
    /// and the SAME equal-flex-width per-button convention those rows already establish.
    private func riffDirGrid(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        VStack(spacing: sp4) {
            HStack(spacing: sp4) {
                riffTabButton("OFF", on: !line.useRiffResolved, accent: accent, rowH: rowH) {
                    edit(idx) { $0.useRiff = false }
                }
                riffTabButton(riffDirShortLabel(line.riffDirResolved), on: line.useRiffResolved, accent: accent, rowH: rowH) {
                    riffDirPopupLane = idx
                }
                riffTabButton(line.riffLockResolved ? "LOCK" : "FREE", on: line.riffLockResolved, accent: accent, rowH: rowH) {
                    edit(idx) { $0.riffLock = !($0.riffLockResolved) }
                }
            }
            HStack(spacing: sp4) {
                riffTabButton("INVERT", on: line.riffInvertResolved, accent: accent, rowH: rowH) {
                    edit(idx) { $0.riffInvert = !($0.riffInvertResolved) }
                }
                riffTabButton("REST:\(line.riffOnRestResolved.rawValue)", on: line.riffOnRestResolved != .skip, accent: accent, rowH: rowH) {
                    edit(idx) { $0.riffOnRest = euclideousNextOnRest($0.riffOnRestResolved) }
                }
            }
        }
    }
    /// Shared button face for the RIFF tab's own 5 controls — one visual language (filled when "on," the
    /// lane's own accent colour), matching the equal-flex-width convention directionRow/hitMissRateRow/
    /// ioSourceRow already use elsewhere on this page.
    private func riffTabButton(_ label: String, on: Bool, accent: Color, rowH: CGFloat, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity).frame(height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.7) : Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
    /// Short direction labels (PEND/PING/RAND) — scoped to THIS page only, never touching the shared
    /// `RiffDir.displayLabel` enum (that enum also serves the unrelated, regular chainable RIFF processor
    /// elsewhere in the app). Shared by the tab's own direction chip and the popup picker below.
    private func riffDirShortLabel(_ d: RiffDir) -> String {
        switch d {
        case .forward: return "FWD"; case .reverse: return "REV"; case .pendulum: return "PEND"
        case .pingpong: return "PING"; case .random: return "RAND"; case .drunk: return "DRUNK"
        }
    }
    /// ON REST's tap-to-cycle order (Paul 2026-10-09 ferry §4: "tap cycles SKIP → FILL → TIE").
    private func euclideousNextOnRest(_ r: EuclidRiffOnRest) -> EuclidRiffOnRest {
        switch r { case .skip: return .fill; case .fill: return .tie; case .tie: return .skip }
    }
    /// The RIFF direction picker (Paul 2026-10-09 ferry §4) — same scrim+centred-card shape as `ratePopupCard`
    /// above, a 2-column grid of the 6 `RiffDir` cases. Selecting one both sets the direction AND turns this
    /// lane's riff ON (there's no separate "ON" control once OFF moved to its own button on line 1 — picking
    /// a direction is how a lane re-engages riff, mirroring the OLD unified 7-button grid's own tap behaviour
    /// for its 6 direction buttons).
    private func riffDirPopupCard(_ idx: Int) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
        let accent = laneAccents[idx % laneAccents.count]
        let pairs = stride(from: 0, to: RiffDir.allCases.count, by: 2).map { Array(RiffDir.allCases[$0..<min($0 + 2, RiffDir.allCases.count)]) }
        return VStack(spacing: 10) {
            Text("LANE \(idx + 1) RIFF DIRECTION").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            ForEach(pairs.indices, id: \.self) { g in
                HStack(spacing: 6) {
                    ForEach(pairs[g], id: \.self) { d in
                        let on = line.useRiffResolved && line.riffDirResolved == d
                        Text(riffDirShortLabel(d)).font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent : Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                            .onTapGesture { edit(idx) { $0.useRiff = true; $0.riffDir = d }; riffDirPopupLane = nil }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
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
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.3)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity).frame(height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // MARK: - The I/O tab (Paul 2026-10-08): per-lane MIDI IN | KEY | CHORDS + the lane's own OUT toggles

    /// MIDI IN | KEY | CHORDS (Paul 2026-10-08) — replaces the old page-level GLOBAL "LANES KEY|MIDI" switch:
    /// each lane now picks its own source independently (`EuclidLine.sourceMode`). CHORDS reads Euclideous's
    /// own on-page chord generator (the CHORDS button beside KEY in the header), resolved entirely in the
    /// engine. Same 3-equal-width-button visual language as `directionRow`.
    ///
    /// ALWAYS LIVE, INCLUDING WHILE RIFF IS ON (Paul 2026-10-09, ferry §2.4): a 2026-10-09 investigation
    /// ("I choose MIDI IN and it plays something else — a chord grid maybe?") found that turning a lane's
    /// RIFF on made ITS OWN choice here completely inert — the shared riff pattern used to read lane 1's pool
    /// exclusively, regardless of which lane was walking it (fixed that day with a banner explaining the
    /// override, since removed). Paul's follow-up ferry ruling reversed the OTHER side of that: the riff pool
    /// itself is no longer lane-1-exclusive — each lane now resolves the shared riff SHAPE against ITS OWN
    /// pool (Router.swift's `runEuclidLine`, the `if useRiff {...}` branch now reads `laneNotes(lineIndex)`/
    /// `laneCount(lineIndex)` directly) — so these 3 buttons are genuinely live again regardless of RIFF
    /// state, and the banner that briefly replaced them is gone.
    private func ioSourceRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        HStack(spacing: sp4) {
            ForEach([EuclideousLaneSource.midi, .key, .chords], id: \.self) { src in
                let on = line.sourceModeResolved == src
                let label = src == .midi ? "MIDI IN" : (src == .key ? "KEY" : "CHORDS")
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.55) : Color.white.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.sourceMode = src } }
            }
        }
    }

    // MARK: - OUT row (Paul 2026-10-07, §2.8/§3: smaller toggles, NO OUTPUT, dashed/hollow main-held chips)

    /// `laneControls` from the pre-rework page collapses to just this one row — the two `EuclidBeacon` calls
    /// that used to sit above it are REMOVED entirely (§2.8: "remove the hit/miss beacons"). Fixed at 30pt
    /// (ferry §3: "do not make lane OUT... any smaller than they are now") regardless of any outer scale.
    /// MOVED (Paul 2026-10-08) into the lane's own new I/O tab, row 2 — no longer always-visible below every
    /// tab; switching to PATTERN/RIFF/MASK hides it, by design ("a new tab for input/output... the four
    /// emitter toggles on the second row").
    @ViewBuilder private func laneOutRow(_ idx: Int, _ line: EuclidLine, accent: Color) -> some View {
        let mask = line.emitterMask ?? 0
        HStack(spacing: sp4) {
            Text("OUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            ForEach(0..<4, id: \.self) { b in
                let routed = (mask >> UInt8(b)) & 1 != 0
                let mainOn = (mainOutMask >> UInt8(b)) & 1 != 0
                // TWO SEPARATE CONDITIONS (spec audit item 3, not one "something's wrong" treatment): a bit
                // that's SET but whose MAIN toggle is off draws dashed/hollow (still shows routing intent);
                // "no output at all" is handled separately below via the trailing NO OUTPUT label.
                ZStack {
                    if routed && mainOn {
                        Circle().fill(accent)
                    } else if routed {
                        Circle().fill(Color.clear).overlay(Circle().stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
                    } else {
                        Circle().fill(Color.white.opacity(0.08))
                    }
                    Text(["A", "B", "C", "D"][b]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(routed && mainOn ? .black : (routed ? accent : .white.opacity(0.5)))
                }
                .frame(width: laneOutSize, height: laneOutSize)
                .contentShape(Circle())
                .onTapGesture { edit(idx) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
            }
            Spacer(minLength: 4)
            if mask == 0 {
                Text("NO OUTPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(Color(red: 1, green: 0.71, blue: 0.33))
                    .lineLimit(1).minimumScaleFactor(0.6)
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
    /// SIZED FROM THE CALLER'S OWN `maxWidth`/`rowH` DIRECTLY — since the 2026-10-09 "six equal boxes" rebuild,
    /// BOTH orientations pass the same `cellSize` for `maxWidth` and a `rowH` solved to make the panel's total
    /// height exactly `cellSize` too (`riffPanelHeight`'s own inverse) — the riff grid is just another box in
    /// the shared grid now, not an independently-proportioned panel with its own width/height rule.
    ///
    /// Per-lane position dots sit above the columns (ferry §2.3, carried over twice now as "still missing" —
    /// the drawing code itself is unchanged and, read in isolation, looks correct: it reads `riffPositions[i]`
    /// (Router→Kernel→AU→VC, polled on the fast ~30fps timer) against this column index for every useRiff-on
    /// lane. Bumped once more for visibility (8pt dot, small lane-coloured background track) in case the
    /// previous round's dots were simply too subtle to notice rather than genuinely absent — but this is
    /// honestly still unverified without a device, and if they're STILL invisible after this, the live
    /// `riffPositions` data itself (not this drawing code, read three times now) is the next thing to trace,
    /// ideally with an on-device or simulator capture this environment cannot produce.
    private func riffGridView(maxWidth: CGFloat, rowH: CGFloat) -> some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        let cellW = max(1, (maxWidth - sp8 * 2 - sp4 * CGFloat(n - 1)) / CGFloat(n))
        let cellH = max(1, rowH)
        let dotRowH: CGFloat = 12
        return VStack(alignment: .leading, spacing: sp4) {
            HStack(spacing: sp8) {
                Text("RIFF").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                // PER-LANE SOURCE (ferry §2.4): the riff's own "SOURCE KEY|MIDI" switch stays removed — each
                // lane resolves this SHARED shape against ITS OWN I/O-tab choice (Router.swift's
                // `laneNotes(lineIndex)`), not lane 1's — two lanes walking the same shape with different
                // inputs genuinely play different notes.
                Text("8 STEPS · SHARED SHAPE, EACH LANE PLAYS ITS OWN SOURCE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: sp8)
            }
            HStack(spacing: sp4) {
                ForEach(0..<n, id: \.self) { col in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.04))
                        ForEach(0..<4, id: \.self) { i in
                            if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] == col {
                                Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .frame(width: cellW, height: dotRowH)
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
