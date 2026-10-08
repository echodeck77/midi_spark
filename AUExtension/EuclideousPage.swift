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
enum EuclideousGestureTab: Int, CaseIterable { case hitsOffset = 0, velocityGate = 1, noteOctave = 2
    var label: String { switch self { case .hitsOffset: "HITS/OFFS"; case .velocityGate: "VEL/GATE"; case .noteOctave: "NOTE/OCT" } }
}

/// PER-LANE TABS (Paul 2026-10-07): PATTERN/RIFF/MASK, switching independently per lane — replaces
/// the old always-visible stacked DIRECTION/HIT-MISS-RATE/RIFF-direction rows with one tabbed slot.
enum EuclideousLaneTab: Int, CaseIterable {
    case pattern = 0, riff = 1, mask = 2
    var label: String { switch self { case .pattern: "PATTERN"; case .riff: "RIFF"; case .mask: "MASK" } }
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
    let riffSourceMidi: Bool
    let lanesSourceMidi: Bool
    let mainOutMask: UInt8
    let clock: EuclidLiveClock
    let onEdit: (@escaping (inout [EuclidLine]) -> Void) -> Void
    let onEditRiff: (@escaping (inout EuclideousRiff) -> Void) -> Void
    let onToggleEnabled: () -> Void
    let onSetResetSpanBars: (Int) -> Void
    let onSetKeyRoot: (Int) -> Void
    let onSetKeyType: (ScaleType) -> Void
    let onSetRiffSourceMidi: (Bool) -> Void
    let onSetLanesSourceMidi: (Bool) -> Void
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

    private let laneAccents: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.35, green: 0.75, blue: 0.95),
        Color(red: 0.95, green: 0.75, blue: 0.25), Color(red: 0.55, green: 0.85, blue: 0.45),
    ]
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // RESPONSIVE FLOORS (Paul 2026-10-08, ferry §3): "do not shrink the riff grid cells or the XY pads below
    // comfortable touch size, and do not make lane OUT or MAIN OUT any smaller than they are now." These are
    // the hard floors every size computation below clamps against — spacing and text shrink FIRST (see
    // `headerScale`/the lane-card internals, which already use small fixed fonts with `minimumScaleFactor`),
    // never these. `minPadSize` is the HIG touch-target minimum (44pt); `minLaneSize` falls out of it since
    // each lane's own 3 XY pads are literally `size/3` wide (unchanged rule) — a lane can't usefully shrink
    // past 3×44 without its own pads going sub-floor. `minRiffCell` is a smaller, still-comfortable floor for
    // the riff matrix's own toggle cells (a denser 8×8 grid of simple on/off toggles, not a drag surface).
    private let minPadSize: CGFloat = 44
    private var minLaneSize: CGFloat { minPadSize * 3 }
    private let minRiffCell: CGFloat = 24
    private let laneOutSize: CGFloat = 30    // PROTECTED — never smaller than this (ferry §3)
    private let mainOutSize: CGFloat = 36    // PROTECTED — never smaller than this (ferry §3)
    private let outerPad: CGFloat = 16
    private let gap: CGFloat = 12

    // RIFF GRID GEOMETRY — shared constants (Paul 2026-10-08, ferry §3 fix): computed ONCE here and read by
    // BOTH the layout functions (which reserve space for the grid) and `riffGridView` itself (which actually
    // draws it) — the exact "two places independently deriving the same quantity" bug class this codebase's
    // own history repeatedly flags (RATCHET PATTERN/DEST). `riffChromeH` is the grid's own header row (the
    // SOURCE switch, 28pt button + 4pt padding = 32pt, the tallest element in that row) + the 10pt dot row +
    // the panel's own `VStack(spacing: 6)` × 2 gaps between its 3 children (12pt) = 54pt total, before any
    // matrix cell is drawn.
    private let riffCellGap: CGFloat = 3
    private let riffChromeH: CGFloat = 54
    private let riffPanelPad: CGFloat = 20   // the panel's own .padding(10), top+bottom or left+right

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
            }
        }
    }

    // MARK: - Orientation-specific layouts (Paul 2026-10-08, ferry §3)

    /// PORTRAIT: header, then the 2×2 lane grid, then the riff grid below — full width throughout. The lane
    /// grid's own height budget RESERVES real room for the riff grid beneath it (computed from the riff's own
    /// protected floor, not a vague guess) so the two can never compete for the same space.
    private func portraitLayout(_ size: CGSize) -> some View {
        let hScale = headerScale(size.width)
        let headerH = headerHeight(hScale)
        // The riff grid's OWN minimum real estate: its header+dot rows + 8 rows at the floor cell height + 7
        // inter-row gaps + the panel's own padding — built from the SAME shared constants `riffGridView`
        // itself uses, so this reservation can never silently drift out of sync with what the grid draws.
        let riffMinH = riffChromeH + minRiffCell * 8 + riffCellGap * 7 + riffPanelPad
        let vGaps: CGFloat = gap * 2   // between header/lanes/riff and the bottom padding
        let laneAvailH = size.height - headerH - riffMinH - vGaps
        let laneAvailW = size.width - outerPad * 2
        let laneSize = max(minLaneSize, min((laneAvailW - gap) / 2, (laneAvailH - gap) / 2))
        let riffAvailH = size.height - headerH - (laneSize * 2 + gap) - vGaps
        return VStack(spacing: gap) {
            header(hScale).padding(.horizontal, outerPad).padding(.top, outerPad)
            laneGridView(laneSize).padding(.horizontal, outerPad)
            riffGridView(maxWidth: laneAvailW, maxHeight: max(riffMinH, riffAvailH))
                .padding(.horizontal, outerPad).padding(.bottom, outerPad)
                .frame(maxHeight: .infinity)
        }
    }

    /// LANDSCAPE: header across the full width, then the lane grid (left) and the riff grid (right) SIDE BY
    /// SIDE, both filling the height below the header. The lane grid is sized from the available height
    /// FIRST (landscape is typically height-constrained, not width-constrained) and capped at 60% of the
    /// total width so the riff grid always keeps a meaningful share regardless of how tall the panel is.
    private func landscapeLayout(_ size: CGSize) -> some View {
        let hScale = headerScale(size.width)
        let headerH = headerHeight(hScale)
        let belowH = size.height - headerH - gap - outerPad
        let totalContentW = size.width - outerPad * 2
        let laneSize = max(minLaneSize, min((belowH - gap) / 2, (totalContentW * 0.6 - gap) / 2))
        let laneGridW = laneSize * 2 + gap
        let riffW = max(minRiffCell * 8 + riffCellGap * 7, totalContentW - laneGridW - gap)
        return VStack(spacing: gap) {
            header(hScale).padding(.horizontal, outerPad).padding(.top, outerPad)
            HStack(alignment: .top, spacing: gap) {
                laneGridView(laneSize)
                riffGridView(maxWidth: riffW, maxHeight: belowH)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, outerPad).padding(.bottom, outerPad)
        }
    }

    // MARK: - Header (Paul 2026-10-07: two rows — title/reset-span/main-out/on/close, then key/lanes-source)

    /// `scale` (Paul 2026-10-08, ferry §3 — "reduce spacing and text size first") shrinks every label/chip/
    /// button in the header proportionally when the available width is tight, so the row degrades gracefully
    /// instead of letting its trailing elements (the ON button, the LANES switch) run off the edge — the
    /// exact faults the ferry named. MAIN OUT's 4 circles are the one thing in this row explicitly protected
    /// (`mainOutSize`, never scaled) — everything else (labels, the reset/key chips, ON/OFF, close) scales.
    private func headerScale(_ width: CGFloat) -> CGFloat {
        // Reasoned, not measured (no on-device text-metrics pass is possible here): roughly the combined
        // width headerRow1's content needs at scale 1.0 — title + 2 labels + a chip + 4×36pt circles + ON/OFF
        // + close + inter-element gaps. Clamped to a floor so labels never vanish entirely, just shrink.
        let neededAtFullScale: CGFloat = 620
        return max(0.62, min(1, (width - outerPad * 2) / neededAtFullScale))
    }
    /// The header's own real height at a given scale — used by both layouts to reserve exactly the space the
    /// header will actually take, so lane/riff sizing can never silently assume a header height that doesn't
    /// match what's actually drawn.
    private func headerHeight(_ scale: CGFloat) -> CGFloat {
        let row1H: CGFloat = max(28, 36 * scale)   // MAIN OUT's own 36pt circles set the floor for row 1's height
        let row2H: CGFloat = max(26, 36 * scale)
        return row1H + row2H + 10 /* inter-row spacing */ + outerPad /* top padding only; bottom comes from the gap to the next section */
    }

    private func header(_ scale: CGFloat) -> some View {
        VStack(spacing: 10) { headerRow1(scale); headerRow2(scale) }
    }

    private func headerRow1(_ scale: CGFloat) -> some View {
        HStack(spacing: max(4, 10 * scale)) {
            Text("EUCLIDEOUS").font(.system(size: max(12, 18 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Text("RESET").font(.system(size: max(7, 10 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            Text(euclideousResetSpanLabel(resetSpanBars))
                .font(.system(size: max(9, 12 * scale), weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, max(6, 12 * scale)).frame(height: max(24, 32 * scale))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { resetSpanPopupOpen = true }
            Text("MAIN OUT").font(.system(size: max(7, 10 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            HStack(spacing: max(3, 5 * scale)) {
                ForEach(0..<4, id: \.self) { b in mainOutToggle(b) }
            }
            Text(enabled ? "ON" : "OFF").font(.system(size: max(9, 12 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, max(8, 14 * scale)).frame(height: max(24, 32 * scale))
                .background(RoundedRectangle(cornerRadius: 8).fill(enabled ? Color.green.opacity(0.85) : Color.white.opacity(0.08)))
                .onTapGesture { onToggleEnabled() }
            Image(systemName: "xmark.circle.fill").font(.system(size: max(14, 20 * scale)))
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

    // MARK: - Header row 2: KEY + LANES source (Paul 2026-10-07, §2.4)

    private func headerRow2(_ scale: CGFloat) -> some View {
        HStack(spacing: max(4, 8 * scale)) {
            Text("KEY").font(.system(size: max(7, 10 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            keyStepButton("−", scale)
            Text("\(noteNames[((keyRoot % 12) + 12) % 12]) \(keyType.label)")
                .font(.system(size: max(9, 13 * scale), weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, max(6, 12 * scale)).frame(height: max(26, 36 * scale))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.9)))
                .contentShape(Rectangle())
                .onTapGesture { keyPopupOpen = true }
            keyStepButton("+", scale)
            Spacer(minLength: 4)
            Text("LANES").font(.system(size: max(7, 10 * scale), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            sourceSwitch(lanesSourceMidi, onSetLanesSourceMidi, scale)
        }
    }

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

    /// Shared KEY|MIDI segmented switch (Paul 2026-10-07) — ONE implementation serving both header row 2's
    /// LANES switch and the riff panel's own SOURCE switch, so the two can't visually drift apart.
    private func sourceSwitch(_ midiOn: Bool, _ onSet: @escaping (Bool) -> Void, _ scale: CGFloat = 1) -> some View {
        HStack(spacing: 2) {
            sourceSegButton("KEY", on: !midiOn, scale) { onSet(false) }
            sourceSegButton("MIDI", on: midiOn, scale) { onSet(true) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
    private func sourceSegButton(_ label: String, on: Bool, _ scale: CGFloat, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: max(8, 11 * scale), weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: max(38, 50 * scale), height: max(22, 28 * scale))
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white.opacity(0.9) : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    // MARK: - Lane grid (Paul 2026-10-07, §2.8: square boxes — Paul 2026-10-08, ferry §3: sized from whatever
    // box the orientation-specific layout above hands it, never assumed)

    /// A single, explicit square size in — both layouts above compute `size` from their own real available
    /// space (width AND height, whichever binds first) and floor it at `minLaneSize`, so this function never
    /// needs its own notion of "the page" at all.
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
        // `size` is the ONE dimension driving both width and height; the comet row, pads row, tab row and
        // 2-line tab content all now live inside this FIXED budget — `.clipped()` below is a safety net if a
        // very narrow screen can't fit every fixed row, not an expected steady-state.
        let cometRowH: CGFloat = 56
        let padSize = max(minPadSize, size / 3)   // the 3 XY pads stay literal squares, 1/3 the card's own width, floored (ferry §3)
        let tabRowH: CGFloat = 30
        // 36, not 30: `maskCometRow`'s own play button/step badge insist on a 36pt minimum (a touch-target
        // floor, not an arbitrary number) regardless of what's budgeted here — at 30 that made the MASK tab's
        // content render 6pt taller than PATTERN/RIFF's own budgeted rows, shifting the card's layout by a
        // few points on every tab switch. Raising the shared floor to 36 (rather than shrinking MASK's touch
        // targets down to 30) keeps all three tabs' content height IDENTICAL.
        let contentLineH: CGFloat = 36
        let outRowH: CGFloat = 34
        let steps = max(2, min(16, line.steps))
        let rotateStepPt = euclidBoxGeometry(n: steps, usableWidth: max(1, (size - 64) - 12)).pitch
        VStack(alignment: .leading, spacing: 6) {
            EuclidLaneBox(idx: idx, line: line, width: size, height: cometRowH, accent: accent,
                          selected: selectedLane == idx, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: line.rate ?? .r1_16, spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          onRotateDelta: { _ in }, onHitsDelta: { _ in },      // NEUTERED — the 3 square pads below own this now
                          onStepsDelta: { d in edit(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },   // PINCH — the one thing explicitly kept on the comet bar itself
                          onAllRotateDelta: { _ in }, onAllHitsDelta: { _ in },   // NEUTERED, same reason
                          onDragState: { _, _ in },                              // no HUD/highlight from the comet bar anymore — the pads report their own
                          onSelect: { selectedLane = idx },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          stepCountBadge: AnyView(stepCountBadge(steps)))
            gesturePadRow(idx, line, accent, cellSize: padSize, rotateStepPt: rotateStepPt)
                .frame(maxHeight: .infinity)
            laneTabRow(idx, line, accent, rowH: tabRowH)
            tabContent(idx, line, tab, accent, cellSize: padSize, rowH: contentLineH, fullWidth: size)
            laneOutRow(idx, line, accent: accent)
                .frame(height: outRowH)
        }
        .padding(8)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
        .clipped()
    }

    /// PASSIVE STEP-COUNT NUMERAL (Paul 2026-10-07, §3: "step count shown as a number") — rendered beside
    /// the comet bar via `EuclidLaneBox`'s new optional `stepCountBadge` slot (nil everywhere else, so the
    /// regular BUILD-page EUCLID editor is unaffected).
    private func stepCountBadge(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            .frame(width: 36, height: 44)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
    }

    // MARK: - The 3 gesture pads (Paul 2026-10-06, faces now show their value permanently — 2026-10-07 §3)

    /// The 3 gesture PADS (HITS/OFFS · VEL/GATE · NOTE/OCT) — square, 1/3 the lane's own width each (floored
    /// at `minPadSize`). Each is its OWN independent 1-/2-finger drag surface (via a dedicated
    /// `EuclidGesturePad` instance per button) wired directly to that button's own X/Y mapping. PINCH
    /// (`onStepsDelta`) is a no-op here — that gesture stays on the comet bar itself.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rotateStepPt: CGFloat) -> some View {
        HStack(spacing: 0) {
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
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black.opacity(0.75) : .white.opacity(0.5))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(info.primary)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(touched ? .black : .white.opacity(0.92))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if !info.secondary.isEmpty {
                            Text(info.secondary)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(touched ? .black.opacity(0.7) : .white.opacity(0.55))
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(4)
                }
                .frame(width: cellSize, height: cellSize)
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
                            case .hitsOffset: dragHUDInfo = euclidLaneDragHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                            case .velocityGate: dragHUDInfo = euclideousVelGateHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
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
        case .hitsOffset:
            let r = line.rotate
            return EuclidDragHUDInfo(label: "LANE \(idx + 1)", primary: "\(line.pulses)/\(line.steps) · \(r >= 0 ? "+" : "")\(r)", secondary: "", point: .zero)
        case .velocityGate: return euclideousVelGateHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        case .noteOctave: return euclideousNoteOctHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
        }
    }

    // MARK: - Per-lane tab row + content (Paul 2026-10-07, §2.6)

    private func laneTabRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(EuclideousLaneTab.allCases, id: \.rawValue) { t in
                let sel = (idx < laneTab.count ? laneTab[idx] : .pattern) == t
                // DOT (Paul 2026-10-07, §3): RIFF/MASK carry a small dot, lane-coloured when the feature is
                // on for the lane — PATTERN never shows one (it's always "on"). MASK's "on" reads as "this
                // lane has a mask configured at all" (line.mask != nil), the literal translation of the
                // ratified mockup's own `!!d.mask` check — there's no further "effect enabled" concept yet
                // since the mask's effect itself is deferred (§4.1).
                let dotOn: Bool = t == .riff ? line.useRiffResolved : (t == .mask ? (line.mask != nil) : false)
                HStack(spacing: 5) {
                    Text(t.label).font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(sel ? .white.opacity(0.95) : .white.opacity(0.45))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if t != .pattern {
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

    /// HIT | MISS | RATE. HIT/MISS is a symmetric 2-way selector (see `missSelected`'s own doc comment) —
    /// tapping the NON-selected side performs the actual invert (`euclideousInvertLine`) and flips which one
    /// shows "selected"; tapping the already-selected side is a no-op. RATE opens the pop-up (`ratePopupLane`);
    /// the button shows FOLLOW (Paul 2026-10-07, §3 — was "—") when the line's rate is genuinely unset (nil
    /// ⇒ inherit the machine-wide rate) rather than silently defaulting the display to 1/16.
    private func hitMissRateRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let missOn = idx < missSelected.count && missSelected[idx]
        func sideButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
                .frame(width: cellSize, height: rowH)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? accent.opacity(0.85) : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        return HStack(spacing: 0) {
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
            Text(line.rate == nil ? "FOLLOW" : line.rate!.rawValue)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: cellSize, height: rowH)
                .background(Color.white.opacity(0.06))
                .contentShape(Rectangle())
                .onTapGesture { ratePopupLane = idx }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    // MARK: - Pure per-lane X/Y mutation (the 3 gesture pads)

    /// Pure per-line mutation, shared by the single-lane and all-lanes paths below — HITS/OFFSET (default) →
    /// Δrotate; VELOCITY/GATE → Δvelocity (scaled); NOTE/OCTAVE → step the note-select cycle.
    private func applyX(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: line.rotate = ((line.rotate - d) % 16 + 16) % 16
        case .velocityGate: line.velocity = max(0, min(2, line.velocityResolved + Double(d) * 0.15))
        case .noteOctave:
            if line.useRiffResolved { line.riffRotate = line.riffRotateResolved + d }
            else { line.noteSel = euclideousStepNoteSel(line.noteSelResolved, by: d) }
        }
    }
    /// Pure per-line mutation — HITS/OFFSET → Δhits; VELOCITY/GATE → Δgate (scaled); NOTE/OCTAVE → Δoctave.
    private func applyY(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: let v = max(1, min(max(2, line.steps), line.pulses + d)); line.pulses = min(v, line.steps)
        case .velocityGate: line.gate = max(0.05, min(1, line.gateResolved + Double(d) * 0.09))
        case .noteOctave:
            if line.useRiffResolved { line.riffOctave = max(-3, min(3, line.riffOctaveResolved + d)) }
            else { line.octave = max(-3, min(3, line.octaveResolved + d)) }
        }
    }
    private func euclideousApplyX(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyX(&$0, tab, d) } }
    private func euclideousApplyY(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyY(&$0, tab, d) } }
    private func euclideousApplyAllX(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyX(&lines[i], tab, d) } } }
    private func euclideousApplyAllY(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyY(&lines[i], tab, d) } } }

    // THE OTHER TWO HUD FORMATTERS (Paul 2026-10-06: "we need different overlays for velocity, gate, etc.") —
    // Euclideous-only (the BUILD-page editor has no VEL/GATE or NOTE/OCT tab to show one for), mirroring
    // `euclidLaneDragHUDInfo`'s own (label, primary, secondary, point) shape exactly. Reused as-is (2026-10-07)
    // for the pads' own permanent face display, not just the transient HUD — see `euclideousPadInfo` above.
    private func euclideousVelGateHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                           primary: "\(Int((line.velocityResolved * 100).rounded())) · \(Int((line.gateResolved * 100).rounded()))%",
                           secondary: "VEL · GATE", point: point)
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

    // MARK: - OUT row (Paul 2026-10-07, §2.8/§3: smaller toggles, NO OUTPUT, dashed/hollow main-held chips)

    /// `laneControls` from the pre-rework page collapses to just this one row now — the two `EuclidBeacon`
    /// calls that used to sit above it are REMOVED entirely (§2.8: "remove the hit/miss beacons"). Fixed at
    /// 30pt (ferry §3: "do not make lane OUT... any smaller than they are now") regardless of any outer scale.
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
  /// sit above the columns, unchanged. NO rank/note-name readout anywhere (ferry §2 — the 2026-10-08 "show
    /// both the rank and the resolved note" addition is fully reversed, not relocated). Sized from an explicit
    /// `(maxWidth, maxHeight)` box the caller computes (portrait: full width, below the lanes; landscape: the
    /// right column, full height) — cell dimensions are independently floored at `minRiffCell` and the grid's
    /// own frame is exactly `8×cell + 7×gap` in each axis, which may exceed the handed box at the floor rather
    /// than silently shrinking past comfortable touch size (ferry §3).
    private func riffGridView(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        let cellGap = riffCellGap
        let cellW = max(minRiffCell, (maxWidth - riffPanelPad - cellGap * CGFloat(n - 1)) / CGFloat(n))
        let cellH = max(minRiffCell, (maxHeight - riffChromeH - riffPanelPad - cellGap * 7) / 8)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("RIFF").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                Text("8 STEPS · SHARED BY EVERY LANE WITH RIFF ON")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text("SOURCE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                sourceSwitch(riffSourceMidi, onSetRiffSourceMidi)
            }
            HStack(spacing: cellGap) {
                ForEach(0..<n, id: \.self) { col in
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] == col {
                                Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(width: cellW, height: 10)
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
        .padding(10)
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
