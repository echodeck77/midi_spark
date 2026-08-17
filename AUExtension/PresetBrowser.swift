import SwiftUI

/// PRESETS v1 (§3) — the browser sheet, opened from the preset button (right of the logo). SAVE AS on top (the
/// app's first text input), then the user list: tap a name to LOAD (one undoable step), the trash to DELETE.
/// Factory presets (DEFAULT arc + the relocated curriculum) + live transient-load previews are later increments.
struct PresetBrowser: View {
    let presets: [String]
    var factory: [String] = []                  // §3 read-only factory presets (DEFAULT + the curriculum)
    let current: String
    let onSave: (String) -> Void
    let onLoad: (String) -> Void
    var onLoadFactory: (String) -> Void = { _ in }
    let onDelete: (String) -> Void
    let onClose: () -> Void

    @State private var newName = ""
    @State private var confirmDelete: String? = nil
    @State private var confirmOverwrite = false   // SAVE onto an existing name arms an OVERWRITE? confirm (no silent clobber)

    private let ink = Color.white
    private let cyan = UI.cyan
    private let amber = UI.amber
    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PRESETS").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.9))
                    Spacer()
                    Text("✕").font(.system(size: 18, weight: .heavy)).foregroundColor(ink.opacity(0.7))
                        .contentShape(Rectangle()).onTapGesture { onClose() }
                }
                .padding(.bottom, 12)

                // SAVE AS — the whole document, under a name (overwrites a same-named user preset)
                HStack(spacing: 8) {
                    TextField("", text: $newName, prompt: Text("name this preset…").foregroundColor(ink.opacity(0.3)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(ink)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(0.08)))
                        .onChange(of: newName) { _ in confirmOverwrite = false }   // editing the name disarms the overwrite confirm
                    Text(confirmOverwrite ? "OVERWRITE?" : "SAVE").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(trimmed.isEmpty ? ink.opacity(0.3) : .black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(trimmed.isEmpty ? ink.opacity(0.08) : (confirmOverwrite ? UI.red : amber)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !trimmed.isEmpty else { return }
                            if !confirmOverwrite && PresetStore.exists(trimmed) { confirmOverwrite = true; return }   // first tap on an existing name arms the confirm
                            onSave(trimmed); newName = ""; confirmOverwrite = false
                        }
                }
                .padding(.bottom, 12)
                Divider().overlay(ink.opacity(0.12)).padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !factory.isEmpty {
                            sectionHeader("FACTORY")
                            ForEach(factory, id: \.self) { factoryRow($0) }
                        }
                        sectionHeader("YOUR PRESETS")
                        if presets.isEmpty {
                            Text("None yet — name the current state above and SAVE it.")
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(ink.opacity(0.35))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                        } else {
                            ForEach(presets, id: \.self) { row($0) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: 460, maxHeight: 520)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.1)))
            .padding(20)
            .onTapGesture { confirmDelete = nil }   // tapping the sheet body cancels a pending delete
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.45)).tracking(1.5)
            .padding(.top, 6).padding(.bottom, 2)
    }
    // §3 a read-only factory preset — tap to LOAD; no rename/overwrite/delete (a lock marks it).
    private func factoryRow(_ name: String) -> some View {
        let isCurrent = name == current
        return HStack(spacing: 10) {
            Text(name).font(.system(size: 12, weight: isCurrent ? .heavy : .semibold, design: .monospaced))
                .foregroundColor(isCurrent ? amber : ink.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(ink.opacity(0.3))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(isCurrent ? 0.08 : 0.03)))
        .contentShape(Rectangle()).onTapGesture { onLoadFactory(name) }
    }
    private func row(_ name: String) -> some View {
        let isCurrent = name == current
        let arming = confirmDelete == name
        return HStack(spacing: 10) {
            Text(name).font(.system(size: 12, weight: isCurrent ? .heavy : .semibold, design: .monospaced))
                .foregroundColor(isCurrent ? cyan : ink.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onLoad(name) }
            Text(arming ? "DELETE?" : "🗑")
                .font(.system(size: arming ? 9 : 12, weight: .heavy, design: .monospaced))
                .foregroundColor(arming ? .black : ink.opacity(0.5))
                .padding(.horizontal, arming ? 6 : 4).padding(.vertical, arming ? 3 : 0)
                .background(RoundedRectangle(cornerRadius: 4).fill(arming ? UI.red : .clear))
                .contentShape(Rectangle())
                .onTapGesture { if arming { onDelete(name); confirmDelete = nil } else { confirmDelete = name } }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(isCurrent ? 0.08 : 0.03)))
    }
}

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

    // One library row: name over its chain summary, a star rating, APPLY, and (saved only) delete. Tapping ANYWHERE
    // on the row that isn't a button previews the chain; APPLY/stars/delete keep their own hit areas.
    @ViewBuilder private func libraryRow(_ e: LibEntry, saved: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(saved ? 0.9 : 0.8))
                Text(e.chainSummary).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.6)
            }
            starsView(e, editable: saved)
            Spacer(minLength: 6)
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
        .contentShape(Rectangle())
        .onTapGesture { if saved { onPreview(e.name) } else { onPreviewFactory(e.name) } }   // whole-row preview
    }
    // A 5-star rating. Editable (saved cells): tap a star to set; tap the current top star to drop one. Factory cells
    // render display-only, so a tap falls through to the row's preview.
    @ViewBuilder private func starsView(_ e: LibEntry, editable: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { k in
                let filled = k <= e.stars
                if editable {
                    Image(systemName: filled ? "star.fill" : "star").font(.system(size: 10)).foregroundColor(filled ? amber : ink.opacity(0.22))
                        .contentShape(Rectangle()).onTapGesture { onSetStars(e.name, e.stars == k ? k - 1 : k) }
                } else {
                    Image(systemName: filled ? "star.fill" : "star").font(.system(size: 10)).foregroundColor(filled ? amber : ink.opacity(0.22))
                }
            }
        }
    }
}
