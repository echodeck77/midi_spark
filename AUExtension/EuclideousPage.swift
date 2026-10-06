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

/// One lane's 3 gesture tabs — the X/Y drag retargets per the active tab. HITS/OFFSET is the
/// default and exactly matches the EXISTING EuclidGesturePad mapping (X=rotate, Y=hits); the
/// other two tabs reinterpret the SAME `(Int) -> Void` callback slots `EuclidLaneBox`/
/// `EuclidGesturePad` already expose — no changes needed to either, since their callback type was
/// already a bare, meaning-free `(Int) -> Void` (confirmed during planning).
enum EuclideousGestureTab: Int, CaseIterable { case hitsOffset = 0, velocityGate = 1, noteOctave = 2
    var label: String { switch self { case .hitsOffset: "HITS/OFFS"; case .velocityGate: "VEL/GATE"; case .noteOctave: "NOTE/OCT" } }
}

struct EuclideousPage: View {
    let lines: [EuclidLine]
    let enabled: Bool
    let receiver: Int
    @Binding var gestureTab: [Int]
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
                // LAYOUT (Paul 2026-10-06): each lane control is exactly 1/4 the SCREEN's own width/height
                // (computed from `geo.size`, the full page geometry — not the space left over after the
                // header), and the resulting 2×2 block is CENTRED — both axes — in whatever space remains
                // below the header. The header keeps its own fixed padding/position; `laneGrid` expands to
                // fill the rest and centers its (now fixed, smaller-than-before) natural-sized content
                // within that via `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
                VStack(spacing: 0) {
                    header.padding(16)
                    laneGrid(geo.size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private func laneGrid(_ size: CGSize) -> some View {
        let gap: CGFloat = 12
        // QUARTER-SCREEN SIZING (Paul 2026-10-06): "each Euclid lane control to be 1 quarter width and
        // quarter height of the screen" — a LITERAL quarter of the full page geometry, not the space left
        // over after padding/gaps are subtracted (the previous formula's own approach). `gap` is extra
        // breathing room BETWEEN the 4 cards, on top of their exact quarter sizes, not stolen from them —
        // so the full 2×2 block is slightly LARGER than exactly half the screen in each dimension, by `gap`.
        let cellW = size.width / 4
        let cellH = size.height / 4
        return VStack(spacing: gap) {
            HStack(spacing: gap) { laneCard(0, width: cellW, height: cellH); laneCard(1, width: cellW, height: cellH) }
            HStack(spacing: gap) { laneCard(2, width: cellW, height: cellH); laneCard(3, width: cellW, height: cellH) }
        }
    }

    @ViewBuilder private func laneCard(_ idx: Int, width: CGFloat, height: CGFloat) -> some View {
        let line = idx < lines.count ? lines[idx] : EuclidLine(noteSel: .all)   // defensive fallback only — `lines` is always exactly 4 via euclideousLinesResolved
        let accent = laneAccents[idx % laneAccents.count]
        let tab = EuclideousGestureTab(rawValue: idx < gestureTab.count ? gestureTab[idx] : 0) ?? .hitsOffset
        VStack(alignment: .leading, spacing: 8) {
            // TAB SELECTOR INSIDE THE LANE BOX (Paul 2026-10-06): passed as EuclidLaneBox's own `trailingContent`
            // so it renders inside THAT box's border/background, directly below the play+comet row — "the same
            // control as the Euclid lane, not a separate box" — rather than floating in laneControls below it.
            // HEIGHT BUDGET (Paul 2026-10-06, "the rate button doesn't respond to touch"): laneControls below
            // needs at least 70pt, not 60 — 16 (outer .padding(8)×2) + 8 (this VStack's own spacing) + 46
            // (laneControls' own 2 remaining rows: 22 INV/beacon + 6 internal spacing + 18 OUT/RATE) = 70. The
            // prior -60 under-reserved by exactly 10pt (a miscalculation from the tab-row-merge change, which
            // moved one row OUT of laneControls and INTO EuclidLaneBox's own budget but recomputed the external
            // split wrong) — the overflow pushed laneControls' last row (OUT/RATE, where the RATE chip lives)
            // past this card's own nominal bottom edge, into the lane card BELOW it in the 2×2 grid, which —
            // declared later in the VStack — wins hit-testing in the overlapping region: taps on RATE were
            // landing on whatever was actually on top there, not the RATE chip underneath it, reading as
            // "doesn't respond to touch." -76 (a few pt of margin over the bare 70 minimum, matching the
            // pre-merge code's own slack rather than computing to the exact byte).
            EuclidLaneBox(idx: idx, line: line, width: width, height: max(80, height - 76), accent: accent,
                          selected: selectedLane == idx, touched: allRowsTouched || singleTouchedLanes.contains(idx),
                          clock: clock, rate: line.rate ?? .r1_16, spanN: 0,   // SPAN stays machine-wide/free-run — a deliberate V1 scope limit, not asked for per-lane
                          onRotateDelta: { d in euclideousApplyX(idx, tab, d) },
                          onHitsDelta: { d in euclideousApplyY(idx, tab, d) },
                          onStepsDelta: { d in edit(idx) { let v = max(2, min(16, $0.steps + d)); $0.steps = v; if $0.pulses > v { $0.pulses = v } } },
                          onAllRotateDelta: { d in onEdit { lines in for i in lines.indices { lines[i].rotate = ((lines[i].rotate - d) % 16 + 16) % 16 } } },
                          onAllHitsDelta: { d in onEdit { lines in for i in lines.indices { let v = max(1, min(max(2, lines[i].steps), lines[i].pulses + d)); lines[i].pulses = min(v, lines[i].steps) } } },   // floored at 1, matching euclideousApplyY
                          onDragState: { point, allRows in
                              if point == nil { if allRows { allRowsTouched = false } else { singleTouchedLanes.remove(idx) } }
                              else { if allRows { allRowsTouched = true } else { singleTouchedLanes.insert(idx) } }
                              guard let point else { dragHUDInfo = nil; return }
                              if !allRows { selectedLane = idx }
                              dragHUDInfo = euclidLaneDragHUDInfo(idx: idx, line: line, point: point, allRows: allRows)
                          },
                          onSelect: { selectedLane = idx },
                          onToggleEnabled: { edit(idx) { $0.enabled = !($0.enabledResolved) } },
                          trailingContent: AnyView(gestureTabRow(idx, tab, accent)), trailingHeight: 22)
            laneControls(idx, line, accent: accent)
        }
        .padding(8)
        .frame(width: width, height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
    }

    /// The 3-way HITS/OFFS · VEL/GATE · NOTE/OCT selector — factored out so it can be handed to
    /// `EuclidLaneBox` as `trailingContent` (rendering inside the lane's own box) instead of living
    /// in `laneControls` (a separate, unbordered area below it).
    private func gestureTabRow(_ idx: Int, _ tab: EuclideousGestureTab, _ accent: Color) -> some View {
        HStack(spacing: 6) {
            ForEach(EuclideousGestureTab.allCases, id: \.rawValue) { t in
                let on = tab == t
                Text(t.label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.55))
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.08)))
                    .onTapGesture { if idx < gestureTab.count { gestureTab[idx] = t.rawValue } }
            }
            Spacer(minLength: 0)
        }
    }

    /// Retargets the gesture pad's X-axis delta per the lane's own active tab — HITS/OFFSET (default,
    /// unchanged) → Δrotate; VELOCITY/GATE → Δvelocity (scaled); NOTE/OCTAVE → step the note-select cycle.
    private func euclideousApplyX(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: edit(idx) { $0.rotate = (($0.rotate - d) % 16 + 16) % 16 }
        case .velocityGate: edit(idx) { $0.velocity = max(0, min(2, $0.velocityResolved + Double(d) * 0.05)) }
        case .noteOctave: edit(idx) { $0.noteSel = euclideousStepNoteSel($0.noteSelResolved, by: d) }
        }
    }
    /// Retargets the gesture pad's Y-axis delta — HITS/OFFSET → Δhits; VELOCITY/GATE → Δgate (scaled);
    /// NOTE/OCTAVE → Δoctave.
    private func euclideousApplyY(_ idx: Int, _ tab: EuclideousGestureTab, _ d: Int) {
        switch tab {
        case .hitsOffset: edit(idx) { let v = max(1, min(max(2, $0.steps), $0.pulses + d)); $0.pulses = min(v, $0.steps) }   // floored at 1, not 0 (Paul 2026-10-06) — 0 hits is never meaningful here; `enabled: false` is the real mute
        case .velocityGate: edit(idx) { $0.gate = max(0.05, min(1, $0.gateResolved + Double(d) * 0.03)) }
        case .noteOctave: edit(idx) { $0.octave = max(-3, min(3, $0.octaveResolved + d)) }
        }
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
            Text("\(info.hits) HITS OUT OF \(info.steps)")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text("OFFSET BY \(info.offset)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }
}
