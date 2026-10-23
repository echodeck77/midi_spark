//  CellBrowser.swift
//  The 8x8 CELL LIBRARY browser, split out of PresetBrowser.swift 2026-10-23 (Fourfold Step 1a). No behaviour change.

import SwiftUI

/// CELL LIBRARY browser (§cell-machine 4.8) — mirrors PresetBrowser for named saved CELLS: SAVE the selected
/// cell under a name, STAMP a saved cell (arms the stamp mode), DELETE. Same overlay look as PRESETS.
struct CellBrowser: View {
    let cells: [LibEntry]
    var factory: [LibEntry] = []                // read-only starter cells (STAMP only)
    var canSave: Bool = false
    let onSave: (String) -> Void
    let onStamp: (String) -> Void
    var onStampFactory: (String) -> Void = { _ in }
    var onPreview: (String) -> Void = { _ in }          // tap anywhere on a ROW → audition its chain (reverted on close unless APPLY'd)
    var onPreviewFactory: (String) -> Void = { _ in }
    var onSetStars: (String, Int) -> Void = { _, _ in } // tap a star to rate a SAVED cell (0–5)
    let onDelete: (String) -> Void
    let onClose: () -> Void

    @State private var newName = ""
    @State private var confirmDelete: String? = nil
    @State private var confirmOverwrite = false   // SAVE onto an existing cell name arms an OVERWRITE? confirm
    private let ink = Color.white
    private let cyan = UI.cyan
    private let amber = UI.amber
    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("CELL LIBRARY").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.9))
                    Spacer()
                    Text("✕").font(.system(size: 18, weight: .heavy)).foregroundColor(ink.opacity(0.7))
                        .contentShape(Rectangle()).onTapGesture { onClose() }
                }.padding(.bottom, 12)

                HStack(spacing: 8) {   // SAVE the selected cell (machine minus routing) under a name
                    TextField("", text: $newName, prompt: Text(canSave ? "name this cell…" : "select a cell first").foregroundColor(ink.opacity(0.3)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(ink)
                        .textInputAutocapitalization(.words).autocorrectionDisabled().disabled(!canSave)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(0.08)))
                        .onChange(of: newName) { _ in confirmOverwrite = false }
                    let ready = canSave && !trimmed.isEmpty
                    Text(confirmOverwrite ? "OVERWRITE?" : "SAVE").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(ready ? .black : ink.opacity(0.3))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ready ? (confirmOverwrite ? UI.red : amber) : ink.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture {
                            guard ready else { return }
                            if !confirmOverwrite && CellLibraryStore.exists(trimmed) { confirmOverwrite = true; return }
                            onSave(trimmed); newName = ""; confirmOverwrite = false
                        }
                }.padding(.bottom, 12)
                Divider().overlay(ink.opacity(0.12)).padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if cells.isEmpty {
                            Text("no saved cells yet — configure a cell, then SAVE").font(.system(size: 11, design: .monospaced)).foregroundColor(ink.opacity(0.4)).padding(.vertical, 8)
                        } else {
                            ForEach(cells) { e in libraryRow(e, saved: true) }
                        }
                        if !factory.isEmpty {   // read-only starter cells — STAMP only
                            Text("FACTORY").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.4)).padding(.top, 10).padding(.leading, 2)
                            ForEach(factory) { e in libraryRow(e, saved: false) }
                        }
                    }
                }
            }
            .padding(18).frame(maxWidth: 460, maxHeight: 520)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
        }
    }

    // One library row: a favourite star, then a PREVIEW region (name over its chain summary), then APPLY + (saved)
    // delete. The preview region is its OWN tap target with no interactive children — so tapping anywhere across the
    // name/summary/gap reliably previews, while the star/APPLY/delete buttons keep their own hit areas.
    @ViewBuilder private func libraryRow(_ e: LibEntry, saved: Bool) -> some View {
        HStack(spacing: 8) {
            favStar(e, editable: saved)
            HStack(spacing: 0) {                               // ← the PREVIEW region (fills the line up to the buttons)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(saved ? 0.9 : 0.8))
                    Text(e.chainSummary).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if saved { onPreview(e.name) } else { onPreviewFactory(e.name) } }
            Text("APPLY").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(cyan))
                .contentShape(Rectangle()).onTapGesture { if saved { onStamp(e.name) } else { onStampFactory(e.name) } }
            if saved {
                Text(confirmDelete == e.name ? "SURE?" : "✕")
                    .font(.system(size: confirmDelete == e.name ? 10 : 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(confirmDelete == e.name ? .black : ink.opacity(0.5))
                    .padding(.horizontal, confirmDelete == e.name ? 8 : 6).padding(.vertical, confirmDelete == e.name ? 5 : 0)
                    .background(RoundedRectangle(cornerRadius: 5).fill(confirmDelete == e.name ? amber : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { if confirmDelete == e.name { onDelete(e.name); confirmDelete = nil } else { confirmDelete = e.name } }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(saved ? 0.05 : 0.03)))
    }
    // A single FAVOURITE star (curation flag). Saved cells: tap to toggle. Factory cells: display-only (curated).
    @ViewBuilder private func favStar(_ e: LibEntry, editable: Bool) -> some View {
        let on = e.stars >= 1
        Image(systemName: on ? "star.fill" : "star").font(.system(size: 13, weight: .semibold)).foregroundColor(on ? amber : ink.opacity(0.28))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .onTapGesture { if editable { onSetStars(e.name, on ? 0 : 1) } }
    }
}
