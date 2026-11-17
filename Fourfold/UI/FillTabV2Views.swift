//  FillTabV2Views.swift — FILL TAB V2 (2026-11-17) §3.8/§3.9/§4/§5: the tab's SwiftUI leaves — the segmented tiles
//  (labels or glyphs), the steppers (tap steps, hold repeats 0.4 s then 0.12 s, double-tap resets), the toggles, the
//  FILL and LOOP tiles, and the glyph Shape. Every frame, text, look-state and VoiceOver string comes from the pure
//  layer in FillTabV2.swift; lane colour appears only where §5 says it does. GEOMETRY + LOOKS DEVICE-OWED.

import SwiftUI

/// §3.7 — the roll row's per-lane prediction cache. Plain (non-published) storage: the page fills it during a draw when
/// the key changes (a setting, a bar line via the cycle, a cycle move) and the 30 fps TimelineView only re-reads it.
final class EuclideousFillV2RollMemo: ObservableObject {
    struct Entry { var key: UInt64 = 0; var bars: [EuclideousFillRollBar] = []; var lo = 55; var hi = 67; var cycleStart = 0 }
    var entries: [Int: Entry] = [:]
}

// MARK: - §5 the shared looks

enum EuclideousFillV2Look {
    static let segIdle: UInt32 = 0x22242A       // §5.1 unselected fill
    static let segIdleText: UInt32 = 0x8A909A
    static let segNeutral: UInt32 = 0x4A4D57    // §5.1 selected, neutral value
    static let segSelectedText: UInt32 = FourfoldStyle.selectedInk   // STYLE PASS 1 §3.1: ink on the selected fill (was #F2F4F7)
    static let stepButton: UInt32 = 0x22242A    // §4.4 − / + ground
    static let stepButtonText: UInt32 = 0xC9CDD5
    static let labelText: UInt32 = FourfoldStyle.key     // STYLE PASS 1 §4.1 tile KEY (was #AAB0BA)
}

/// §4.3 the ORDER / RANKS glyphs as a Shape (the 24-unit box scaled into the rect; round caps and joins, 1.1 pt stroke).
struct EuclideousFillV2GlyphShape: Shape {
    let glyph: EuclideousFillV2Glyph
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        for sub in glyph.subpaths {
            guard let first = sub.first else { continue }
            p.move(to: CGPoint(x: ox + first.x * s, y: oy + first.y * s))
            for pt in sub.dropFirst() { p.addLine(to: CGPoint(x: ox + pt.x * s, y: oy + pt.y * s)) }
        }
        return p
    }
}

/// §4.2 — the control tile's ground + top-leading label (6 pt heavy, 0.12 em, #AAB0BA, 6 in). No lane colour on the tile itself.
struct EuclideousFillV2Tile<Content: View>: View {
    let label: String
    let size: CGSize
    let radius: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius).fill(Color(hex: EuclideousMixV2FieldLook.groundHex))
            Text(label).font(.system(size: 6, weight: .medium, design: .monospaced)).tracking(6 * 0.12)
                .foregroundColor(Color(hex: EuclideousFillV2Look.labelText))
                .padding(.top, 6).padding(.leading, 6)
                .allowsHitTesting(false)
            content
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One §4.3 segment's background + border per §5.1 (the rate grid's selected look when non-neutral).
struct EuclideousFillV2SegBack: View {
    let selected: Bool
    let neutral: Bool
    let accent: Color
    var body: some View {
        // STYLE PASS 1 §3.1: ONE selected look — the neutral/non-neutral split collapses (both draw #DFE3EA) and the
        // lane border goes (was segNeutral/lane20 + a lane border on non-neutral; FILL V2 §5's lane rule is superseded here).
        RoundedRectangle(cornerRadius: EuclideousFillV2Metrics.segRadius)
            .fill(selected ? Color(hex: FourfoldStyle.selectedFill) : Color(hex: EuclideousFillV2Look.segIdle))
    }
}

/// §4.3 — a segmented control (labels or ORDER's glyphs) inside its tile. A tap selects; nothing if already selected; one undo step.
struct EuclideousFillV2SegmentedTile: View {
    let seg: EuclideousFillV2Seg
    let line: EuclidLine
    let accent: Color
    let size: CGSize
    let radius: CGFloat
    let onSelect: (Int) -> Void
    var body: some View {
        let row = euclideousFillV2SegRow(tileSize: size)
        let frames = euclideousFillV2SegFrames(row: row, count: seg.count)
        let selected = euclideousFillV2SegIndex(seg, line)
        let orderGlyphs: [EuclideousFillV2Glyph] = [.fwd, .rev, .fwd /*bounce = EUCLID's icon*/, .shuffle, .stutter]
        return EuclideousFillV2Tile(label: seg.label, size: size, radius: radius) {
            ForEach(0..<seg.count, id: \.self) { i in
                let isSel = i == selected
                let neutral = euclideousFillV2SegIsNeutral(seg, index: i)
                ZStack {
                    EuclideousFillV2SegBack(selected: isSel, neutral: neutral, accent: accent)
                    if seg == .order {
                        let stroke = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                        let tint = Color(hex: isSel ? EuclideousFillV2Look.segSelectedText : EuclideousFillV2Look.segIdleText)
                        if i == 2 {   // BOUNCE: EUCLID's own ping-pong icon (the spec's reuse clause)
                            EuclideousPage.RiffDirectionIcon(kind: .pingpong).stroke(tint, style: stroke).frame(width: 11, height: 11)
                        } else if i == 0 {
                            EuclideousPage.RiffDirectionIcon(kind: .forward).stroke(tint, style: stroke).frame(width: 11, height: 11)
                        } else if i == 1 {
                            EuclideousPage.RiffDirectionIcon(kind: .backward).stroke(tint, style: stroke).frame(width: 11, height: 11)
                        } else {
                            EuclideousFillV2GlyphShape(glyph: orderGlyphs[i]).stroke(tint, style: stroke).frame(width: 11, height: 11)
                        }
                    } else {
                        Text(seg.segTexts[i])
                            .font(.system(size: seg.textSize, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(hex: isSel ? EuclideousFillV2Look.segSelectedText : EuclideousFillV2Look.segIdleText))
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                }
                .frame(width: frames[i].width, height: frames[i].height)
                .contentShape(Rectangle())   // HIT REGION FIX (2026-11-17): contentShape + the tap MUST precede .position — after it, .position expands the view to fill the tile and the hit area becomes the WHOLE tile, so the last-drawn segment swallows every tap (tap FLIP → BUILD). Gesture-before-position, per the SwiftUI rule.
                .onTapGesture { if i != selected { onSelect(i) } }
                .position(x: frames[i].midX, y: frames[i].midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(euclideousFillV2SegAX(seg, index: i))
                .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// §4.4 — a − / + stepper button: a tap steps once; holding repeats after 0.4 s every 0.12 s (ONE undo step per hold).
struct EuclideousFillV2StepButton: View {
    let text: String
    let frame: CGRect
    let axLabel: String
    /// `first` true on the press's first step (the undo burst's opener), false on every repeat.
    let onStep: (Bool) -> Void
    @State private var repeater: Task<Void, Never>? = nil
    @State private var down = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(Color(hex: EuclideousFillV2Look.stepButtonText))
            .frame(width: frame.width, height: frame.height)
            .background(RoundedRectangle(cornerRadius: EuclideousFillV2Metrics.segRadius).fill(Color(hex: EuclideousFillV2Look.stepButton).opacity(down ? 0.6 : 1)))
            .contentShape(Rectangle())   // HIT REGION FIX (2026-11-17): contentShape + gesture MUST precede .position (same as the segmented tile) — else .position fills the row and the two steppers overlap, one swallowing both taps
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true
                    onStep(true)
                    repeater = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        while !Task.isCancelled {
                            onStep(false)
                            try? await Task.sleep(nanoseconds: 120_000_000)
                        }
                    }
                }
                .onEnded { _ in down = false; repeater?.cancel(); repeater = nil })
            .position(x: frame.midX, y: frame.midY)
            .onDisappear { repeater?.cancel(); repeater = nil; down = false }
            .accessibilityHidden(true)   // the stepper's value box is the adjustable element (§8.3)
    }
}

/// §4.5 — a whole-tile toggle (RUSH / BREAK / LAND): off = the tile's own look + #C9CDD5; on = the rate grid's selected look.
struct EuclideousFillV2ToggleTile: View {
    let label: String
    let on: Bool
    let accent: Color
    let size: CGSize
    let radius: CGFloat
    let axLabel: String
    let onTap: () -> Void
    var body: some View {
        Text(label).font(.system(size: 6.5, weight: .heavy, design: .monospaced)).tracking(6.5 * 0.12)
            .foregroundColor(Color(hex: FourfoldSelect.switchInk(on)))   // STYLE PASS 1 §3.2 (was segSelectedText/stepButtonText)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: radius).fill(Color(hex: FourfoldSelect.switchFill(on))))   // §3.2: no border (was lane20 + lane border)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// §3.9 — LOOP: neutral in every state. "LOOP" 5.5 pt over the value 8.5 pt; a tap cycles 4 → 8 → 16 → 4.
struct EuclideousFillV2LoopTile: View {
    let loop: Int
    let size: CGSize
    let radius: CGFloat
    let onTap: () -> Void
    var body: some View {
        VStack(spacing: 1) {
            Text("LOOP").font(.system(size: 5.5, weight: .heavy, design: .monospaced)).tracking(5.5 * 0.14).foregroundColor(Color(hex: 0x8A909A))
            Text("\(loop)").font(.system(size: 8.5, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: radius).fill(Color(hex: EuclideousMixV2FieldLook.groundHex)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousFillV2LoopAX(loop))
        .accessibilityAddTraits(.isButton)
    }
}
