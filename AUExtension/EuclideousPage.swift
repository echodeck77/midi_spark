//  EuclideousPage.swift
//  MidiSpark — EUCLIDEOUS (Paul 2026-10-05): a standalone, playable 4-lane EUCLID instrument.
//  Reuses the EXACT lane box/comet bar/gesture pad/beacon ProcessorBox's own EUCLID editor uses
//  (EuclidLaneUI.swift), sized generously to fill the screen rather than squeezed into a small
//  inline processor panel — "four Euclid lanes in the centre of the screen... a playable,
//  grabbable instrument." Presented as a plain overlay (DiagView's root ZStack), the same
//  mechanism CogPage uses (engine never stops), but NOT CogPage's small bounded-card sizing.
//  Foundation/SwiftUI/UIKit-only, same seam as every other GridUI/BuildPage file.

import SwiftUI

// EUCLIDEOUS INVERT (euclideousInvertLine/euclideousEnsureMissDefaults), the NOTE/OCTAVE cycle
// (euclideousNoteSelCycle/euclideousStepNoteSel), and the rate stepper (euclideousNextRate) all
// live in Derivations.swift (Paul 2026-10-05) — Foundation-only, so they reach the macOS
// unit-test target; this file only CALLS them.

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
    let clock: EuclidLiveClock
    let onEdit: (@escaping (inout [EuclidLine]) -> Void) -> Void
    let onToggleEnabled: () -> Void
    let onSetReceiver: (Int) -> Void
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
                // in tension the same way). Wrapped in a ScrollView since 2 rows of now-taller lanes may
                // exceed the screen height on some devices — scrolls rather than silently clipping.
                VStack(spacing: 0) {
                    header.padding(16)
                    ScrollView(.vertical, showsIndicators: false) {
                        laneGrid(geo.size.width).frame(maxWidth: .infinity, alignment: .center)
                    }
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
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("EUCLIDEOUS").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9))
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
        let euclidBoxH = 12 + cometRowH + gestureRowH + directionRowH
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
                                  gesturePadRow(idx, accent, cellSize: gestureRowH, rotateStepPt: rotateStepPt)
                                  directionRow(idx, line, accent, cellSize: gestureRowH, rowH: directionRowH)
                              }
                          ),
                          trailingHeight: gestureRowH + directionRowH)
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
    private func gesturePadRow(_ idx: Int, _ accent: Color, cellSize: CGFloat, rotateStepPt: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
                let touched = touchedPad[idx] == t.rawValue
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(touched ? accent.opacity(0.35) : Color.white.opacity(0.06))
                    Text(t.label).font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(touched ? .black : .white.opacity(0.65))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5)
                        .padding(4)
                }
                .frame(width: cellSize, height: cellSize)
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

    /// Pure per-line mutation, shared by the single-lane and all-lanes paths below — HITS/OFFSET (default) →
    /// Δrotate; VELOCITY/GATE → Δvelocity (scaled); NOTE/OCTAVE → step the note-select cycle.
    private func applyX(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: line.rotate = ((line.rotate - d) % 16 + 16) % 16
        case .velocityGate: line.velocity = max(0, min(2, line.velocityResolved + Double(d) * 0.05))
        case .noteOctave: line.noteSel = euclideousStepNoteSel(line.noteSelResolved, by: d)
        }
    }
    /// Pure per-line mutation — HITS/OFFSET → Δhits; VELOCITY/GATE → Δgate (scaled); NOTE/OCTAVE → Δoctave.
    private func applyY(_ line: inout EuclidLine, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: let v = max(1, min(max(2, line.steps), line.pulses + d)); line.pulses = min(v, line.steps)   // floored at 1, not 0 (Paul 2026-10-06) — 0 hits is never meaningful here; `enabled: false` is the real mute
        case .velocityGate: line.gate = max(0.05, min(1, line.gateResolved + Double(d) * 0.03))
        case .noteOctave: line.octave = max(-3, min(3, line.octaveResolved + d))
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
        let oct = line.octaveResolved
        return EuclidDragHUDInfo(label: allRows ? "ALL LANES" : "LANE \(idx + 1)",
                                  primary: line.noteSelResolved.rawValue,
                                  secondary: "OCTAVE \(oct > 0 ? "+" : "")\(oct)", point: point)
    }

    @ViewBuilder private func laneControls(_ idx: Int, _ line: EuclidLine, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("INV").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
                    .onTapGesture { edit(idx) { $0 = euclideousInvertLine($0) } }
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
                Spacer(minLength: 6)
                Text("RATE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                Text((line.rate ?? .r1_16).rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    .onTapGesture { edit(idx) { $0.rate = euclideousNextRate($0.rate ?? .r1_16) } }
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
