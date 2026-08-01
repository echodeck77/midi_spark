import Foundation

/// PRESETS v1 (§3) — a preset is the WHOLE document (all scenes · wiring · per-scene Colours · key), saved as a
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
        return doc
    }

    // MARK: - file I/O (extension sandbox — thin FileManager calls, device-verified)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    /// User preset names (no extension), case-insensitively sorted.
    static func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// CELL LIBRARY (§cell-machine 1.5/4.8) — a named, saved CELL reusable across sessions. Same app-level file
/// pattern as PresetStore (Application Support/Cells · `.8x8cell`), one Codable `Cell` per file. A saved cell is
/// "machine minus routing": the chain + colour + source-shaping travel; input/output are wired fresh on stamp.
enum CellLibraryStore {
    static let ext = "8x8cell"
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Cells", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(PresetStore.sanitize(name)).appendingPathExtension(ext)
    }
    static func encode(_ cell: Cell) -> Data? { try? JSONEncoder().encode(cell) }
    static func decode(_ data: Data) -> Cell? { try? JSONDecoder().decode(Cell.self, from: data) }
    @discardableResult
    static func save(_ cell: Cell, as name: String) -> Bool {
        guard let data = encode(cell) else { return false }
        return (try? data.write(to: fileURL(for: name), options: .atomic)) != nil
    }
    static func load(_ name: String) -> Cell? {
        guard let data = try? Data(contentsOf: fileURL(for: name)) else { return nil }
        return decode(data)
    }
    static func delete(_ name: String) { try? FileManager.default.removeItem(at: fileURL(for: name)) }
    /// Saved cell names (no extension), case-insensitively sorted.
    static func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
