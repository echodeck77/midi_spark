//  PolyRiffGridPainter.swift
//  POLY RIFF ferry (2026-10-29), slice 2: the POLY grid's picture — sixteen columns by eight ranks drawn in ONE Canvas (128 cell views would be a stack-budget and frame-time cost for nothing), notes as bars across the columns they cover.
//  Every frame comes from `EuclideousRiffPanelLayout` (`euclideousPolyPanelLayout`); this file decides nothing but colours. SwiftUI-only on purpose (GridUI seam rule).

import SwiftUI

struct EuclideousPolyGridView: View {
    let riff: EuclideousPolyRiff
    let layout: EuclideousRiffPanelLayout

    /// Cell and note looks: the MONO grid's own (an empty cell is white at 8 % with a 12 % border; a note is white at 85 %). A note's tail cells are dimmer, so the head — where it STRIKES — reads at a glance.
    private enum Look {
        static let empty = Color.white.opacity(0.08), border = Color.white.opacity(0.12)
        static let head = Color.white.opacity(0.88), tail = Color.white.opacity(0.5)
        static let radius: CGFloat = 2.5
    }

    var body: some View {
        let l = layout
        let gridW = l.gridSize.width, gridH = l.gridSize.height
        let notes = riff.normalized.notes
        return Canvas { ctx, _ in
            let x0 = l.columnLeft(0)
            let y0 = l.rowTop(0)
            for rank in 1...8 {
                for col in 0..<l.columns {
                    let f = l.cellFrame(column: col, rank: rank).offsetBy(dx: -x0, dy: -y0)
                    let p = Path(roundedRect: f, cornerRadius: Look.radius)
                    ctx.fill(p, with: .color(Look.empty))
                    ctx.stroke(p, with: .color(Look.border), lineWidth: 1)
                }
            }
            for n in notes {
                let head = l.cellFrame(column: n.col, rank: n.rank).offsetBy(dx: -x0, dy: -y0)
                if n.len > 1 {
                    let tailEnd = l.cellFrame(column: n.col + n.len - 1, rank: n.rank).offsetBy(dx: -x0, dy: -y0)
                    let bar = CGRect(x: head.minX, y: head.minY, width: tailEnd.maxX - head.minX, height: head.height)
                    ctx.fill(Path(roundedRect: bar, cornerRadius: Look.radius), with: .color(Look.tail))
                }
                ctx.fill(Path(roundedRect: head, cornerRadius: Look.radius), with: .color(Look.head))
            }
        }
        .frame(width: gridW, height: gridH)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the cells are spoken by `PolyRiffCellAccessibility` below; this is paint only
    }
}
