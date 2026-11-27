//  KitTemplateStore.swift — KIT CARD V2 ferry (2026-11-26) §4.4: the app-level store of USER kit templates.
//
//  GROUP-READY (Paul 2026-11-26): the file lives in the App-Group container when it is provisioned — shared by the
//  standalone app AND the AUv3 — and falls back to THIS process's own Application Support until the group is enabled
//  at the Apple portal (so it builds + works now; enabling the group later turns on app↔AU sharing with no code
//  change). Foundation-only; never touched on the render thread. A user template is 8 notes + 8 velocities + a name.

import Foundation

/// One saved user kit (§4): a name + the 8 ranks' notes and velocities.
struct EuclideousUserKit: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var notes: [UInt8]   // 8
    var vel: [UInt8]     // 8
}

enum KitTemplateStore {
    static let groupId = "group.com.paulbarrett.Fourfold"
    static let fileName = "user-kits.json"
    /// Tests set this to a temp dir so a round-trip never touches the real store.
    static var directoryOverride: URL? = nil

    static var directory: URL {
        if let o = directoryOverride { return o }
        let fm = FileManager.default
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: groupId) {
            return g.appendingPathComponent("KitTemplates", isDirectory: true)   // shared (group provisioned)
        }
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        return base.appendingPathComponent("KitTemplates", isDirectory: true)     // per-process fallback
    }
    private static var fileURL: URL { directory.appendingPathComponent(fileName) }

    // MARK: file layer
    static func load() -> [EuclideousUserKit] {
        guard let data = try? Data(contentsOf: fileURL), let kits = try? JSONDecoder().decode([EuclideousUserKit].self, from: data) else { return [] }
        return kits
    }
    @discardableResult static func write(_ kits: [EuclideousUserKit]) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(kits) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    // MARK: operations (persist + return the new id where relevant)
    /// §4.3 SAVE — store a new template, return its id. The name is cleaned/uniquified by `uniqueName` first.
    @discardableResult static func save(name: String, notes: [UInt8], vel: [UInt8], id: String = UUID().uuidString) -> String {
        var kits = load()
        let n = uniqueName(name, fallback: prefillName(kits.map { $0.name }), existing: kits.map { $0.name })
        kits.append(EuclideousUserKit(id: id, name: n, notes: Array(notes.prefix(8)), vel: Array(vel.prefix(8))))
        write(kits); return id
    }
    /// §4.5 rename (keeps the id; uniquifies against the OTHER names).
    static func rename(id: String, to raw: String) {
        var kits = load()
        guard let i = kits.firstIndex(where: { $0.id == id }) else { return }
        let others = kits.enumerated().filter { $0.offset != i }.map { $0.element.name }
        kits[i].name = uniqueName(raw, fallback: kits[i].name, existing: others)
        write(kits)
    }
    /// §4.5 delete.
    static func delete(id: String) { write(load().filter { $0.id != id }) }

    // MARK: pure name helpers (§4.3) — testable without files
    /// The prefill "KIT n": the lowest n ≥ 1 whose "KIT n" is not already a name.
    static func prefillName(_ existing: [String]) -> String {
        let set = Set(existing.map { $0.uppercased() })
        var n = 1; while set.contains("KIT \(n)") { n += 1 }
        return "KIT \(n)"
    }
    /// Clean a user name: uppercased, ≤ 16 chars, empty ⇒ `fallback`; a clash with an existing name ⇒ append " 2" (then " 3"…).
    static func uniqueName(_ raw: String, fallback: String, existing: [String]) -> String {
        var base = String(raw.uppercased().prefix(16)); if base.isEmpty { base = fallback }
        let set = Set(existing.map { $0.uppercased() })
        if !set.contains(base) { return base }
        var k = 2; while set.contains("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }
}
