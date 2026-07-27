import SwiftUI

/// PRESETS v1 (§3) — the browser sheet, opened from the preset button (right of the logo). SAVE AS on top (the
/// app's first text input), then the user list: tap a name to LOAD (one undoable step), the trash to DELETE.
/// Factory presets (DEFAULT arc + the relocated curriculum) + live transient-load previews are later increments.
struct PresetBrowser: View {
    let presets: [String]
    let current: String
    let onSave: (String) -> Void
    let onLoad: (String) -> Void
    let onDelete: (String) -> Void
    let onClose: () -> Void

    @State private var newName = ""
    @State private var confirmDelete: String? = nil

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
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
                    Text("SAVE").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(trimmed.isEmpty ? ink.opacity(0.3) : .black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(trimmed.isEmpty ? ink.opacity(0.08) : amber))
                        .contentShape(Rectangle())
                        .onTapGesture { if !trimmed.isEmpty { onSave(trimmed); newName = "" } }
                }
                .padding(.bottom, 12)
                Divider().overlay(ink.opacity(0.12)).padding(.bottom, 8)

                if presets.isEmpty {
                    Text("No presets yet — name the current state above and SAVE it.")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(ink.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) { ForEach(presets, id: \.self) { row($0) } }
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
                .background(RoundedRectangle(cornerRadius: 4).fill(arming ? Color(red: 0.98, green: 0.35, blue: 0.3) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { if arming { onDelete(name); confirmDelete = nil } else { confirmDelete = name } }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(isCurrent ? 0.08 : 0.03)))
    }
}
