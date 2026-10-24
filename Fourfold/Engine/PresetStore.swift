import Foundation

/// PRESETS v1 (§3) — a preset is the WHOLE document (all scenes · wiring · per-scene Machines · key), saved as a
/// NAMED JSON file. It is distinct from the host's automatic fullState (that stays the AUM-session persistence);
/// a preset uses the SAME codec as the fullState document blob, so the two are byte-interchangeable.
///
/// v1 stores files in the EXTENSION's own container (Application Support/Presets). The App Group container — so a
/// future standalone app reads the same files natively — is a follow-up needing an entitlement: swap `directory`.
enum PresetStore {
    static let ext = "8x8"                       // our preset file extension

    /// A filesystem-safe base name for a user-facing preset name: strips path/reserved/control chars, trims,
    /// collapses runs of whitespace, caps length. Empty → "Untitled". Pure (the unit-tested surface).
    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>.").union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.filter { !bad.contains($0) })
        let collapsed = cleaned.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
        let capped = String(collapsed.prefix(48))
        return capped.isEmpty ? "Untitled" : capped
    }

    /// Encode/decode the document exactly as the host fullState does (same codec → interchangeable). Load runs
    /// the mandatory legacy-schema migration, matching fullState's setter. Pure (unit-tested round-trip).
    static func encode(_ doc: PluginState) -> Data? { try? JSONEncoder().encode(doc) }
    static func decode(_ data: Data) -> PluginState? {
        guard var doc = try? JSONDecoder().decode(PluginState.self, from: data) else { return nil }
        doc.migrateLegacyRoutingIfNeeded()       // old-schema presets → v3 on load (same as fullState)
        doc.normalizeLocksAtLoad()               // LANE LOCK 3.5: a preset saved while a locked lane was deviated opens at its locked state
        return doc
    }

    // MARK: - file I/O (extension sandbox — thin FileManager calls, device-verified)

    /// The standalone app turns this on at launch: its Documents folder is visible in the Files app (`UIFileSharingEnabled`), so saved presets live there and can be backed up, copied and shared. The AU extension (its container is
    /// invisible whatever we do) and the unit tests keep Application Support.
    static var useDocumentsFolder = false
    private static var movedToDocuments = false
    static var directory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Presets", isDirectory: true)
        guard useDocumentsFolder else {
            try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
            return appSupport
        }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Presets", isDirectory: true)
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
        if !movedToDocuments { movedToDocuments = true; moveAll(from: appSupport, to: docs) }   // presets saved before the app moved to Documents come along, once
        return docs
    }
    /// Moves every preset file in `old` into `new` unless a file of that name is already there; returns how many moved.
    @discardableResult
    static func moveAll(from old: URL, to new: URL) -> Int {
        let fm = FileManager.default
        var n = 0
        for f in (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == ext {
            let target = new.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: target.path), (try? fm.moveItem(at: f, to: target)) != nil { n += 1 }
        }
        return n
    }
    static func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(sanitize(name)).appendingPathExtension(ext)
    }

    @discardableResult
    static func save(_ doc: PluginState, as name: String) -> Bool {
        guard let data = encode(doc) else { return false }
        return (try? data.write(to: fileURL(for: name), options: .atomic)) != nil
    }
    static func load(_ name: String) -> PluginState? {
        guard let data = try? Data(contentsOf: fileURL(for: name)) else { return nil }
        return decode(data)
    }
    /// The raw encoded document bytes for a preset — the SAME bytes fullState puts under its state key, so the
    /// host's `presetState(for:)` can hand them straight back to the fullState setter. nil if the file is missing.
    static func rawData(for name: String) -> Data? { try? Data(contentsOf: fileURL(for: name)) }
    static func delete(_ name: String) { try? FileManager.default.removeItem(at: fileURL(for: name)) }
    /// Whether a preset already exists under `name` (its SANITIZED filename) — the browser arms an overwrite confirm
    /// on it, so a save never silently clobbers a same-named (or same-sanitized, e.g. "My/Rig"↔"MyRig") preset.
    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(for: name).path) }

    /// User preset names (no extension), case-insensitively sorted.
    static func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
