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

    // RESPONSIVE SIZING (Paul 2026-10-09, ferry §1.1 — supersedes the 2026-10-08 "protected floor" rule
    // wherever the two conflict): "nothing may extend past the plugin view in either orientation" now wins
    // over the earlier touch-size floors. Every size below is a TARGET the layout functions use to decide how
    // much space to RESERVE for a section when there's room — never a forced minimum that lets the rendered
    // content exceed the box it's actually been given. `minPadSize` is the HIG touch-target AIM for a gesture
    // pad (no longer force-applied inside `laneCard` — see its own §1.3 rewrite); `riffCellTarget` is the
    // ferry's own "~30pt tall" riff-cell aim, used only to decide how much height/width `portraitLayout`/
    // `landscapeLayout` try to reserve for the riff panel, never as a floor inside `riffGridView` itself
    // (which always renders to fit exactly whatever box it's handed, smaller if the screen demands it).
    // `laneOutSize`/`mainOutSize` are UNCHANGED, still genuinely protected (ferry §3, 2026-10-08) — nothing in
    // this pass touches either.
    private let minPadSize: CGFloat = 44
    private let riffCellTarget: CGFloat = 30
    private let laneOutSize: CGFloat = 30    // PROTECTED — never smaller than this (ferry §3)
    private let mainOutSize: CGFloat = 36    // PROTECTED — never smaller than this (ferry §3)
    private let outerPad: CGFloat = 16
    private let gap: CGFloat = 12

    // RIFF GRID GEOMETRY — shared constants (Paul 2026-10-08, ferry §3 fix; tightened 2026-10-09, ferry §2.1):
    // computed ONCE here and read by BOTH the layout functions (which reserve space for the grid) and
    // `riffGridView` itself (which actually draws it) — the exact "two places independently deriving the same
    // quantity" bug class this codebase's own history repeatedly flags (RATCHET PATTERN/DEST). `riffChromeH`
    // is the grid's own header text row (~18pt, no SOURCE-switch button anymore — removed with the per-lane
    // I/O rework, the old 54pt estimate predates that) + the 12pt dot row + the panel's own
    // `VStack(spacing: 4)` × 2 gaps between its 3 children (8pt) = 38pt total, before any matrix cell is drawn.
    private let riffCellGap: CGFloat = 3
    private let riffChromeH: CGFloat = 38
    private let riffPanelPad: CGFloat = 12   // the panel's own .padding(6), top+bottom or left+right (tightened from .padding(10)/20 — ferry §2.1)

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
                    let y = max(40, info.point.y - origin.y - 130)
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

    // MARK: - Orientation-specific layouts (Paul 2026-10-08, ferry §3)

    /// PORTRAIT: header, then the 2×2 lane grid, then the riff grid below — full width throughout. The riff
    /// panel gets a FIXED, DELIBERATELY SMALL height target (ferry §2.1 — "~30pt" cells, not "whatever's left
    /// after the lanes," the old shape); any space the lanes don't need goes back to the riff panel, but the
    /// lanes are never forced BIGGER than what the screen actually allows (ferry §1.1 — fit always wins over
    /// the old touch-size floors wherever the two would conflict).
    private func portraitLayout(_ size: CGSize) -> some View {
        let hScale = headerScale(size.width)
        let headerH = headerHeight(hScale)
        let riffTargetH = riffChromeH + riffCellTarget * 8 + riffCellGap * 7 + riffPanelPad
        let vGaps: CGFloat = gap * 2   // between header/lanes/riff and the bottom padding
        let laneAvailW = size.width - outerPad * 2
        let laneAvailH = max(1, size.height - headerH - riffTargetH - vGaps)
        let laneSize = max(1, min((laneAvailW - gap) / 2, (laneAvailH - gap) / 2))
        let riffAvailH = max(1, size.height - headerH - (laneSize * 2 + gap) - vGaps)
        return VStack(alignment: .leading, spacing: gap) {
            header(hScale).padding(.horizontal, outerPad).padding(.top, outerPad)
            // SHARED MARGINS (ferry §1.2): `.leading` on this VStack AND an explicit full-width leading frame
            // on the lane grid keep every section's LEFT edge at the same `outerPad`, even when the lane
            // grid's own content (laneSize×2+gap) comes out narrower than the full available width — the old
            // default-centre VStack alignment shifted a narrower lane grid right, producing a bigger left
            // margin than the header/riff rows beside it.
            laneGridView(laneSize).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, outerPad)
            riffGridView(maxWidth: laneAvailW, maxHeight: min(riffTargetH, riffAvailH))
                .padding(.horizontal, outerPad).padding(.bottom, outerPad)
        }
    }

    /// LANDSCAPE: header across the full width, then the lane grid (left) and the riff grid (right) SIDE BY
    /// SIDE, both filling the height below the header. The riff column now gets a FIXED, narrow width target
    /// (ferry §2.2 — was capped at 60% width for the LANE grid, i.e. riff got ~40%; the riff column is now
    /// sized from the same small ~30pt-cell aim portrait uses, with the lane grid claiming everything else).
    private func landscapeLayout(_ size: CGSize) -> some View {
        let hScale = headerScale(size.width)
        let headerH = headerHeight(hScale)
        let belowH = max(1, size.height - headerH - gap - outerPad)
        let totalContentW = size.width - outerPad * 2
        let riffTargetW = riffPanelPad + riffCellTarget * 8 + riffCellGap * 7
        let laneGridTargetW = max(1, totalContentW - riffTargetW - gap)
        let laneSize = max(1, min((belowH - gap) / 2, (laneGridTargetW - gap) / 2))
        let riffW = max(1, totalContentW - (laneSize * 2 + gap) - gap)
        return VStack(alignment: .leading, spacing: gap) {
            header(hScale).padding(.horizontal, outerPad).padding(.top, outerPad)
            HStack(alignment: .top, spacing: gap) {
                laneGridView(laneSize)
                riffGridView(maxWidth: riffW, maxHeight: belowH)
            }
            .padding(.horizontal, outerPad).padding(.bottom, outerPad)
        }
    }

    // MARK: - Header (Paul 2026-10-08: collapsed to ONE row — title/reset-span/KEY/CHORDS/main-out/on/close.
    // KEY used to live on its own second row; moved up here per Paul's explicit "move the key selector to the
    // top header," with CHORDS placed directly beside it ("next to it place a chords button"). Once KEY moved
    // out, row 2 had nothing left in it (the LANES switch it used to share the row with was already retired
    // into the per-lane I/O tab) — collapsing to one row is a direct consequence, not scope creep, and frees
    // real vertical space for the lane/riff grids below.

    /// `scale` (ferry §3 — "reduce spacing and text size first") shrinks every label/chip/button in the header
    /// proportionally when the available width is tight, so the row degrades gracefully instead of letting its
    /// trailing elements run off the edge. MAIN OUT's 4 circles are the one thing in this row explicitly
    /// protected (`mainOutSize`, never scaled) — everything else scales.
    private func headerScale(_ width: CGFloat) -> CGFloat {
        // Reasoned, not measured (no on-device text-metrics pass is possible here): roughly the combined width
        // this ONE row's content needs at scale 1.0 — title + RESET label+chip + KEY label+−+chip+plus +
        // CHORDS button + MAIN OUT label+4×36pt circles + ON/OFF + close + inter-element gaps. Widened from
        // the old 620 (when KEY lived on its own second row) now that everything shares one row.
        let neededAtFullScale: CGFloat = 860
        return max(0.62, min(1, (width - outerPad * 2) / neededAtFullScale))
    }
    /// The header's own real height at a given scale — used by both layouts to reserve exactly the space the
    /// header will actually take, so lane/riff sizing can never silently assume a header height that doesn't
    /// match what's actually drawn. One row now, not two.
    private func headerHeight(_ scale: CGFloat) -> CGFloat {
        let rowH: CGFloat = max(28, 36 * scale)   // MAIN OUT's own 36pt circles set the floor
        return rowH + outerPad /* top padding only; bottom comes from the gap to the next section */
    }

    private func header(_ scale: CGFloat) -> some View { headerRow1(scale) }

    private func headerRow1(_ scale: CGFloat) -> some View {
        HStack(spacing: max(3, 8 * scale)) {
            Text("EUCLIDEOUS").font(.system(size: max(11, 16 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 2)
            Text("RESET").font(.system(size: max(7, 9 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            Text(euclideousResetSpanLabel(resetSpanBars))
                .font(.system(size: max(8, 11 * scale), weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, max(5, 10 * scale)).frame(height: max(22, 30 * scale))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { resetSpanPopupOpen = true }
            Text("KEY").font(.system(size: max(7, 9 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            keyStepButton("−", scale)
            Text("\(noteNames[((keyRoot % 12) + 12) % 12]) \(keyType.label)")
                .font(.system(size: max(8, 11 * scale), weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, max(5, 10 * scale)).frame(height: max(22, 30 * scale))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.9)))
                .contentShape(Rectangle())
                .onTapGesture { keyPopupOpen = true }
            keyStepButton("+", scale)
            // CHORDS (Paul 2026-10-08) — "next to [KEY] place a chords button that opens a pop-up to a chord
            // grid with rate control." A dot lights when a real progression has been authored (mirrors the
            // per-lane tab dots' own "is this configured" convention) — always true in practice once touched,
            // since a fresh MachineParams() already resolves to the sensible default loop, not silence.
            Text("CHORDS").font(.system(size: max(8, 11 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, max(6, 12 * scale)).frame(height: max(22, 30 * scale))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { chordsPopupOpen = true }
            Text("MAIN OUT").font(.system(size: max(7, 9 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            HStack(spacing: max(3, 5 * scale)) {
                ForEach(0..<4, id: \.self) { b in mainOutToggle(b) }
            }
            Text(enabled ? "ON" : "OFF").font(.system(size: max(8, 11 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, max(6, 12 * scale)).frame(height: max(22, 30 * scale))
                .background(RoundedRectangle(cornerRadius: 7).fill(enabled ? Color.green.opacity(0.85) : Color.white.opacity(0.08)))
                .onTapGesture { onToggleEnabled() }
            Image(systemName: "xmark.circle.fill").font(.system(size: max(13, 18 * scale)))
                .foregroundColor(.white.opacity(0.5))
                .onTapGesture { onClose() }
        }
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

    private func keyStepButton(_ label: String, _ scale: CGFloat) -> some View {
        Text(label).font(.system(size: max(11, 16 * scale), weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            .frame(width: max(24, 32 * scale), height: max(24, 32 * scale))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
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

    // MARK: - Lane grid (Paul 2026-10-07, §2.8: square boxes — Paul 2026-10-08, ferry §3: sized from whatever
    // box the orientation-specific layout above hands it, never assumed)

    /// A single, explicit square size in — both layouts above compute `size` from their own real available
    /// space (width AND height, whichever binds first — ferry §1.1: never forced bigger than what fits), so
    /// this function never needs its own notion of "the page" at all.
    private func laneGridView(_ size: CGFloat) -> some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) { laneCard(0, size: size); laneCard(1, size: size) }
            HStack(spacing: gap) { laneCard(2, size: size); laneCard(3, size: size) }
        }
    }

    @ViewBuilder private func laneCard(_ idx: Int, size: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        let tab = idx < laneTab.count ? laneTab[idx] : .pattern
        // SQUARE (Paul 2026-10-07, §2.8: "lane boxes are square, using the space reclaimed from the riff") —
        // `size` is the ONE dimension driving both width and height.
        let cometRowH: CGFloat = 56
        let padSize = size / 3    // DIRECTION/HIT-MISS-RATE stay 3 columns, unchanged — 1/3 the card's own width (ferry §1.1: fits, never floored)
        // GESTURE PADS (Paul 2026-10-08): 4 columns (TILT/HITS·OFFS/CNT·GATE/VEL·NOTE/OCT) — this row's own
        // WIDTH per pad, `size/4`, rather than reusing `padSize`'s 3-column width. DISCLOSED CONSEQUENCE:
        // the gesture-pad row doesn't line up column-for-column with the PATTERN tab's 3-column DIRECTION/
        // HIT-MISS-RATE rows beneath it (a cosmetic side effect of adding a 4th pad where nothing else widened
        // to match) — not asked to change, left alone.
        let gesturePadW = size / 4
        let tabRowH: CGFloat = 30
        // Every tab (I/O·PATTERN·RIFF·MASK) renders exactly 2 content rows at this height — confirmed by
        // reading each: `ioSourceRow`+`laneOutRow`, `directionRow`+`hitMissRateRow`, `riffDirGrid`'s 2 groups
        // of 4, `maskCometRow`+`maskStubRow` (`maskCometRow`'s own 36pt-floored play button/badge is WHY this
        // is 36, not 30 — matching it keeps all 4 tabs' content height identical, no per-tab layout jump).
        let contentLineH: CGFloat = 36
        // +2: each tab's own content is `VStack(spacing: 2)` wrapping its 2 rows (confirmed by reading all
        // four — `.io`/`.pattern`/`.mask`'s own literal `VStack(spacing: 2)`, `riffDirGrid`'s identical inner
        // VStack) — the real rendered height is `36+2+36`, not a bare `36*2`; omitting this 2pt undercounted
        // `gestureRowH` below by the same amount, very slightly overflowing the card's own fixed frame.
        let tabContentH: CGFloat = contentLineH * 2 + 2
        // NO EMPTY BANDS (Paul 2026-10-09, ferry §1.3): the gesture-pad row used to sit in a `.frame(maxHeight:
        // .infinity)` slot and render at a FIXED square size (`size/4`), CENTRED within whatever slack the
        // VStack gave it — leaving two equal gaps (above and below the pads) whenever the card was taller than
        // the fixed rows' own combined height. Fixed by computing the row's HEIGHT explicitly as "exactly
        // what's left" (below) and having the pads stretch to fill it — genuinely taller, not padded.
        let outerVPad: CGFloat = 16      // .padding(8), top+bottom
        let rowGaps: CGFloat = 6 * 3     // VStack(spacing: 6) between the 4 children = 3 gaps
        let gestureRowH = max(1, size - cometRowH - tabRowH - tabContentH - outerVPad - rowGaps)
        let steps = max(2, min(16, line.steps))
        let rotateStepPt = euclidBoxGeometry(n: steps, usableWidth: max(1, (size - 64) - 12)).pitch
        VStack(alignment: .leading, spacing: 6) {
            EuclidLaneBox(idx: idx, line: line, width: size, height: cometRowH, accent: accent,
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
            tabContent(idx, line, tab, accent, cellSize: padSize, rowH: contentLineH, fullWidth: size)
        }
        .padding(8)
        .frame(width: size, height: size)
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

    /// The 4 gesture PADS (TILT/HITS · OFFS/CNT · GATE/VEL · NOTE/OCT) — `cellSize` wide, `rowHeight` tall
    /// (ferry §1.3: no longer forced square — stretches to fill whatever height `laneCard` computes is
    /// actually left over, instead of centering a fixed square within it and leaving empty bands above/
    /// below). Each is its OWN independent 1-/2-finger drag surface (via a dedicated `EuclidGesturePad`
    /// instance per button) wired directly to that button's own X/Y mapping. PINCH (`onStepsDelta`) is a
    /// no-op here — that gesture stays on the comet bar itself.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowHeight: CGFloat, rotateStepPt: CGFloat) -> some View {
        // LARGER TYPE IN THE FREED SPACE (Paul 2026-10-09, ferry §4.4): "pad text is very small in landscape
        // (especially RIFF SHIFT/OCT) — use the extra pad height from §1.3 for larger type." Scales the pad's
        // own 3 text lines with however tall the row actually renders — `minimumScaleFactor` below still
        // protects the WIDTH axis regardless of how big the requested size gets, so this can't overflow.
        let fontScale = max(1, min(1.9, rowHeight / 70))
        return HStack(spacing: 0) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
                let touched = touchedPad[idx] == t.rawValue
                // RIFF ADVANCE (Paul 2026-10-06): once a lane's useRiff is on, this ONE pad's label/tint
                // change to reflect the new role and its DRAG retargets to riffRotate/riffOctave instead of
                // noteSel/octave.
                let isRiffPad = t == .noteOctave && line.useRiffResolved
                let info = euclideousPadInfo(idx, line, t)
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(touched ? accent.opacity(0.4) : (isRiffPad ? accent.opacity(0.22) : Color.white.opacity(0.06)))
                    VStack(spacing: 2) {
                        Text(isRiffPad ? "RIFF SHIFT/OCT" : t.label)
                            .font(.system(size: 9 * fontScale, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black.opacity(0.75) : .white.opacity(0.5))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(info.primary)
                            .font(.system(size: 13 * fontScale, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black : .white.opacity(0.92))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if !info.secondary.isEmpty {
                            Text(info.secondary)
                                .font(.system(size: 9 * fontScale, weight: .semibold, design: .monospaced))
                                .foregroundColor(touched ? .black.opacity(0.7) : .white.opacity(0.55))
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(4)
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            VStack(spacing: 2) {
                ioSourceRow(idx, line, accent, rowH: rowH)
                laneOutRow(idx, line, accent: accent).frame(height: rowH)
            }
        case .pattern:
            VStack(spacing: 2) {
                directionRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
                hitMissRateRow(idx, line, accent, cellSize: cellSize, rowH: rowH)
            }
        case .riff:
            riffDirGrid(idx, line, accent, rowH: rowH)
        case .mask:
            VStack(spacing: 2) {
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
        return HStack(spacing: 0) {
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6))
                    .frame(width: cellSize, height: rowH)
                    .background(on ? accent.opacity(0.55) : Color.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.direction = dir } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        let gapW: CGFloat = 4
        // The HIT+MISS pair's own width shrinks by exactly `gapW` (split between the two) so the row's TOTAL
        // width stays `cellSize*3` — matching `directionRow` directly above it — rather than the visible
        // separator gap silently pushing the row a few points wider than the card's own budget.
        let hitMissW = max(1, (cellSize * 2 - gapW) / 2)
        func sideButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
                .frame(width: hitMissW, height: rowH)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? accent.opacity(0.85) : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        return HStack(spacing: gapW) {
            HStack(spacing: 0) {
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
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(spacing: 1) {
                Text("RATE").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Text(line.rate == nil ? "FOLLOW" : line.rate!.rawValue)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: cellSize, height: rowH)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { ratePopupLane = idx }
        }
        // NO outer clip shape here (ferry §3.3): HIT/MISS already clip to their own shared pill above; RATE
        // draws its own independent rounded background — a single clip spanning the whole row (the old shape)
        // would visually re-merge the two groups the 4pt gap is meant to separate.
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
        return VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let opt = rows[r][c]
                        let isOff = opt == nil
                        let on = isOff ? !line.useRiffResolved : (line.useRiffResolved && line.riffDirResolved == opt)
                        Text(isOff ? "OFF" : shortLabel(opt!))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity).frame(height: rowH)
                            .background(on ? accent.opacity(0.7) : Color.white.opacity(0.06))
                            .contentShape(Rectangle())
                            .onTapGesture { edit(idx) { if isOff { $0.useRiff = false } else { $0.useRiff = true; $0.riffDir = opt } } }
                    }
                    if rows[r].count < 4 {
                        ForEach(0..<(4 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: rowH) }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        return HStack(spacing: 8) {
            Image(systemName: m.enabledResolved ? "play.fill" : "stop.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(m.enabledResolved ? accent : .white.opacity(0.4))
                .frame(width: 36, height: max(36, height))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { editMask(idx) { $0.enabled = !$0.enabledResolved } }
            EuclidCometBar(pulses: m.pulsesResolved, steps: steps, rotate: m.rotate ?? 0, invert: false, dir: .fwd,
                           rate: .r1_16, spanN: 0, tint: accent, lanePlaying: m.enabledResolved, clock: clock,
                           width: max(1, width - 64 - 44 - 12),
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
        // SINGULAR (Paul 2026-10-09, ferry §4.3): "1 HIT", not "1 HITS."
        let hitWord = line.pulses == 1 ? "HIT" : "HITS"
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: "\(line.pulses) \(hitWord)", secondary: "TILT \(pct >= 0 ? "+" : "")\(pct)%", point: point)
    }
    private func euclideousOffsetCountHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        // WRAPPED TO THE STEP COUNT (Paul 2026-10-09, ferry §4.2): "lane 1 shows OFFS +14 with 8 steps; it
        // should read +6." The STORED `rotate` can legitimately exceed `steps` — its own clamp
        // (`applyX`'s `.offsetCount` case) wraps mod 16 unconditionally, independent of the line's current
        // step count, and the real pattern engine (`euclidPatternInto`) already wraps correctly by the true
        // step count at read time — so this was a DISPLAY-only bug, fixed here by wrapping the shown value to
        // the line's own `steps`, not by changing how `rotate` is stored/clamped.
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: "\(line.steps) STEPS", secondary: "OFFS +\(r)", point: point)
    }
    // THE OTHER TWO HUD FORMATTERS (Paul 2026-10-06: "we need different overlays for velocity, gate, etc.") —
    // Euclideous-only (the BUILD-page editor has no VEL/GATE or NOTE/OCT tab to show one for), mirroring
    // `euclidLaneDragHUDInfo`'s own (label, primary, secondary, point) shape exactly. Reused as-is (2026-10-07)
    // for the pads' own permanent face display, not just the transient HUD — see `euclideousPadInfo` above.
    // UNCHANGED despite the GATE/VEL axis swap (Paul 2026-10-08) — it already shows both resolved values
    // regardless of which one is driven by which axis, so there's nothing for the swap to invalidate here.
    // ORDER FIXED (Paul 2026-10-09, ferry §4.1): the pad's own heading reads "GATE/VEL" (X=gate, Y=velocity,
    // per Paul's own dictation order when this pad's axes were last set) — but this formatter showed velocity
    // FIRST in both the value string and the subtitle, disagreeing with the heading. Swapped so GATE leads
    // throughout (heading, values, subtitle) — each number keeps its own prior formatting (gate still carries
    // the "%", velocity still doesn't), only their ORDER changed.
    private func euclideousVelGateHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                           primary: "\(Int((line.gateResolved * 100).rounded()))% · \(Int((line.velocityResolved * 100).rounded()))",
                           secondary: "GATE · VEL", point: point)
    }
    private func euclideousNoteOctHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        let label = allRows ? "ALL LANES" : "LANE \(idx + 1)"
        if line.useRiffResolved {
            let rot = line.riffRotateResolved, oct = line.riffOctaveResolved
            return EuclidDragHUDInfo(label: label, primary: "\(rot) · \(oct > 0 ? "+" : "")\(oct)", secondary: "SHIFT · OCT", point: point)
        }
        let oct = line.octaveResolved
        return EuclidDragHUDInfo(label: label, primary: line.noteSelResolved.rawValue,
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
        HStack(spacing: 0) {
            ForEach([EuclideousLaneSource.midi, .key, .chords], id: \.self) { src in
                let on = line.sourceModeResolved == src
                let label = src == .midi ? "MIDI IN" : (src == .key ? "KEY" : "CHORDS")
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity).frame(height: rowH)
                    .background(on ? accent.opacity(0.55) : Color.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.sourceMode = src } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        HStack(spacing: 5) {
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
    /// pattern is shared by every lane that has riff on, not owned by any one of them). Per-lane position dots
    /// sit above the columns, unchanged (ferry §2.3 — the drawing code here never went anywhere; if they still
    /// don't show on device the next thing to check is the live `riffPositions` poll chain, not this view).
    /// NO rank/note-name readout anywhere (ferry §2 — the 2026-10-08 "show both the rank and the resolved
    /// note" addition is fully reversed, not relocated). Sized from an explicit `(maxWidth, maxHeight)` box
    /// the caller computes (portrait: full width, below the lanes; landscape: the right column, full height).
    /// NEVER forces cell size up past what the given box allows (ferry §1.1 — this is the actual fix for "the
    /// riff grid's 8th column is clipped": the old `max(minRiffCell, ...)` floor could demand MORE than the
    /// box, overflowing past it; now the grid always renders to fit exactly, smaller if the screen demands —
    /// `portraitLayout`/`landscapeLayout` are what decide how generous that box is, per ferry §2.1/§2.2).
    private func riffGridView(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        let cellGap = riffCellGap
        let dotRowH: CGFloat = 12
        let cellW = max(1, (maxWidth - riffPanelPad - cellGap * CGFloat(n - 1)) / CGFloat(n))
        let cellH = max(1, (maxHeight - riffChromeH - riffPanelPad - cellGap * 7) / 8)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("RIFF").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                // PER-LANE SOURCE (Paul 2026-10-09, ferry §2.4): the riff's own "SOURCE KEY|MIDI" switch stays
                // removed — but unlike the earlier "follows lane 1" design, each lane now resolves this SHARED
                // shape against ITS OWN I/O-tab choice (Router.swift's `laneNotes(lineIndex)`), not lane 1's —
                // two lanes walking the same shape with different inputs genuinely play different notes.
                Text("8 STEPS · SHARED SHAPE, EACH LANE PLAYS ITS OWN SOURCE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
            }
            HStack(spacing: cellGap) {
                ForEach(0..<n, id: \.self) { col in
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] == col {
                                Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 7, height: 7)
                            }
                        }
                    }
                    .frame(width: cellW, height: dotRowH)
                }
            }
            VStack(spacing: cellGap) {
                ForEach((1...8).reversed(), id: \.self) { rank in
                    HStack(spacing: cellGap) {
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
        .padding(6)   // matches riffPanelPad (12 = 6+6, ferry §2.1 — tightened from .padding(10))
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
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }
}
