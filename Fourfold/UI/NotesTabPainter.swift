//  NotesTabPainter.swift
//  The NOTES tab's keys, way previews, PLAY AS button and picker (ferry "NOTES tab rebuilt: octave and velocity go, WHEN RIFF, seven ways to PLAY AS, CHANCE and RECEIVED; FILL leaves ON REST", 2026-10-19).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `LanesPanelPainter.swift` / `FXPanelPainter.swift`: every frame comes from `euclideousNotesTabLayout`, every
//  preview bar from `euclideousNotesPreviewBars`, every place number from `euclideousNotesPlaceNumbers` (Derivations.swift), so the drawing and the tests can never disagree. This file paints what
//  those return. It keeps no state; the page owns the lit order, the pool and the edits (one undo step each).

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }
private func boldMono(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }

enum EuclideousNotesPalette {
    static let ink = Color(h: 0xF2F4F7)
    static let dim = Color(h: 0xAAB0BA)
    static let key = Color(h: 0x8A909A)
    static let button = Color(h: 0x2A2D34)
    static let riffDot = Color(h: 0xDFE3EA)
    static let pickerFill = Color(h: 0x1B1D23)
    static let pickerOutline = Color(h: 0x2E3138)
    static let previewColumn = Color(h: 0x1F2228)
    static let cellPreviewColumn = Color(red: 13.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, opacity: 0.35)
}

// MARK: - the keys (§2)

// MARK: - the previews (§3.3, §4.4)

/// A row of `columns` previews: column c shows the notes of the way for k = c, as bars in the pool rank row each note sits in (rank 8 at the top).
struct EuclideousNotesPreviewView: View, Equatable {
    let list: EuclideousNotesList
    let way: EuclidNotesPlayAs
    let columns: Int
    let columnGap: CGFloat
    let columnPad: CGFloat
    let rowGap: CGFloat
    let columnFill: Color
    let accent: Color
    var body: some View {
        Canvas { ctx, size in
            let n = max(1, columns)
            let colW = (size.width - CGFloat(n - 1) * columnGap) / CGFloat(n)
            let innerW = max(0, colW - 2 * columnPad), innerH = max(0, size.height - 2 * columnPad)
            let rowH = (innerH - 7 * rowGap) / 8
            for c in 0..<n {
                let colX = CGFloat(c) * (colW + columnGap)
                ctx.fill(Path(roundedRect: CGRect(x: colX, y: 0, width: colW, height: size.height), cornerRadius: 3), with: .color(columnFill))
                for bar in euclideousNotesPreviewBars(list: list, way: way, k: c) {
                    let rowFromTop = 8 - bar.rank
                    let y = columnPad + CGFloat(rowFromTop) * (rowH + rowGap)
                    let rect = CGRect(x: colX + columnPad + CGFloat(bar.x) * innerW, y: y, width: CGFloat(bar.w) * innerW, height: rowH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(accent))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - the PLAY AS button (§3.3)

struct EuclideousNotesPlayAsButtonView: View, Equatable {
    let way: EuclidNotesPlayAs
    let list: EuclideousNotesList
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(way.rawValue).font(heavyMono(12)).foregroundColor(EuclideousNotesPalette.ink).lineLimit(1).frame(height: 16)
                Path { p in
                    p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 4, y: 4)); p.addLine(to: CGPoint(x: 7, y: 1))
                }
                .stroke(EuclideousNotesPalette.key, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 5)
            }
            .frame(width: 58, alignment: .leading)
            EuclideousNotesPreviewView(list: list, way: way, columns: 8, columnGap: 1.5, columnPad: 2, rowGap: 0.6, columnFill: EuclideousNotesPalette.previewColumn, accent: accent)
        }
        .padding(.top, 4).padding(.bottom, 4).padding(.leading, 10).padding(.trailing, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(EuclideousNotesPalette.button))
    }
}

// MARK: - the picker (§4)

struct EuclideousNotesPickerView: View {
    let layout: EuclideousNotesTabLayout
    let current: EuclidNotesPlayAs
    let list: EuclideousNotesList
    let accent: Color
    let onChoose: (EuclidNotesPlayAs) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(EuclideousNotesPalette.pickerFill)
            RoundedRectangle(cornerRadius: 10).strokeBorder(EuclideousNotesPalette.pickerOutline, lineWidth: 1)
            // header: "PLAY AS · YOUR LIT NOTES, HIT BY HIT" with a 4 pt left inset, then the close button at the trailing edge
            (Text("PLAY AS").font(heavyMono(9)).kerning(0.9).foregroundColor(EuclideousNotesPalette.ink)
                + Text(" \u{00B7} YOUR LIT NOTES, HIT BY HIT").font(heavyMono(8)).kerning(0.32).foregroundColor(EuclideousNotesPalette.key))
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, 4)
                .frame(width: max(0, layout.pickerHeader.width - layout.pickerClose.width - 8), height: layout.pickerHeader.height, alignment: .leading)
                .offset(x: layout.pickerHeader.minX, y: layout.pickerHeader.minY)
            closeButton.offset(x: layout.pickerClose.minX, y: layout.pickerClose.minY)
            // RETIRED (PLAY AS SEQUENCE ferry 2026-11-08): the live picker is the page-level pop-up now; this view is unmounted. `euclideousNotesWayOrder` grew to 13 but `layout.pickerCells` still has 7, so bound the loop — a re-mount degrades, never crashes.
            ForEach(0..<min(euclideousNotesWayOrder.count, layout.pickerCells.count), id: \.self) { i in
                let way = euclideousNotesWayOrder[i]
                cell(way, frame: layout.pickerCells[i]).offset(x: layout.pickerCells[i].minX, y: layout.pickerCells[i].minY)
            }
        }
        .frame(width: layout.picker.width, height: layout.picker.height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.6), radius: 11, x: 0, y: 8)
    }
    private var closeButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(EuclideousNotesPalette.button)
            Path { p in
                p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 7, y: 7)); p.move(to: CGPoint(x: 7, y: 1)); p.addLine(to: CGPoint(x: 1, y: 7))
            }
            .stroke(EuclideousNotesPalette.dim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 8, height: 8)
        }
        .frame(width: layout.pickerClose.width, height: layout.pickerClose.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousNotesPickerCloseLabel)
        .accessibilityAddTraits(.isButton)
    }
    private func cell(_ way: EuclidNotesPlayAs, frame: CGRect) -> some View {
        let selected = way == current
        return VStack(alignment: .leading, spacing: 0) {
            Text(way.rawValue).font(heavyMono(11)).foregroundColor(selected ? EuclideousNotesPalette.ink : EuclideousNotesPalette.riffDot).lineLimit(1).frame(height: 13)
            Color.clear.frame(height: 2)
            Text(euclideousNotesWayDescriptions[way] ?? "").font(heavyMono(7.5)).kerning(0.3).foregroundColor(EuclideousNotesPalette.key).lineLimit(1).truncationMode(.tail).frame(height: 9)
            Color.clear.frame(height: 4)
            EuclideousNotesPreviewView(list: list, way: way, columns: 6, columnGap: 1.5, columnPad: 2, rowGap: 1, columnFill: EuclideousNotesPalette.cellPreviewColumn, accent: accent)
        }
        .padding(.top, 5).padding(.bottom, 5).padding(.leading, 6).padding(.trailing, 5)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.2) : EuclideousNotesPalette.button))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onChoose(way) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousNotesWayAccessibilityLabel(way))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
