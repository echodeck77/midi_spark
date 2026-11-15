//  FillBlockViews.swift — FILL ferry (2026-11-13) §4.3/§6.3: a FILL value tile (SPEED · LENGTH · RANKS · SWELL · ROLL ·
//  CHANCE), drawn like OFFSET (the MIX v2 field look), with the discrete-value drag / tap-halves / double-tap reset.
//  FILL TAB ferry (2026-11-14): ROLL / CHANCE value tiles, the §4.3 bipolar fix (#4A4E57 centre line always, the value
//  edge at 35 % when the value is 0), a notched content shape so a curve/shape CHIP's corner is its own hit area (§4.4),
//  and the ORDER / HITS selector tiles, the LAND toggle, the mode chip and the loop chip (§4.5/§4.6/§5.4).

import SwiftUI

/// Drawn as OFFSET draws (§4.3): an opaque ground, OFFSET's ticks, a lane-coloured value edge (RANKS/SWELL add TILT's
/// centre line), the label top-leading and the value bottom-trailing on their own backings. A horizontal drag steps
/// through the values by absolute position (OFFSET's drag); a tap on the leading/trailing half steps toward that end
/// (§6.3); a double tap resets to the §1.1 default. One undo step per drag (`onStep`); a tap / reset is its own step (`onTap`).
///
/// §4.4: `excludeCorner` notches a top-trailing `cw × ch` corner out of the hit area so a curve/shape chip drawn there
/// owns its own taps. §6.3 conflict, DISCLOSED: a double tap also lands one tap-half first (the reset then wins).
struct EuclideousFillFieldTile: View {
    let field: EuclideousFillField
    let line: EuclidLine
    let accent: Color
    let size: CGSize
    let radius: CGFloat
    var excludeCorner: CGSize? = nil
    let onStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void
    let onTap: (@escaping (inout EuclidLine) -> Void) -> Void
    @State private var dragged = false
    private let inset: CGFloat = 6

    /// The hit area: the tile rect, with a top-trailing corner notched out when a chip lives there (§4.4).
    private var hitShape: Path {
        var p = Path()
        guard let c = excludeCorner else { p.addRect(CGRect(origin: .zero, size: size)); return p }
        let cw = min(size.width, c.width), ch = min(size.height, c.height)
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: size.width - cw, y: 0))
        p.addLine(to: CGPoint(x: size.width - cw, y: ch))
        p.addLine(to: CGPoint(x: size.width, y: ch))
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    var body: some View {
        typealias F = EuclideousMixV2FieldLook
        let frac = euclideousFillFieldFraction(field, line)
        let text = euclideousFillFieldValueText(field, line)
        let travel = max(1, size.width - inset * 2)
        let edgeX = inset + CGFloat(frac) * travel
        let atZero = field.bipolar && abs(frac - 0.5) < 1e-6   // §4.3: a bipolar field at 0 draws its value edge faint so it doesn't read as a set value
        return ZStack {
            Canvas { ctx, sz in
                let shape = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: radius)
                ctx.fill(shape, with: .color(Color(hex: F.groundHex)))
                var c = ctx; c.clip(to: shape)
                for tf in euclideousMixV2FieldTickFracs {
                    let x = inset + CGFloat(tf) * travel
                    c.fill(Path(CGRect(x: x - F.tickW / 2, y: sz.height - F.tickH, width: F.tickW, height: F.tickH)), with: .color(Color(hex: F.tickHex)))
                }
                if field.bipolar {   // §4.3 TILT's centre line, now #4A4E57 and always drawn
                    let mid = inset + 0.5 * travel
                    c.fill(Path(CGRect(x: mid - 0.5, y: 0, width: 1, height: sz.height)), with: .color(Color(hex: 0x4A4E57)))
                }
                c.fill(Path(CGRect(x: edgeX - F.edge / 2, y: 0, width: F.edge, height: sz.height)), with: .color(accent.opacity(atZero ? 0.35 : 1)))
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(field.label).font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(7 * 0.08).foregroundColor(Color(hex: F.labelHex)).lineLimit(1)
                        .padding(.horizontal, 3).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: F.groundHex)))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(text).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: F.valueHex)).lineLimit(1)
                        .padding(.horizontal, 3).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: F.valueBackingRadius).fill(Color(hex: F.valueBackingHex).opacity(F.valueBackingAlpha)))
                }
            }.padding(.horizontal, 4).padding(.vertical, 2).allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(hitShape)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if abs(v.translation.width) > 4 || dragged {
                    let fx = Double((v.location.x - inset) / travel)
                    onStep(!dragged) { euclideousFillSetFieldIndex(field, euclideousFillFieldDragIndex(field, fracX: fx), &$0) }
                    dragged = true
                }
            }
            .onEnded { v in
                if !dragged {
                    let fx = Double(v.location.x / max(1, size.width))
                    onTap { euclideousFillSetFieldIndex(field, euclideousFillFieldTapStep(field, line, fracX: fx), &$0) }
                }
                dragged = false
            })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onTap { euclideousFillSetFieldIndex(field, field.defaultIndex, &$0) } })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousFillFieldAX(field, line))
        .accessibilityAdjustableAction { dir in
            onTap { euclideousFillSetFieldIndex(field, euclideousFillFieldIndex(field, line) + (dir == .increment ? 1 : -1), &$0) }
        }
    }
}

/// §4.4 the curve / shape mini chip (a 13 pt top-trailing rounded square on SPEED / RANKS): lit when active, a tap cycles.
struct EuclideousFillChip: View {
    let text: String
    let lit: Bool
    let accent: Color
    let size: CGSize
    let axLabel: String
    let onTap: () -> Void
    var body: some View {
        Text(text).font(.system(size: 5.5, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundColor(lit ? Color(hex: 0x0D0F14) : Color(hex: 0xAAB0BA))
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? accent : Color(hex: 0x2A2D34)))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore).accessibilityLabel(axLabel).accessibilityAddTraits(.isButton)
    }
}

/// §4.5 a SELECTOR tile (ORDER / HITS): the label top-leading, the current value centred; a tap cycles, a double tap
/// resets. `enabled` false dims it and ignores taps (used for HITS while ALL/FLIP are not yet wired in the engine).
struct EuclideousFillSelectorTile: View {
    let selector: EuclideousFillSelector
    let line: EuclidLine
    let accent: Color
    let size: CGSize
    let radius: CGFloat
    var enabled: Bool = true
    let onTap: (@escaping (inout EuclidLine) -> Void) -> Void
    var body: some View {
        typealias F = EuclideousMixV2FieldLook
        let value = euclideousFillSelectorText(selector, line)
        return ZStack {
            RoundedRectangle(cornerRadius: radius).fill(Color(hex: F.groundHex))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(selector.label).font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(7 * 0.08).foregroundColor(Color(hex: F.labelHex)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                Text(value).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: F.valueHex)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }.padding(.horizontal, 4).padding(.vertical, 2).allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { onTap { euclideousFillCycleSelector(selector, &$0) } } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if enabled { onTap { euclideousFillResetSelector(selector, &$0) } } })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousFillSelectorAX(selector, line) + (enabled ? "" : ", not yet active"))
        .accessibilityAddTraits(.isButton)
    }
}

/// §5.4 the loop chip — cycles the fill loop length 4 → 8 → 16.
struct EuclideousFillLoopChip: View {
    let loop: Int
    let accent: Color
    let size: CGSize
    let onTap: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Text("LOOP").font(.system(size: 5, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
            Text("\(loop)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x22252C)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.45), lineWidth: 1)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore).accessibilityLabel("Fill loop, \(loop) bars").accessibilityAddTraits(.isButton)
    }
}
