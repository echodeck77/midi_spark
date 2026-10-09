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
enum EuclideousGestureTab: Int, CaseIterable { case tiltHits = 0, offsetCount = 1, gateVelocity = 2, noteOctave = 3
    var label: String { switch self { case .tiltHits: "TILT/HITS"; case .offsetCount: "OFFS/CNT"; case .gateVelocity: "GATE/VEL"; case .noteOctave: "NOTE/OCT" } }
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
            }
        }
    }

    // MARK: - ONE CONTAINER (ferry §2): "the plugin view's bounds minus 16pt on the left and right. Header,
    // lane grid and riff panel are all laid out inside it, and their left and right edges line up exactly
    // with its edges. Nothing is drawn outside the container. No horizontal scrolling." Applied on all four
    // sides for symmetry (top/bottom get the same sp16 — §2's own wording names left/right explicitly because
    // that's where the overflow bugs were, not because top/bottom should be bare).
    //
    // The riff panel's own fixed per-tab-row height (ferry §5: "rows about 30pt tall") — ONE named constant,
    // read by BOTH the layout functions below (which reserve space for it) and `riffGridView` itself (which
    // draws it), so the two can never silently disagree about how tall the panel actually is (the RATCHET/
    // DEST class of bug this codebase's own history keeps flagging).
    private let riffRowHeight: CGFloat = 30
    /// The riff panel's total height at a given row height: top+bottom padding (sp8 each) + the header text
    /// row (~18pt) + a gap + the position-dot row (12pt) + a gap + 8 matrix rows with 7 gaps between them.
    private func riffPanelHeight(rowH: CGFloat) -> CGFloat {
        sp8 * 2 + 18 + sp4 + 12 + sp4 + rowH * 8 + sp4 * 7
    }

    // --- LANE CARD'S OWN FIXED-HEIGHT ROWS — hoisted to struct level (not re-declared inside `laneCard`) so
    // `portraitLayout` can share the EXACT same numbers when deciding how much height a card needs, rather
    // than guessing a second time (the RATCHET/DEST class of bug this file's own history keeps flagging). ---
    private let cometRowH: CGFloat = 56
    private let tabRowH: CGFloat = 30
    private let contentLineH: CGFloat = 36
    /// A tab's 2-row content is `36 + sp4 + 36` (each tab's own inner VStack uses `spacing: sp4` between its
    /// 2 rows, confirmed by reading all four: `ioSourceRow`+`laneOutRow`, `directionRow`+`hitMissRateRow`,
    /// `riffDirGrid`'s 2 groups of 4, `maskCometRow`+`maskStubRow`) — not a bare `36×2`.
    private var tabContentH: CGFloat { contentLineH * 2 + sp4 }
    /// Every FIXED-height row in a lane card, summed — comet row + tab row + tab content + the card's own sp8
    /// padding (top+bottom) + the sp4 gaps between the VStack's 4 children. This is "how tall a card needs to
    /// be with ZERO room left for its own gesture pads" — i.e. not yet a usable minimum on its own.
    private var laneCardFixedOverhead: CGFloat { cometRowH + tabRowH + tabContentH + sp8 * 2 + sp4 * 3 }
    /// A sane functional floor for the gesture-pad row itself (HIG's own touch-target minimum is 44pt; 36 is
    /// a deliberately smaller "still usable, genuinely tight" floor, not the comfortable target) — added to
    /// the fixed overhead above to get a card's real functional minimum height. Read by `portraitLayout` to
    /// decide how far the riff panel must flex DOWN (below its own `riffRowHeight` target) before it may
    /// starve a lane card of this minimum (ferry §1.1's "fit always wins" still governs when the two
    /// genuinely conflict on a short enough screen — see `portraitLayout`'s own doc comment).
    private var laneCardMinHeight: CGFloat { laneCardFixedOverhead + 36 }

    /// PORTRAIT (ferry §5): 2-row header; a 2×2 lane grid that FILLS the container width (two equal columns,
    /// sp8 gap — no longer capped by height, so lane cards are NOT forced square here, a deliberate, explicit
    /// departure from the landscape/original "square boxes" rule for this one orientation, per §5's own
    /// wording); the riff panel spans the full container width below the lanes, aiming for `riffRowHeight`-
    /// tall rows; any height left over after that goes to the lane cards (taller, not wider).
    ///
    /// RIFF FLEXES BELOW ITS OWN TARGET ON A SHORT SCREEN (found while verifying this rebuild's own numbers
    /// by hand, not reported directly): a fixed 30pt-row riff panel plus a 2-row header leaves too little
    /// remaining height for 2 STACKED lane cards to even fit their own fixed-height rows (comet bar + tab row
    /// + tab content, ~188pt, BEFORE the gesture pads get any room at all) once the total screen height drops
    /// much below ~950pt — a real possibility on a genuinely small "windowed" AUM panel, not just a
    /// theoretical edge case. Ferry §1.1's "nothing may extend past the plugin view" and §8's "nothing
    /// clipped" are unconditional; §5's "rows about 30pt tall" is a TARGET that must yield when the two
    /// conflict, the same "fit always wins over protected sizing" principle an earlier ferry already
    /// established. So: compute the riff row height that would leave both lane-card rows at their own
    /// functional minimum (`laneCardMinHeight`), and use the SMALLER of that or the 30pt target — riff only
    /// ever shrinks below 30, never grows past it.
    private func portraitLayout(_ size: CGSize) -> some View {
        let headerH = portraitHeaderHeight
        let containerW = size.width - sp16 * 2
        let cardWidth = max(1, (containerW - sp8) / 2)
        // Fixed vertical overhead: sp16 top + sp16 bottom (the container's own margin) + 2× sp16 (the gaps
        // between header↔lanes and lanes↔riff) — everything else is header/lane-grid/riff content itself.
        let fixedVOverhead = sp16 * 2 + sp16 * 2
        let heightForLanesAndRiff = max(1, size.height - fixedVOverhead - headerH)
        let riffHAtMinLanes = max(1, heightForLanesAndRiff - (laneCardMinHeight * 2 + sp8))
        let riffRowHActual = max(1, min(riffRowHeight, (riffHAtMinLanes - riffPanelHeight(rowH: 0)) / 8))
        let riffH = riffPanelHeight(rowH: riffRowHActual)
        let availableForLanes = max(1, heightForLanesAndRiff - riffH)
        let cardHeight = max(1, (availableForLanes - sp8) / 2)
        return VStack(alignment: .leading, spacing: sp16) {
            portraitHeader().padding(.horizontal, sp16).padding(.top, sp16)
            laneGridView(cardWidth: cardWidth, cardHeight: cardHeight)
                .frame(width: containerW, alignment: .leading).padding(.horizontal, sp16)
            riffGridView(maxWidth: containerW, rowH: riffRowHActual)
                .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
    }

    /// LANDSCAPE (ferry §6): one-row header; the lane grid (square cards, left) and the riff panel (right)
    /// SIDE BY SIDE, both exactly `belowH` tall so "their tops and bottoms line up" holds by construction —
    /// riff's height is passed directly, never independently derived. Riff's WIDTH is a direct ~36% of the
    /// container (not "whatever's left after the lane grid" — that leftover approach was the exact bug a
    /// prior pass shipped and then had to fix: on a height-bound panel the lane grid never uses its own full
    /// width share, so there was nothing to "win back" for riff, and it stayed as wide as before). Lane cards
    /// stay square, sized by whichever of the 64%-width share or the available height is smaller — reliably
    /// close to the target ratio on a typical landscape aspect ratio, confirmed by hand against several sizes
    /// before shipping (see the ferry-response notes) — though on a very tall/short panel the riff CELLS can
    /// end up noticeably non-square (8 rows filling the full shared height vs. 8 columns filling a narrower,
    /// independently-set width) — accepted per §6's own "square OR CLOSE TO square," not solvable alongside
    /// "same height" and "~36% width" simultaneously for every aspect ratio at once.
    private func landscapeLayout(_ size: CGSize) -> some View {
        let headerH = landscapeHeaderHeight
        let containerW = size.width - sp16 * 2
        let belowH = max(1, size.height - headerH - sp16 * 3)   // sp16 top + header↔below gap + bottom margin
        let riffW = max(1, containerW * 0.36 - sp16 / 2)
        let laneGridTargetW = max(1, containerW - riffW - sp16)
        let cardTargetW = max(1, (laneGridTargetW - sp8) / 2)
        let cardHeightDerived = max(1, (belowH - sp8) / 2)
        let cardSize = min(cardTargetW, cardHeightDerived)
        return VStack(alignment: .leading, spacing: sp16) {
            landscapeHeader().padding(.horizontal, sp16).padding(.top, sp16)
            HStack(alignment: .top, spacing: sp16) {
                laneGridView(cardWidth: cardSize, cardHeight: cardSize)
                riffGridView(maxWidth: riffW, rowH: max(1, (belowH - riffPanelHeight(rowH: 0)) / 8))
                    .frame(height: belowH)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp16).padding(.bottom, sp16)
        }
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

    // MARK: - Lane grid (Paul 2026-10-09, ferry §3/§5/§6: EVERY row inside a card spans the SAME inner width
    // — the card's own width minus sp8 padding each side — and the card's width/height are now INDEPENDENT
    // parameters, not one shared "size." Landscape keeps lane cards SQUARE (width == height, unchanged from
    // the original 2026-10-07 rule); portrait does NOT — §5 explicitly has the lane grid fill the container
    // width and gives any leftover height to the lane cards, so a portrait card can be taller than it is wide.)
    private func laneGridView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        VStack(spacing: sp8) {
            HStack(spacing: sp8) { laneCard(0, width: cardWidth, height: cardHeight); laneCard(1, width: cardWidth, height: cardHeight) }
            HStack(spacing: sp8) { laneCard(2, width: cardWidth, height: cardHeight); laneCard(3, width: cardWidth, height: cardHeight) }
        }
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
        let rotateStepPt = euclidBoxGeometry(n: steps, usableWidth: max(1, innerWidth - 64)).pitch
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
            gesturePadRow(idx, line, accent, cellSize: gesturePadW, rowHeight: gestureRowH, rotateStepPt: rotateStepPt)
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

    // MARK: - The 4 gesture pads (Paul 2026-10-06, faces now show their value permanently — 2026-10-07 §3)

    /// The 4 gesture PADS (TILT/HITS · OFFS/CNT · GATE/VEL · NOTE/OCT) — `cellSize` wide, `rowHeight` tall,
    /// with `sp4` gaps between them (ferry §3: "the four pads in a lane are equal width, with 4pt gaps
    /// between them" — were touching before). Each is its OWN independent 1-/2-finger drag surface (via a
    /// dedicated `EuclidGesturePad` instance per button) wired directly to that button's own X/Y mapping.
    /// PINCH (`onStepsDelta`) is a no-op here — that gesture stays on the comet bar itself.
    ///
    /// TYPE (ferry §4): heading/value/subtitle all use the SAME three fixed sizes in every pad, lane and
    /// orientation — `padHeadingSize`/`padValueSize`/`padSubtitleSize` — with NO `.minimumScaleFactor`
    /// anywhere here. The pad-face strings themselves (`euclideousPadInfo` and the HUD formatters below) are
    /// written in COMPACT forms sized to fit the narrowest supported pad at these fixed sizes, not shrunk.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowHeight: CGFloat, rotateStepPt: CGFloat) -> some View {
        HStack(spacing: sp4) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
                let touched = touchedPad[idx] == t.rawValue
                // RIFF ADVANCE (Paul 2026-10-06): once a lane's useRiff is on, this ONE pad's label/tint
                // change to reflect the new role and its DRAG retargets to riffRotate/riffOctave instead of
                // noteSel/octave. Heading compacted to "SHIFT/OCT" (was "RIFF SHIFT/OCT") — 9 characters,
                // matching the other 3 pads' own heading length budget (ferry §4's fixed heading size is
                // sized against a 9-character ceiling).
                let isRiffPad = t == .noteOctave && line.useRiffResolved
                let info = euclideousPadInfo(idx, line, t)
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(touched ? accent.opacity(0.4) : (isRiffPad ? accent.opacity(0.22) : Color.white.opacity(0.06)))
                    VStack(spacing: sp4) {
                        Text(isRiffPad ? "SHIFT/OCT" : t.label)
                            .font(.system(size: padHeadingSize, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black.opacity(0.75) : .white.opacity(0.5))
                            .lineLimit(1)
                        Text(info.primary)
                            .font(.system(size: padValueSize, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black : .white.opacity(0.92))
                            .lineLimit(1)
                        if !info.secondary.isEmpty {
                            Text(info.secondary)
                                .font(.system(size: padSubtitleSize, weight: .semibold, design: .monospaced))
                                .foregroundColor(touched ? .black.opacity(0.7) : .white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(sp4)
                }
                .frame(width: cellSize, height: rowHeight)
                .contentShape(Rectangle())
                .overlay(
                    EuclidGesturePad(
                        onRotateDelta: { d in euclideousApplyX(idx, t, d) },
                        onHitsDelta: { d in euclideousApplyY(idx, t, d) },
                        onStepsDelta: { _ in },                              // "except the pinch" — a deliberate no-op on these pads
                        onAllRotateDelta: { d in euclideousApplyAllX(t, d) },
                        onAllHitsDelta: { d in euclideousApplyAllY(t, d) },
                        onDragState: { point, allRows in
                            touchedPad[idx] = point == nil ? nil : t.rawValue
                            guard let point else { dragHUDInfo = nil; return }
                            let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)
                            switch t {
                            case .tiltHits: dragHUDInfo = euclideousTiltHitsHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                            case .offsetCount: dragHUDInfo = euclideousOffsetCountHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                            case .gateVelocity: dragHUDInfo = euclideousVelGateHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                            case .noteOctave: dragHUDInfo = euclideousNoteOctHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                            }
                        },
                        rotateStepPt: rotateStepPt)
                )
            }
        }
    }

    /// The permanent-face equivalent of the transient drag HUD. HITS/OFFS gets its OWN compact formatter
    /// (Paul 2026-10-08, ferry §3: "3 HITS OUT OF…" truncated at small pad sizes) — "K/N · ±R" in one line,
    /// matching the format VEL/GATE already used and the ratified mockup's own literal example string
    /// ("5/16 · +0"), rather than reusing `euclidLaneDragHUDInfo`'s verbose "N HITS OUT OF M"/"OFFSET BY K"
    /// pair, which was built for the much roomier floating drag-HUD card and was never going to fit a ~44pt
    /// pad face. The transient drag HUD (below, `onDragState`) is UNCHANGED — it has the room for the
    /// verbose form and nobody asked to compact that one.
    private func euclideousPadInfo(_ idx: Int, _ line: EuclidLine, _ t: EuclideousGestureTab) -> EuclidDragHUDInfo {
        switch t {
        case .tiltHits: return euclideousTiltHitsHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        case .offsetCount: return euclideousOffsetCountHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        case .gateVelocity: return euclideousVelGateHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        case .noteOctave: return euclideousNoteOctHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        }
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

    /// RIFF tab (Paul 2026-10-07, §3): OFF + all 6 `RiffDir` cases over TWO lines, 4 columns — short labels
    /// (PEND/PING/RAND) scoped to THIS local lookup only, never touching the shared `RiffDir.displayLabel`
    /// enum (that enum also serves the unrelated, regular chainable RIFF processor elsewhere in the app).
    private func riffDirGrid(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        let options: [RiffDir?] = [nil] + RiffDir.allCases   // nil = OFF; 7 total
        func shortLabel(_ d: RiffDir) -> String {
            switch d {
            case .forward: return "FWD"; case .reverse: return "REV"; case .pendulum: return "PEND"
            case .pingpong: return "PING"; case .random: return "RAND"; case .drunk: return "DRUNK"
            }
        }
        let rows = stride(from: 0, to: options.count, by: 4).map { Array(options[$0..<min($0 + 4, options.count)]) }
        return VStack(spacing: sp4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: sp4) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let opt = rows[r][c]
                        let isOff = opt == nil
                        let on = isOff ? !line.useRiffResolved : (line.useRiffResolved && line.riffDirResolved == opt)
                        Text(isOff ? "OFF" : shortLabel(opt!))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: rowH)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.7) : Color.white.opacity(0.06)))
                            .contentShape(Rectangle())
                            .onTapGesture { edit(idx) { if isOff { $0.useRiff = false } else { $0.useRiff = true; $0.riffDir = opt } } }
                    }
                    if rows[r].count < 4 {
                        ForEach(0..<(4 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: rowH) }
                    }
                }
            }
        }
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

    // MARK: - Pure per-lane X/Y mutation (the 4 gesture pads)

    /// Pure per-line mutation, shared by the single-lane and all-lanes paths below (Paul 2026-10-08 reshuffle):
    /// TILT/HITS → Δtilt; OFFS/CNT → Δrotate (unchanged from the old HITS/OFFS pad's own X mapping); GATE/VEL
    /// → Δgate (SWAPPED onto X — was the Y-axis of the old VEL/GATE pad); NOTE/OCTAVE → step the note-select
    /// cycle (unchanged).
    private func applyX(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .tiltHits: line.tilt = max(-1, min(1, line.tiltResolved + Double(d) * 0.08))
        case .offsetCount: line.rotate = ((line.rotate - d) % 16 + 16) % 16
        case .gateVelocity: line.gate = max(0.05, min(1, line.gateResolved + Double(d) * 0.09))
        case .noteOctave:
            if line.useRiffResolved { line.riffRotate = line.riffRotateResolved + d }
            else { line.noteSel = euclideousStepNoteSel(line.noteSelResolved, by: d) }
        }
    }
    /// Pure per-line mutation — TILT/HITS → Δhits (unchanged from the old HITS/OFFS pad's own Y mapping);
    /// OFFS/CNT → Δsteps (NEW — mirrors the comet bar's own pinch-to-resize clamp exactly: pulling steps below
    /// the current hit count pulls hits down with it); GATE/VEL → Δvelocity (SWAPPED onto Y); NOTE/OCTAVE →
    /// Δoctave (unchanged).
    private func applyY(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .tiltHits: let v = max(1, min(max(2, line.steps), line.pulses + d)); line.pulses = min(v, line.steps)
        case .offsetCount: let v = max(2, min(16, line.steps + d)); line.steps = v; if line.pulses > v { line.pulses = v }
        case .gateVelocity: line.velocity = max(0, min(2, line.velocityResolved + Double(d) * 0.15))
        case .noteOctave:
            if line.useRiffResolved { line.riffOctave = max(-3, min(3, line.riffOctaveResolved + d)) }
            else { line.octave = max(-3, min(3, line.octaveResolved + d)) }
        }
    }
    private func euclideousApplyX(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyX(&$0, tab, d) } }
    private func euclideousApplyY(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyY(&$0, tab, d) } }
    private func euclideousApplyAllX(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyX(&lines[i], tab, d) } } }
    private func euclideousApplyAllY(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyY(&lines[i], tab, d) } } }

    // THE RESHUFFLED PADS' OWN FORMATTERS (Paul 2026-10-08) — mirror `euclidLaneDragHUDInfo`'s own (label,
    // primary, secondary, point) shape exactly, same as the VEL/GATE and NOTE/OCT formatters below. Reused for
    // both the pads' permanent face display (`euclideousPadInfo`) and the transient drag HUD (`onDragState`).
    private func euclideousTiltHitsHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        let pct = Int((line.tiltResolved * 100).rounded())
        // SINGULAR (ferry §4.3): "1 HIT", not "1 HITS." Subtitle drops the "TILT" word (ferry §4 type-scale
        // budget — worst case "16 HITS" value / "-100%" subtitle both fit the fixed sizes; by elimination a
        // bare signed percentage on THIS pad can only be tilt, since the value already names hits).
        let hitWord = line.pulses == 1 ? "HIT" : "HITS"
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: "\(line.pulses) \(hitWord)", secondary: "\(pct >= 0 ? "+" : "")\(pct)%", point: point)
    }
    private func euclideousOffsetCountHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        // WRAPPED TO THE STEP COUNT (ferry §4.2): "lane 1 shows OFFS +14 with 8 steps; it should read +6."
        // The STORED `rotate` can legitimately exceed `steps` — its own clamp (`applyX`'s `.offsetCount`
        // case) wraps mod 16 unconditionally, independent of the line's current step count, and the real
        // pattern engine (`euclidPatternInto`) already wraps correctly by the true step count at read time —
        // so this was a DISPLAY-only bug, fixed here by wrapping the shown value to the line's own `steps`,
        // not by changing how `rotate` is stored/clamped. Value compacted "STEPS"→"STP" (ferry §4 budget);
        // subtitle drops the "OFFS" word for the same by-elimination reason as TILT/HITS above.
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: "\(line.steps) STP", secondary: "+\(r)", point: point)
    }
    // THE OTHER TWO HUD FORMATTERS (Paul 2026-10-06: "we need different overlays for velocity, gate, etc.") —
    // Euclideous-only (the BUILD-page editor has no VEL/GATE or NOTE/OCT tab to show one for), mirroring
    // `euclidLaneDragHUDInfo`'s own (label, primary, secondary, point) shape exactly. Reused as-is (2026-10-07)
    // for the pads' own permanent face display, not just the transient HUD — see `euclideousPadInfo` above.
    //
    // REBUILT (Paul 2026-10-09, ferry §1/§7: "Lane 1 shows velocity 200. MIDI velocity is 1-127... if a value
    // above 127 is a scaling percentage, label it as a percentage"): `velocityResolved` is a 0...2 SCALE
    // MULTIPLIER on the struck note's own inherited velocity (see `runEuclidLine`'s `velScale: velocity`),
    // NOT a MIDI velocity value — displaying `Int(velocityResolved*100)` with no unit read as an invalid raw
    // MIDI velocity (up to 200, past the real 1-127 ceiling). Now explicitly labelled a percentage ("200%"),
  // matching the ferry's own suggested fix, and split one-number-per-row (value=velocity%, the Y-axis
    // parameter per `applyY`'s `.gateVelocity` case; subtitle=gate%, the X-axis parameter) — consistent with
    // the OTHER 3 pads' own Y=value/X=subtitle convention, which this one pad didn't follow before (it showed
    // both numbers combined in one line). Each is a bare "{n}%" (ferry §4 budget: "200%" is 4 characters,
    // comfortably under the fixed value size's own ceiling) — no name prefix, since the heading "GATE/VEL"
    // itself (gate named first, matching the X-first dictation convention every other pad's heading uses)
    // plus the value/subtitle POSITIONS already identify which number is which, the same elimination logic
    // the other 3 pads already rely on.
    private func euclideousVelGateHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        let velPct = Int((line.velocityResolved * 100).rounded())
        let gatePct = Int((line.gateResolved * 100).rounded())
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: "\(velPct)%", secondary: "\(gatePct)%", point: point)
    }
    private func euclideousNoteOctHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        let label = allRows ? "ALL LANES" : "LANE \(idx + 1)"
        if line.useRiffResolved {
            // Riff mode keeps its own pre-existing value=X(shift)/subtitle=Y(octave) mapping — the one pad
            // whose two sub-modes (riff/non-riff) share this shape, left as-is (not relitigated by this
            // ferry); only the STRINGS are compacted to fit the fixed type scale (ferry §4).
            //
            // WRAPPED TO THE RIFF'S OWN STEP COUNT (Paul 2026-10-09, drag-HUD legibility review — the exact
            // ferry §4.2 fix already applied to OFFSET/COUNT's own rotate above, missed here): `riffRotate`
            // carries NO stored clamp at all — `applyX`'s riff branch (`line.riffRotate = riffRotateResolved
            // + d`) just accumulates forever, unlike `riffOctave`'s own -3...3 clamp two lines below. The
            // ENGINE already wraps it correctly at read time (`riffRotateStep`'s own double-mod against the
            // riff's real step count), so the SOUND was never wrong — only the DISPLAY, which showed the raw,
            // unbounded stored value as-is. That's not just confusing (a lane dragged a few laps past zero on
            // an 8-step riff showed "19" instead of "3," the step actually in effect) — left unfixed, it's a
            // genuine risk to this pad's own fixed-size type scale: `padValueSize` carries NO
            // `.minimumScaleFactor` by design (ferry §4), sized around a 7-character ceiling ("16 HITS"); an
            // unwrapped value could eventually grow past that many digits and silently overflow the pad face,
            // with no shrink-to-fit safety net to catch it. Wrapping to `riff.stepsResolved` (≤32) caps the
            // displayed value at 2 digits, well inside the budget, same as every other pad's own value.
            let n = riff.stepsResolved
            let rot = ((line.riffRotateResolved % n) + n) % n
            let oct = line.riffOctaveResolved
            return EuclidDragHUDInfo(label: label, primary: "\(rot)", secondary: "OCT \(oct > 0 ? "+" : "")\(oct)", point: point)
        }
        let oct = line.octaveResolved
        // RAW NOTE-SELECT LABELS ABBREVIATED (ferry §4 budget): "RANDOM"(6)/"CYCLE"(5) were the longest value
        // strings on this page — shortened to fit the fixed value size alongside every other pad's own
        // 7-character ceiling ("16 HITS"), matching the compact-form spirit the ferry's own examples use.
        let selLabel: String
        switch line.noteSelResolved {
        case .random: selLabel = "RND"
        case .cycle: selLabel = "CYC"
        default: selLabel = line.noteSelResolved.rawValue
        }
        return EuclidDragHUDInfo(label: label, primary: selLabel,
                                  secondary: "OCT \(oct > 0 ? "+" : "")\(oct)", point: point)
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
    /// SIZED FROM THE CALLER'S OWN `rowH` DIRECTLY (ferry §5/§6, 2026-10-09 rebuild) — portrait passes the
    /// fixed `riffRowHeight` (30pt, "rows about 30pt tall"); landscape passes whatever row height makes the
    /// WHOLE panel exactly `belowH` tall (so "both are the same height" holds by construction, not as two
    /// independently-computed numbers that could silently disagree — the RATCHET/DEST class of bug this
    /// codebase's history keeps flagging). `cellW` is still derived from `maxWidth` here, since width has no
    /// competing "must match something else exactly" constraint the way height does.
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
