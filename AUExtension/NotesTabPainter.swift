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

/// What one key shows. `position` is the lit-order position it stands for (0-7 ranks 1-8, 8 TOP 2, 9 TOP).
struct EuclideousNotesKeySpec: Equatable {
    var position: Int
    /// The received look (fill #30343C); false = an octave copy — and every key while nothing is held.
    var received: Bool
    var lit: Bool
    /// A lit octave copy while RECEIVED is on: the bar is hollow, the key stays lit and just doesn't sound (2.6).
    var heldBack: Bool
    /// A rank key: the full note name ("A♭3", or "–" with nothing held). TOP 2 / TOP: the second line, the note it resolves to now.
    var name: String
    var place: String?
    var riffDot: Bool
    /// 0...1: the glow while this key's note sounds (10.1).
    var sounding: Double
}

struct EuclideousNotesKeyView: View {
    let spec: EuclideousNotesKeySpec
    let accent: Color
    let size: CGSize

    private var isTop: Bool { spec.position >= 8 }
    private var labelColour: Color {
        if spec.sounding > 0 { return EuclideousNotesPalette.ink }
        return spec.received ? Color.white.opacity(0.75) : Color.white.opacity(0.35)
    }
    @ViewBuilder private var label: some View {
        if isTop {
            VStack(spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("TOP").font(heavyMono(10))
                    if spec.position == EuclideousLitOrder.topTwoPosition { Text("2").font(heavyMono(8)) }
                }
                .foregroundColor(labelColour).lineLimit(1)
                .frame(height: 13)
                Text(spec.name).font(boldMono(8)).foregroundColor(spec.sounding > 0 ? EuclideousNotesPalette.ink : EuclideousNotesPalette.key).lineLimit(1)
                    .frame(height: 10)
            }
        } else {
            let split = euclideousSplitNoteOctave(spec.name)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(split.note).font(heavyMono(15))
                Text(split.octave).font(boldMono(10))
            }
            .foregroundColor(labelColour).lineLimit(1)   // truncate, never shrink
        }
    }
    var body: some View {
        let fill = spec.received ? Color(h: 0x30343C) : Color(h: 0x17191E)
        let border = spec.received ? Color(h: 0x454A54) : Color(h: 0x202329)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1)
            // the label: centred in the key above a 6 pt bottom inset, clear of the bar and the place number
            label.frame(width: size.width, height: size.height - 6).frame(maxHeight: .infinity, alignment: .top)
            if let place = spec.place {
                Text(place).font(heavyMono(8.5)).foregroundColor(accent).lineLimit(1).frame(height: 10)
                    .padding(.bottom, 9.5)
            }
            if spec.lit {
                if spec.heldBack {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(accent, lineWidth: 1.25).frame(height: 4).padding(.horizontal, 4).padding(.bottom, 3)
                } else {
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(height: 3).padding(.horizontal, 4).padding(.bottom, 3.5)
                }
            }
            if spec.riffDot {
                Circle().fill(EuclideousNotesPalette.riffDot).frame(width: 5, height: 5).frame(maxHeight: .infinity, alignment: .top).padding(.top, 6)
            }
            if spec.sounding > 0 {
                RoundedRectangle(cornerRadius: 6).strokeBorder(accent, lineWidth: 1.5).opacity(spec.sounding)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: spec.sounding > 0 ? accent.opacity(0.45 * spec.sounding) : .clear, radius: spec.sounding > 0 ? 10 : 0)
    }
}

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
            ForEach(0..<euclideousNotesWayOrder.count, id: \.self) { i in
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
