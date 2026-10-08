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
            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.055, blue: 0.07).ignoresSafeArea()
                // LAYOUT (Paul 2026-10-07 rework): header (fixed) → the 2×2 SQUARE lane grid (sized from
                // width alone, see `laneGrid`) → the riff panel filling whatever's left. NO SCROLL — same
                // reasoning this page has carried since 2026-10-07's first pass: a SwiftUI ScrollView's own
                // pan recognizer competes with the UIKit pan/pinch recognizers every gesture pad on this
                // page hosts (now MORE of them than before, with the mask's own second pad per lane), so a
                // scroll container stays off the table rather than fighting those recognizers.
                VStack(spacing: 10) {
                    header.padding(.horizontal, 16).padding(.top, 16)
                    laneGrid(geo.size).padding(.horizontal, 16)
                    riffPanel.padding(.horizontal, 16).padding(.bottom, 16).frame(maxHeight: .infinity)
                }
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

    // MARK: - Header (Paul 2026-10-07: two rows — title/reset-span/main-out/on/close, then key/lanes-source)

    private var header: some View {
        VStack(spacing: 10) { headerRow1; headerRow2 }
    }

    private var headerRow1: some View {
        HStack(spacing: 10) {
            Text("EUCLIDEOUS").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 8)
            Text("RESET").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Text(euclideousResetSpanLabel(resetSpanBars))
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture { resetSpanPopupOpen = true }
            Text("MAIN OUT").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { b in mainOutToggle(b) }
            }
            Text(enabled ? "ON" : "OFF").font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .black : .white.opacity(0.6))
                .padding(.horizontal, 14).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(enabled ? Color.green.opacity(0.85) : Color.white.opacity(0.08)))
                .onTapGesture { onToggleEnabled() }
            Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                .foregroundColor(.white.opacity(0.5))
                .onTapGesture { onClose() }
        }
    }

    /// MAIN OUT (Paul 2026-10-07, §2.3): a GLOBAL master gate over every lane's own per-lane routing — 36pt
    /// per the ratified mockup's explicit pixel spec (§3), noticeably bigger than a lane's own 30pt OUT chip
    /// so the two read as different tiers at a glance.
    private func mainOutToggle(_ b: Int) -> some View {
        let on = (mainOutMask >> UInt8(b)) & 1 != 0
        return Text(["A", "B", "C", "D"][b]).font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.6))
            .frame(width: 36, height: 36)
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

    private var headerRow2: some View {
        HStack(spacing: 8) {
            Text("KEY").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            keyStepButton("−") { onSetKeyRoot(((keyRoot - 1) % 12 + 12) % 12) }
            Text("\(noteNames[((keyRoot % 12) + 12) % 12]) \(keyType.label)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.9)))
                .contentShape(Rectangle())
                .onTapGesture { keyPopupOpen = true }
            keyStepButton("+") { onSetKeyRoot((keyRoot + 1) % 12) }
            Spacer(minLength: 8)
            Text("LANES").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            sourceSwitch(lanesSourceMidi, onSetLanesSourceMidi)
        }
    }

    private func keyStepButton(_ label: String, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
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
    private func sourceSwitch(_ midiOn: Bool, _ onSet: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 2) {
            sourceSegButton("KEY", on: !midiOn) { onSet(false) }
            sourceSegButton("MIDI", on: midiOn) { onSet(true) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
    private func sourceSegButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.6))
            .frame(width: 50, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white.opacity(0.9) : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    // MARK: - Lane grid (Paul 2026-10-07, §2.8: square boxes filling the width — §3's own mockup rule)

    /// Square, sized from WIDTH per the ratified mockup's own "2×2 grid of square boxes filling the width"
    /// rule — but capped against a HEIGHT budget too (shortcut-audit addition, not in the original plan): a
    /// width-only square on a wide/short real host panel (the spec's own disclosed risk — "the mockup was
    /// drawn ~35pt taller than the plugin area") could derive a lane size so large the riff panel below it is
    /// left with zero or negative remaining space, directly working against §2.1's "give the space to the
    /// lane boxes" intent (which presumes the riff panel still gets SOME space, not none). The budget reserves
    /// a rough header allowance (2 rows) and a minimum legible riff-panel height before splitting what's left
    /// between the two lane rows — `size` still drives BOTH width and height (still literally square), it's
    /// just the smaller of the two candidate dimensions, so this degrades gracefully on a cramped panel
    /// instead of silently starving the riff panel. Still flagged device-owed — this is a reasoned cap, not a
    /// device-measured one.
    private func laneGrid(_ pageSize: CGSize) -> some View {
        let gap: CGFloat = 12
        let fromWidth = max(1, (pageSize.width - 32 - gap) / 2)
        let headerAllowance: CGFloat = 110, riffMinimum: CGFloat = 140, outerVSpacing: CGFloat = 32
        let heightBudget = pageSize.height - headerAllowance - riffMinimum - outerVSpacing
        let fromHeight = max(1, (heightBudget - gap) / 2)
        let size = min(fromWidth, fromHeight)
        return VStack(spacing: gap) {
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
        // 2-line tab content all now live inside this FIXED budget (a change from the earlier bottom-up-
        // sized design) — `.clipped()` below is a safety net if a very narrow screen can't fit every fixed
        // row, not an expected steady-state (flagged in the device-owed list, same as the mockup's own
        // disclosed "~35pt taller than the real plugin area" caveat).
        let cometRowH: CGFloat = 56
        let padSize = size / 3   // the 3 XY pads stay literal squares, 1/3 the card's own width — unchanged rule
        let tabRowH: CGFloat = 30
        let contentLineH: CGFloat = 30
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

    /// The 3 gesture PADS (HITS/OFFS · VEL/GATE · NOTE/OCT) — square, 1/3 the lane's own width each. Each is
    /// its OWN independent 1-/2-finger drag surface (via a dedicated `EuclidGesturePad` instance per button)
    /// wired directly to that button's own X/Y mapping. PINCH (`onStepsDelta`) is a no-op here — that
    /// gesture stays on the comet bar itself. PAGE REWORK (2026-10-07): each pad now shows its current
    /// value on its OWN face permanently (not only in the transient drag HUD) — reuses the SAME 3 HUD
    /// formatter functions for both the permanent face text and the transient overlay, so the two can never
    /// show different numbers for the same gesture.
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
                        Text(info.secondary)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(touched ? .black.opacity(0.7) : .white.opacity(0.55))
                            .lineLimit(1).minimumScaleFactor(0.5)
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

    /// The permanent-face equivalent of the transient drag HUD — same 3 formatters, a dummy `.zero` point
    /// (never read for this purpose, only `.primary`/`.secondary` are).
    private func euclideousPadInfo(_ idx: Int, _ line: EuclidLine, _ t: EuclideousGestureTab) -> EuclidDragHUDInfo {
        switch t {
        case .hitsOffset: return euclidLaneDragHUDInfo(idx: idx, line: line, point: .zero, allRows: false)
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
                .foregroundColor(.white.opacity(0.7))
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
                            .foregroundColor(on ? .black : .white.opacity(0.6))
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
            .foregroundColor(.white.opacity(0.3))
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
                                  secondary: "OCTAVE \(oct > 0 ? "+" : "")\(oct)", point: point)
    }

    // MARK: - OUT row (Paul 2026-10-07, §2.8/§3: smaller toggles, NO OUTPUT, dashed/hollow main-held chips)

    /// `laneControls` from the pre-rework page collapses to just this one row now — the two `EuclidBeacon`
    /// calls that used to sit above it are REMOVED entirely (§2.8: "remove the hit/miss beacons").
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
                .frame(width: 30, height: 30)
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

    // MARK: - The riff panel (Paul 2026-10-07, §2.1/§3 — moved onto the page, fixed 8 steps, no popup)

    /// A single row of 8 tall cells, one per step — note RANK (not a resolved note NAME: no live pool data
    /// reaches this page today, only `riffPositions`, so there's nothing to resolve a real pitch from; the
    /// pre-rework page also only ever showed ranks, never note names, so this isn't a regression — flagged
    /// as a named simplification in the ferry acknowledgment, not a silent gap) + a bar whose height encodes
    /// the rank. Per-lane position dots sit above the columns. HARDCODED to 8 steps (§2.1) — editing always
    /// writes back an 8-length `ranks` array + `steps = 8`, so a legacy riff longer than 8 steps becomes
    /// genuinely 8-long the moment it's first touched through this page (no separate migration pass, per the
    /// ruling: "no migration work required"). Tap-to-cycle (rank 0...8, wrapping) is an explicit INTERIM
    /// gesture — the real editing gesture for this layout is open (§4.6).
    private var riffPanel: some View {
        let n = 8
        let resolved = riff.ranksResolved
        let ranks = (0..<n).map { $0 < resolved.count ? resolved[$0] : 0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("RIFF").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                Text("8 STEPS · SHARED BY EVERY LANE WITH RIFF ON")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Spacer(minLength: 8)
                Text("SOURCE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                sourceSwitch(riffSourceMidi, onSetRiffSourceMidi)
            }
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { col in
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] == col {
                                Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 10)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { col in
                    let rank = ranks[col]
                    VStack(spacing: 4) {
                        Text(rank >= 1 ? "\(rank)" : "–")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(rank >= 1 ? 0.9 : 0.3))
                            .padding(.top, 6)
                        Spacer(minLength: 2)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(rank >= 1 ? Color.white.opacity(0.85) : Color.clear)
                            .frame(height: max(2, CGFloat(rank) / 8.0 * 44))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEditRiff { r in
                            var rr = (0..<n).map { k -> Int in let rv = r.ranksResolved; return k < rv.count ? rv[k] : 0 }
                            rr[col] = (rr[col] + 1) % 9
                            r.ranks = rr; r.steps = n
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
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
