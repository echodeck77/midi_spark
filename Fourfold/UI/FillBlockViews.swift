//  FillBlockViews.swift — FILL ferry (2026-11-13) §4.3/§6.3: a FILL value tile (SPEED · LENGTH · RANKS · SWELL),
//  drawn like OFFSET (the MIX v2 field look), with the discrete-value drag / tap-halves / double-tap reset.

import SwiftUI

/// Drawn as OFFSET draws (§4.3): an opaque ground, OFFSET's ticks, a lane-coloured value edge (RANKS/SWELL add TILT's
/// centre line), the label top-leading and the value bottom-trailing on their own backings. A horizontal drag steps
/// through the values by absolute position (OFFSET's drag); a tap on the leading/trailing half steps toward that end
/// (§6.3); a double tap resets to the §1.1 default. One undo step per drag (`onStep`); a tap / reset is its own step (`onTap`).
///
/// §6.3 conflict, DISCLOSED: a double tap also lands one tap-half first (the reset then wins) — the halves are kept, per the spec.
struct EuclideousFillFieldTile: View {
    let field: EuclideousFillField
    let line: EuclidLine
    let accent: Color
    let size: CGSize
    let radius: CGFloat
    let onStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void
    let onTap: (@escaping (inout EuclidLine) -> Void) -> Void
    @State private var dragged = false
    private let inset: CGFloat = 6

    var body: some View {
        typealias F = EuclideousMixV2FieldLook
        let frac = euclideousFillFieldFraction(field, line)
        let text = euclideousFillFieldValueText(field, line)
        let travel = max(1, size.width - inset * 2)
        let edgeX = inset + CGFloat(frac) * travel
        return ZStack {
            Canvas { ctx, sz in
                let shape = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: radius)
                ctx.fill(shape, with: .color(Color(hex: F.groundHex)))
                var c = ctx; c.clip(to: shape)
                for tf in euclideousMixV2FieldTickFracs {
                    let x = inset + CGFloat(tf) * travel
                    c.fill(Path(CGRect(x: x - F.tickW / 2, y: sz.height - F.tickH, width: F.tickW, height: F.tickH)), with: .color(Color(hex: F.tickHex)))
                }
                if field.bipolar {   // §4.3 TILT's centre line
                    let mid = inset + 0.5 * travel
                    c.fill(Path(CGRect(x: mid - 0.5, y: 0, width: 1, height: sz.height)), with: .color(Color(hex: 0x3A3E47)))
                }
                c.fill(Path(CGRect(x: edgeX - F.edge / 2, y: 0, width: F.edge, height: sz.height)), with: .color(accent))
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
        .contentShape(Rectangle())
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
