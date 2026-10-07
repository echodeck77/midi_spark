//  EuclideousPage.swift
//  MidiSpark — EUCLIDEOUS (Paul 2026-10-05): a standalone, playable 4-lane EUCLID instrument.
//  Reuses the EXACT lane box/comet bar/gesture pad/beacon ProcessorBox's own EUCLID editor uses
//  (EuclidLaneUI.swift), sized generously to fill the screen rather than squeezed into a small
//  inline processor panel — "four Euclid lanes in the centre of the screen... a playable,
//  grabbable instrument." Presented as a plain overlay (DiagView's root ZStack), the same
//  mechanism CogPage uses (engine never stops), but NOT CogPage's small bounded-card sizing.
//  Foundation/SwiftUI/UIKit-only, same seam as every other GridUI/BuildPage file.

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

struct EuclideousPage: View {
    let lines: [EuclidLine]
    let enabled: Bool
    let receiver: Int
    let lineReady: UInt8
    // RIFF ADVANCE (Paul 2026-10-06): `riff` is the ONE shared pattern every useRiff-on lane reads; `riffPositions`
    // is each lane's own live step-cursor into it (index 0...3, -1 = not started/off) — "independent cursor per
    // lane" into one shared pattern, not a single shared cursor.
    let riff: EuclideousRiff
    let riffPositions: [Int]
    let clock: EuclidLiveClock
    let onEdit: (@escaping (inout [EuclidLine]) -> Void) -> Void
    let onEditRiff: (@escaping (inout EuclideousRiff) -> Void) -> Void
    let onToggleEnabled: () -> Void
    let onSetReceiver: (Int) -> Void
    let onClose: () -> Void

    @State private var selectedLane = 0
    // RIFF GRID (Paul 2026-10-06): "small until touched, then takes up more of the screen." Collapsed form
    // lives inline in the header row; expanded form is a floating scrim+card overlay (see `body`) — REVISED
    // 2026-10-07 ("the riff overlay should not move the rest of the page down") from an earlier in-flow/
    // ScrollView design that this flag originally drove directly.
    @State private var riffExpanded = false
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

    private let laneAccents: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.35), Color(red: 0.35, green: 0.75, blue: 0.95),
        Color(red: 0.95, green: 0.75, blue: 0.25), Color(red: 0.55, green: 0.85, blue: 0.45),
    ]

    /// Edits ONE line by index — the shared mutation path every per-lane control below goes through.
    private func edit(_ idx: Int, _ mutate: @escaping (inout EuclidLine) -> Void) {
        onEdit { lines in guard idx >= 0, idx < lines.count else { return }; mutate(&lines[idx]) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.055, blue: 0.07).ignoresSafeArea()
                // LAYOUT (Paul 2026-10-06, revised same day for the square gesture-pad redesign below): each
                // lane's own CONTENT now dictates its height bottom-up (play+comet row + the new, much taller
                // square gesture-pad row + the existing controls row) rather than a fixed quarter-screen
                // height forced top-down — a literal square gesture button at 1/3 the lane's WIDTH is often
                // taller than a quarter-screen lane could hold alongside everything else (confirmed by exact
                // arithmetic before asking; Paul's own call: let the lane grow rather than compromise the
                // square sizing or drop the existing controls). Width stays a literal screen quarter (never
                // in tension the same way). NO SCROLL (Paul 2026-10-07: "disable the scrolling on this page")
                // — the same reasoning already established for the regular BUILD-page EUCLID editor: a
                // SwiftUI ScrollView's own pan recognizer competes with the UIKit pan/pinch recognizers every
                // gesture pad on this page hosts, and this page has FAR more of those than that one ever did.
                VStack(spacing: 0) {
                    header.padding(16)
                    laneGrid(geo.size.width).frame(maxWidth: .infinity, alignment: .center).padding(.horizontal, 16)
                }
                // THE RIFF GRID, EXPANDED (Paul 2026-10-07: "should not move the rest of the page down") — a
                // scrim + centred card, the SAME overlay shape as the rate pop-up just below, floating entirely
                // OUTSIDE the page's own layout flow so opening/closing it can never shift the lane grid.
                if riffExpanded {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { withAnimation { riffExpanded = false } }
                        .zIndex(3)
                    let cardW = min(geo.size.width - 40, 560)
                    riffGridExpanded(cardW)
                        .frame(width: cardW)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .zIndex(4)
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
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("EUCLIDEOUS").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
            // RIFF GRID, COLLAPSED (Paul 2026-10-07: "the riff overlay should not move the rest of the page
            // down") — lives INLINE in the header row (a fixed, single row regardless of state) rather than in
            // the scrolling/flowing body, so toggling it can never shift the lane grid. Tapping it opens the
            // EXPANDED view as a true overlay (see `body`'s own `riffExpanded` branch), not an in-flow reveal.
            riffGridCollapsed
            Spacer(minLength: 8)
            Text("IN").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    let on = receiver == i
                    Text(["A", "B", "C", "D"][i]).font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.08)))
                        .onTapGesture { onSetReceiver(i) }
                }
            }
            Text(enabled ? "ON" : "OFF").font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? .black : .white.opacity(0.6))
                .padding(.horizontal, 14).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(enabled ? Color.green.opacity(0.85) : Color.white.opacity(0.08)))
                .onTapGesture { onToggleEnabled() }
            Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                .foregroundColor(.white.opacity(0.5))
                .onTapGesture { onClose() }
        }
    }

    private func laneGrid(_ screenWidth: CGFloat) -> some View {
        let gap: CGFloat = 12
        // QUARTER-SCREEN WIDTH (Paul 2026-10-06): still a literal quarter of the screen's own width — width
        // was never in tension with the square-button redesign the way height was, so this stays unchanged.
        // HEIGHT is no longer computed here at all — `laneCard` now sizes itself bottom-up from its own
        // content (see its own doc comment), so the grid's total height simply falls out of that naturally.
        let cellW = screenWidth / 4
        return VStack(spacing: gap) {
            HStack(spacing: gap) { laneCard(0, width: cellW); laneCard(1, width: cellW) }
            HStack(spacing: gap) { laneCard(2, width: cellW); laneCard(3, width: cellW) }
        }
    }

    // RIFF GRID (Paul 2026-10-06): "at the top centre of the page... a riff grid with step count... small
    // until touched, then takes up more of the screen." One SHARED pattern (`riff`) — just the step CONTENT
    // (steps/ranks); DIRECTION is per-lane now (see `riffDirRow` below), not shown here. Collapsed (called
    // inline from `header`): step count + a mini per-step tick strip + each useRiff-on lane's own live cursor,
    // so "4 independent cursors, one shared pattern" reads even closed. Expanded (called from `body` as a
    // floating overlay when `riffExpanded`): the full rank matrix.
    private var riffGridCollapsed: some View {
        let n = riff.stepsResolved
        let ranks = riff.ranksResolved
        // NARROWER now it lives inline in the header row (Paul 2026-10-07), sharing space with the title/IN/
        // ON-OFF/close cluster — was 200pt as a standalone top-center pill, which no longer fits here.
        let stripW: CGFloat = 110
        let stepW = stripW / CGFloat(max(1, n))
        return HStack(spacing: 8) {
            Text("RIFF").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            Text("\(n)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<n, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(ranks[i] >= 1 ? Color.white.opacity(0.45) : Color.white.opacity(0.1))
                            .frame(height: 10)
                    }
                }
                .frame(width: stripW)
                ForEach(0..<4, id: \.self) { i in
                    if i < lines.count, lines[i].useRiffResolved, i < riffPositions.count, riffPositions[i] >= 0 {
                        Circle().fill(laneAccents[i % laneAccents.count])
                            .frame(width: 7, height: 7)
                            .offset(x: CGFloat(min(n - 1, riffPositions[i])) * stepW + stepW / 2 - 3.5, y: -1)
                    }
                }
            }
            .frame(width: stripW, height: 12)
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { riffExpanded = true } }
    }

    private func riffGridExpanded(_ screenWidth: CGFloat) -> some View {
        let n = riff.stepsResolved
        let ranks = riff.ranksResolved
        let stepW: CGFloat = max(14, min(28, (screenWidth - 260) / CGFloat(max(1, n))))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RIFF").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("COLLAPSE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { riffExpanded = false } }
            }
            HStack(spacing: 10) {
                Text("STEPS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                riffStepperButton("-") { onEditRiff { r in r.steps = max(1, r.stepsResolved - 1) } }
                Text("\(n)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white).frame(width: 28)
                riffStepperButton("+") { onEditRiff { r in r.steps = min(32, r.stepsResolved + 1) } }
            }
            // CURSOR ROW + RANK MATRIX share one horizontal scroll + the same `stepW`, so they can never drift
            // out of column alignment with each other as the grid scrolls.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(0..<n, id: \.self) { col in
                            let activeLanes = (0..<4).filter { i in i < lines.count && lines[i].useRiffResolved && i < riffPositions.count && riffPositions[i] == col }
                            ZStack {
                                ForEach(activeLanes, id: \.self) { i in
                                    Circle().fill(laneAccents[i % laneAccents.count]).frame(width: 6, height: 6)
                                }
                            }
                            .frame(width: stepW, height: 10)
                        }
                    }
                    ForEach((1...8).reversed(), id: \.self) { rank in
                        HStack(spacing: 2) {
                            ForEach(0..<n, id: \.self) { col in
                                let on = col < ranks.count && ranks[col] == rank
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(on ? laneAccents[0].opacity(0.85) : Color.white.opacity(0.08))
                                    .frame(width: stepW, height: 18)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onEditRiff { r in
                                            var rr = r.ranksResolved
                                            if col < rr.count { rr[col] = (rr[col] == rank ? 0 : rank) }
                                            r.ranks = rr
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            // DIRECTION IS PER-LANE now (Paul 2026-10-07: "the back/forward, drunk controls should be per
            // lane, not on the riff control") — this card holds only the SHARED pattern content (steps/ranks);
            // each lane's own direction lives on its own card via `riffDirRow` below (no BIAS control anymore
            // either — dropped same session, never requested).
            Text("Each lane picks its own direction on its own card (OFF / FWD / REV / …).")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.35))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private func riffStepperButton(_ label: String, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    // COMET ROW HEIGHT (Paul 2026-10-06): a modest, FIXED height for the play-button+comet-bar row — no
    // longer "generously sized" the way it was before this redesign, since the step-pattern DISPLAY/pinch-to-
    // resize-steps is now a secondary, visual role; the 3 square pads below are the lane's own PRIMARY
    // interactive surface. Matches the regular BUILD-page EUCLID editor's own established `euclidLaneH`
    // constant (GridUI.swift) rather than inventing a new number.
    private let cometRowH: CGFloat = 56

    @ViewBuilder private func laneCard(_ idx: Int, width: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        // ALTERNATIVE GESTURE CONTROL (Paul 2026-10-06): "change the toggle buttons to be square, with each
        // button taking up a third of the width of the Euclid lane... each will act as an x/y pad in itself."
        // `gestureRowH` is a literal square (1/3 the lane's own WIDTH, on both axes) — this REPLACES the old
        // toggle-then-drag-the-comet-bar model entirely, so `EuclidLaneBox`'s own play+comet row no longer
        // needs to host a live rotate/hits drag at all: its onRotateDelta/onHitsDelta/onAllRotateDelta/
        // onAllHitsDelta/onDragState are now plain no-ops (PINCH, via onStepsDelta, is the one thing explicitly
        // KEPT there — "it behaves exactly as the lane gestures do now (except the pinch)" names pinch as the
        // one exclusion from the NEW per-button pads, which by construction says nothing about removing it
        // from the comet bar itself). `euclidBoxH` is computed bottom-up (12pt padding + the fixed comet row +
        // the exact square gesture row, zero gap between them per the earlier no-gap fix) rather than forced
        // top-down — EuclidLaneBox's own internal math (`reserve`/the comet row's height) is self-consistent
        // by construction, so handing it this EXACT total can never overflow or leave slack.
        let gestureRowH = width / 3
        // DIRECTION ROW (Paul 2026-10-06): "directly below the x/y control, put short backwards, ping pong,
        // forwards buttons, aligned with the three x/y controls" — a SECOND, SHORT (not square) row, same 3
        // column widths as the gesture pads above it, stacked immediately beneath with zero gap (the same
        // "no gap or padding" convention already established for the step-boxes→gesture-pads transition).
        let directionRowH: CGFloat = 32
        // HIT | MISS | RATE ROW (Paul 2026-10-06): "directly below the last set of buttons that were added,
        // put the invert button and rate button" — a THIRD stacked row, same height/convention as the
        // direction row above it, same 3-column width split (HIT · MISS · RATE) matching the gesture-pad/
        // direction rows' own established rhythm.
        let hitMissRateRowH: CGFloat = 32
        // RIFF DIRECTION ROW, PER LANE (Paul 2026-10-07: "the back/forward, drunk controls should be per lane,
        // not on the riff control" — "I don't see the riff controls" named this as plainly missing). A FOURTH
        // stacked row — OFF + all 6 RiffDir options in one compact strip — replacing the earlier hidden tap-
        // toggle on the NOTE/OCT pad with something actually visible. (A conditional BIAS row for DRUNK was
        // here too, same day — DROPPED (Paul 2026-10-07, same session: "another control that I didn't ask
        // for... can we drop?") — never requested, modeled on RIFF's own BIAS knob without being asked.
        // `EuclidLine.riffDirBias`/`riffDirBiasResolved` stay in the model, unreachable from any UI now — a
        // harmless, always-neutral (0) resting value, not worth the churn of also ripping out of Router.swift.)
        let riffDirRowH: CGFloat = 26
        let euclidBoxH = 12 + cometRowH + gestureRowH + directionRowH + hitMissRateRowH + riffDirRowH
        // ROTATE SENSITIVITY (Paul 2026-10-06): "it behaves exactly as the lane gestures do now" — the SAME
        // box-pitch-derived points-per-step the comet bar's own X-axis currently uses (EuclidCometBar.body),
        // recomputed here with the identical formula/inputs so the two can't disagree, since the comet bar's
        // OWN pan is being retired in favour of these buttons. Used uniformly for all 3 buttons' X-axis, not
        // just HITS/OFFSET — the comet bar's existing sensitivity was never actually tab-specific either (one
        // `rotateStepPt` served whichever tab happened to be selected), so this is a faithful match, not a
        // new behaviour invented for the other two tabs.
        let steps = max(2, min(16, line.steps))
        let rotateStepPt = euclidBoxGeometry(n: steps, usableWidth: max(1, (width - 64) - 12)).pitch
        VStack(alignment: .leading, spacing: 8) {
            EuclidLaneBox(idx: idx, line: line, width: width, height: euclidBoxH, accent: accent,
                          selected: selectedLane == idx, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: line.rate ?? .r1_16, spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          onRotateDelta: { _ in }, onHitsDelta: { _ in },      // NEUTERED — the 3 square pads below own this now
                          onStepsDelta: { d in edit(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },   // PINCH — the one thing explicitly kept on the comet bar itself
                          onAllRotateDelta: { _ in }, onAllHitsDelta: { _ in },   // NEUTERED, same reason
                          onDragState: { _, _ in },                              // no HUD/highlight from the comet bar anymore — the pads report their own
                          onSelect: { selectedLane = idx },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          trailingContent: AnyView(
                              VStack(spacing: 0) {
                                  gesturePadRow(idx, line, accent, cellSize: gestureRowH, rotateStepPt: rotateStepPt)
                                  directionRow(idx, line, accent, cellSize: gestureRowH, rowH: directionRowH)
                                  hitMissRateRow(idx, line, accent, cellSize: gestureRowH, rowH: hitMissRateRowH)
                                  riffDirRow(idx, line, accent, rowH: riffDirRowH)
                              }
                          ),
                          trailingHeight: gestureRowH + directionRowH + hitMissRateRowH + riffDirRowH)
            laneControls(idx, line, accent: accent)
        }
        .padding(8)
        .frame(width: width)   // height no longer forced — the VStack sizes naturally from its two exactly-sized children
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
    }

    /// The 3 gesture PADS (HITS/OFFS · VEL/GATE · NOTE/OCT) — square, 1/3 the lane's own width each,
    /// handed to `EuclidLaneBox` as `trailingContent` (renders inside the lane's own box, flush beneath the
    /// step boxes). Each is its OWN independent 1-/2-finger drag surface (via a dedicated `EuclidGesturePad`
    /// instance per button) wired directly to that button's own X/Y mapping — no "selected tab" to toggle
    /// first; touching VEL/GATE and dragging immediately adjusts velocity/gate, just as touching HITS/OFFS
    /// and dragging immediately adjusts offset/hits. PINCH (`onStepsDelta`) is a no-op here — "except the
    /// pinch" — that gesture stays on the comet bar itself.
    private func gesturePadRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rotateStepPt: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
                let touched = touchedPad[idx] == t.rawValue
                // RIFF ADVANCE (Paul 2026-10-06, toggle relocated 2026-10-07 — "I don't see the riff controls...
                // per lane"): once a lane's useRiff is on (via the now-visible `riffDirRow` below, NOT a hidden
                // tap on this pad — that was undiscoverable and has been removed), this ONE pad's label/tint
                // change to reflect the new role and its DRAG retargets to riffRotate/riffOctave instead of
                // noteSel/octave — "via the existing, relabelled note/octave control" still holds for the drag,
                // just not for the on/off switch anymore.
                let isRiffPad = t == .noteOctave && line.useRiffResolved
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(touched ? accent.opacity(0.35) : (isRiffPad ? accent.opacity(0.22) : Color.white.opacity(0.06)))
                    Text(isRiffPad ? "RIFF H/V" : t.label).font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(touched ? .black : .white.opacity(0.65))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5)
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
                            // EACH TAB gets its OWN HUD content (Paul 2026-10-06: "we need different overlays
                            // for velocity, gate, etc.") — three dedicated formatters, not one hardcoded to
                            // hits/offset. `euclidLaneDragHUDInfo` is the pre-existing, SHARED hits/offset
                            // formatter (also used by the regular BUILD-page editor); the other two are new,
                            // Euclideous-only (below) — the BUILD-page editor has no VEL/GATE or NOTE/OCT tab.
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

    /// The 3 DIRECTION buttons (Paul 2026-10-06) — short (not square), same 3 column widths as the gesture
    /// pads directly above, so the two rows line up. Left-to-right as asked: BACKWARDS · PING-PONG ·
    /// FORWARDS, glyphs "<" / "><" / ">" (the SAME convention the regular BUILD-page EUCLID editor's own
    /// DIRECTION control already uses — reused, not reinvented). A plain 3-way exclusive tap-to-select, not a
    /// drag pad — direction is a discrete choice, not a continuous X/Y target.
    private func directionRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let order: [(EuclidDir, String)] = [(.bkw, "<"), (.pingpong, "><"), (.fwd, ">")]
        return HStack(spacing: 0) {
            ForEach(order, id: \.0) { dir, glyph in
                let on = line.directionResolved == dir
                Text(glyph).font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6))
                    .frame(width: cellSize, height: rowH)
                    .background(on ? accent.opacity(0.55) : Color.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .onTapGesture { edit(idx) { $0.direction = dir } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// HIT | MISS | RATE (Paul 2026-10-06) — 3 columns matching the gesture-pad/direction rows above. HIT/MISS
    /// is a symmetric 2-way selector (see `missSelected`'s own doc comment) — tapping the NON-selected side
    /// performs the actual invert (`euclideousInvertLine`) and flips which one shows "selected"; tapping the
    /// already-selected side is a no-op. "The outline... to look selected" — SELECTED = an accent-coloured
    /// STROKE (matching `EuclidLaneBox`'s own `selected` convention exactly), not a filled background, so
    /// whichever side is currently selected visually reads the same way regardless of which it is — "the
    /// misses to appear like hits do now" IS this symmetry, not a separate treatment to build for misses only.
    /// RATE opens the pop-up (`ratePopupLane`); the button itself shows "—" when the line's rate is genuinely
    /// unset (nil ⇒ inherit the machine-wide rate) rather than silently defaulting the display to 1/16.
    private func hitMissRateRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, cellSize: CGFloat, rowH: CGFloat) -> some View {
        let missOn = idx < missSelected.count && missSelected[idx]
        func sideButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced))
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
            Text(line.rate == nil ? "—" : line.rate!.rawValue)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: cellSize, height: rowH)
                .background(Color.white.opacity(0.06))
                .contentShape(Rectangle())
                .onTapGesture { ratePopupLane = idx }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// RIFF DIRECTION, PER LANE (Paul 2026-10-07): OFF + all 6 `RiffDir` cases in ONE visible row — "the back/
    /// forward, drunk controls should be per lane, not on the riff control," replacing the earlier hidden tap-
    /// toggle on the NOTE/OCT pad. Picking a direction turns `useRiff` ON and sets it in a single tap (no
    /// separate enable step); picking OFF turns it off. One unified selector, not a toggle plus a picker.
    private func riffDirRow(_ idx: Int, _ line: EuclidLine, _ accent: Color, rowH: CGFloat) -> some View {
        let options: [RiffDir?] = [nil] + RiffDir.allCases   // nil = OFF
        return HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isOff = opt == nil
                let on = isOff ? !line.useRiffResolved : (line.useRiffResolved && line.riffDirResolved == opt)
                Text(isOff ? "OFF" : opt!.displayLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(on ? accent.opacity(0.7) : Color.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        edit(idx) {
                            if isOff { $0.useRiff = false } else { $0.useRiff = true; $0.riffDir = opt }
                        }
                    }
            }
        }
        .frame(height: rowH)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// The RATE pop-up card — an explicit "—" (inherit the machine-wide rate, nil) plus all 18 `ArpRate`
    /// cases grouped exactly as `ArpRate.allCases` already orders them (6 straight · 6 dotted · 6 triplet),
    /// one row per group. Picking any option closes the pop-up.
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

    /// Pure per-line mutation, shared by the single-lane and all-lanes paths below — HITS/OFFSET (default) →
    /// Δrotate; VELOCITY/GATE → Δvelocity (scaled); NOTE/OCTAVE → step the note-select cycle.
    private func applyX(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: line.rotate = ((line.rotate - d) % 16 + 16) % 16
        // SENSITIVITY (Paul 2026-10-07: "the velocity/gate controls need me to move my fingers way too far") —
        // tripled from 0.05/step so a full pad-width drag actually spans a meaningful fraction of VELOCITY's
        // 0...2 range, instead of needing several repeats of the same drag to get anywhere near the extremes.
        case .velocityGate: line.velocity = max(0, min(2, line.velocityResolved + Double(d) * 0.15))
        case .noteOctave:
            // RIFF ADVANCE (Paul 2026-10-06): once useRiff is on, this SAME pad's X-axis drives the lane's own
            // horizontal offset into the shared riff pattern instead of stepping noteSel — "replaces it
            // entirely". riffRotate is intentionally unbounded here (wrapped mod the riff's own step count at
            // READ time in Router.swift's `riffRotateStep`) — the same convention EUCLID's own `rotate` field
            // already uses (also unclamped at this layer, wrapped mod N in the engine).
            if line.useRiffResolved { line.riffRotate = line.riffRotateResolved + d }
            else { line.noteSel = euclideousStepNoteSel(line.noteSelResolved, by: d) }
        }
    }
    /// Pure per-line mutation — HITS/OFFSET → Δhits; VELOCITY/GATE → Δgate (scaled); NOTE/OCTAVE → Δoctave.
    private func applyY(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: let v = max(1, min(max(2, line.steps), line.pulses + d)); line.pulses = min(v, line.steps)   // floored at 1, not 0 (Paul 2026-10-06) — 0 hits is never meaningful here; `enabled: false` is the real mute
        // SENSITIVITY (Paul 2026-10-07, same complaint as VELOCITY above) — tripled from 0.03/step for the
        // same reason, scaled to GATE's narrower 0.05...1 range.
        case .velocityGate: line.gate = max(0.05, min(1, line.gateResolved + Double(d) * 0.09))
        case .noteOctave:
            // RIFF ADVANCE: Y-axis drives the lane's own vertical offset (riffOctave) into the shared pattern
            // instead of the plain octave shift, once useRiff is on — same ±3 clamp as octave's own.
            if line.useRiffResolved { line.riffOctave = max(-3, min(3, line.riffOctaveResolved + d)) }
            else { line.octave = max(-3, min(3, line.octaveResolved + d)) }
        }
    }
    private func euclideousApplyX(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyX(&$0, tab, d) } }
    private func euclideousApplyY(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) { edit(idx) { applyY(&$0, tab, d) } }
    // ALL-LANES (2-finger) variants — now genuinely TAB-AWARE, unlike the old comet-bar all-rows gesture it
    // replaces (that one was hard-coded to rotate/hits always, regardless of which tab happened to be
    // selected — a pre-existing limitation, never deliberately designed, that this redesign naturally fixes
    // as a side effect of each button now carrying its own explicit tab).
    private func euclideousApplyAllX(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyX(&lines[i], tab, d) } } }
    private func euclideousApplyAllY(_ tab: EuclideousGestureTab, _ d: Int) { onEdit { lines in for i in lines.indices { applyY(&lines[i], tab, d) } } }

    // THE OTHER TWO HUD FORMATTERS (Paul 2026-10-06: "we need different overlays for velocity, gate, etc.") —
    // Euclideous-only (the BUILD-page editor has no VEL/GATE or NOTE/OCT tab to show one for), mirroring
    // `euclidLaneDragHUDInfo`'s own (label, primary, secondary, point) shape exactly.
    private func euclideousVelGateHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                           primary: "VEL \(Int((line.velocityResolved * 100).rounded()))%",
                           secondary: "GATE \(Int((line.gateResolved * 100).rounded()))%", point: point)
    }
    private func euclideousNoteOctHUDInfo(idx: Int, line: EuclidLine, point: CGPoint, allRows: Bool) -> EuclidDragHUDInfo {
        let label = allRows ? "ALL LANES" : "LANE \(idx + 1)"
        // RIFF ADVANCE (Paul 2026-10-06): once this lane's useRiff is on, the pad's drag no longer moves noteSel/
        // octave at all — show the riff offsets it actually moves instead, branching the SAME formatter rather
        // than a separate one (there's nothing else distinguishing the two HUD shapes).
        if line.useRiffResolved {
            let rot = line.riffRotateResolved, oct = line.riffOctaveResolved
            return EuclidDragHUDInfo(label: label, primary: "RIFF ROT \(rot)", secondary: "RIFF OCT \(oct > 0 ? "+" : "")\(oct)", point: point)
        }
        let oct = line.octaveResolved
        return EuclidDragHUDInfo(label: label, primary: line.noteSelResolved.rawValue,
                                  secondary: "OCTAVE \(oct > 0 ? "+" : "")\(oct)", point: point)
    }

    // INV + RATE moved OUT of here (Paul 2026-10-06) — now `hitMissRateRow`, stacked directly beneath the
    // DIRECTION row inside EuclidLaneBox's own trailingContent. This row keeps just the 2 beacons + OUT.
    @ViewBuilder private func laneControls(_ idx: Int, _ line: EuclidLine, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EuclidBeacon(line: line, isMiss: false, accent: accent, clock: clock, rate: line.rate ?? .r1_16, spanN: 0,
                             isReady: (lineReady & UInt8(1 << (idx * 2))) != 0)
                EuclidBeacon(line: line, isMiss: true, accent: accent, clock: clock, rate: line.rate ?? .r1_16, spanN: 0,
                             isReady: (lineReady & UInt8(1 << (idx * 2 + 1))) != 0)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text("OUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                ForEach(0..<4, id: \.self) { b in
                    let mask = line.emitterMask ?? 0
                    let on = (mask >> UInt8(b)) & 1 != 0
                    Text(["A", "B", "C", "D"][b]).font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(on ? accent : Color.white.opacity(0.08)))
                        .onTapGesture { edit(idx) { $0.emitterMask = ($0.emitterMask ?? 0) ^ (1 << UInt8(b)) } }
                }
                Spacer(minLength: 0)
            }
        }
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
