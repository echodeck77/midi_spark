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

/// A library BROWSER row: the saved/factory cell's name, the processor types in its chain, and its star rating.
struct LibEntry: Identifiable, Equatable {
    let name: String
    let types: [ProcessorType]
    var stars: Int
    var id: String { name }
    var chainSummary: String { types.isEmpty ? "—" : types.map { $0.rawValue }.joined(separator: " → ") }
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
    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(for: name).path) }   // browser arms an overwrite confirm
    /// Saved cell names (no extension), case-insensitively sorted.
    static func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// A small read-only FACTORY set so the library isn't empty first-run. Each is "machine minus routing"
    /// (a chain + colour, no routing) — the user STAMPs it and wires input/output. Built in code (no bundle).
    static func factory() -> [(name: String, cell: Cell)] {
        func slot(_ t: ProcessorType, _ f: (inout ColourParams) -> Void = { _ in }) -> ProcessorSlot {
            var p = ColourParams(); f(&p); return ProcessorSlot(type: t, params: p)
        }
        func cell(_ colourID: String, _ slots: [ProcessorSlot], _ stars: Int = 3) -> Cell {
            var c = Cell(colourID: colourID); c.processors = slots; c.buses = []; c.stars = stars; return c
        }
        // A curated set of MUSICAL CHAINS (each is a colour's machine you STAMP onto the selected colour, then wire
        // your own I/O). Rebuilt for the current 19-processor model (2026-08-17). Ordered light → dense.
        return [
            // — melodic / arpeggiated —
            ("Shimmer",    cell("gold",    [slot(.harmonize) { $0.harmIntervals = [7, 12, 19] },        // add 5th + octave + 12th
                                            slot(.arp) { $0.pattern = .up; $0.rate = .r1_16; $0.octaves = 2 }])),
            ("Human Arp",  cell("vermilion",   [slot(.arp) { $0.pattern = .up; $0.rate = .r1_16; $0.octaves = 2 },
                                            slot(.humanize) { $0.spread = 0.35 }])),                    // loose, hand-played feel
            ("Push",       cell("teal",    [slot(.shift) { $0.spread = 0.16 },                          // nudge the whole chord late
                                            slot(.arp) { $0.pattern = .upDown; $0.rate = .r1_8 }])),
            // — rhythmic gates / rolls —
            ("Trance Gate",cell("cyan",    [slot(.length) { $0.lenSlices = [.pass, .mute, .pass, .mute, .pass, .mute, .pass, .mute] }])),
            ("Trap Roll",  cell("magenta", [slot(.ratchet) { $0.rtcMode = .pattern; $0.rtcSlices = [0, 0, 3, 0, 0, 4, 0, 2]; $0.rtcRate = .r1_16 }])),
            ("Euclid Dub", cell("indigo",  [slot(.euclid) { $0.euclidPulses = 5; $0.euclidSteps = 8 },  // 5-in-8 pulse …
                                            slot(.echo) { $0.echoDelayDiv = 6; $0.echoRepeats = 5; $0.echoDecay = 0.7 }])),  // … into a dotted dub tail
            // — polyrhythm / ensemble —
            ("Weave",      cell("violet",  [slot(.weave) { $0.weaveMode = .ladder; $0.weaveBaseStep = .r1_2; $0.weaveSpan = 4 }])),
            ("Cascade",    cell("chartreuse",    [slot(.cascade) { $0.rate = .r1_4; $0.strumDir = .up }])),   // reveal the chord note by note
            // — expressive / gestural —
            ("Rake",       cell("orange",  [slot(.strum) { $0.strumDir = .down; $0.spread = 0.28; $0.velTilt = 0.5 }])),
            ("Glide Bass", cell("wine",    [slot(.split) { $0.splitSet = ChordSplit(mode: .bottom, n: 1) },   // keep the lowest note …
                                            slot(.glide) { $0.glideTime = 0.18; $0.glideRange = 12 }])),      // … as one sliding mono voice
            ("Burst",      cell("blush",   [slot(.burst) { $0.count = 6; $0.curve = -0.6 },              // an accelerating entry roll …
                                            slot(.harmonize) { $0.harmIntervals = [0, 12, 0] }])),       // … doubled an octave up
            // — generative / evolving —
            ("Sparse",     cell("purple",  [slot(.chance) { $0.probability = 0.55; $0.chanceDensity = true },
                                            slot(.arp) { $0.pattern = .upDown; $0.rate = .r1_8 }])),
            ("Tutti Stab", cell("mint",    [slot(.tutti) { $0.tuttiMode = .coin; $0.tuttiBalance = 0.35; $0.tuttiPick = .high }])),

            // ── SECOND SET (2026-08-17) — 20 more, each differing from the first set in an interesting way ──────────
            // — harmony / voicing —
            ("Descend",     cell("azure",     [slot(.harmonize) { $0.harmIntervals = [7, 12, 0] },              // 5th + octave …
                                               slot(.arp) { $0.pattern = .down; $0.rate = .r1_16; $0.octaves = 2 }])),  // … falling (vs Shimmer's rise)
            ("Wide Voicing",cell("green",     [slot(.harmonize) { $0.harmIntervals = [12, 16, 19] }])),          // octave · 10th · 12th — a spread chord
            // — arpeggiator characters —
            ("Down Runner", cell("slate",     [slot(.arp) { $0.pattern = .down; $0.rate = .r1_16; $0.octaves = 3; $0.arpFit = true }])),
            ("Random Walk", cell("magenta",   [slot(.arp) { $0.pattern = .random; $0.rate = .r1_16; $0.octaves = 2 }])),
            ("Top Line",    cell("chartreuse",[slot(.split) { $0.splitSet = ChordSplit(mode: .top, n: 2) },       // the two highest notes …
                                               slot(.arp) { $0.pattern = .up; $0.rate = .r1_16 }])),             // … as a melody line
            // — echo characters —
            ("Climb",       cell("orange",    [slot(.echo) { $0.echoDelayDiv = 2; $0.echoRepeats = 6; $0.echoDecay = 0.6; $0.echoPitch = 2 }])),  // each echo a step higher
            ("Cavern",      cell("indigo",    [slot(.echo) { $0.echoDelayDiv = 8; $0.echoRepeats = 4; $0.echoDecay = 0.7; $0.echoOffset = 0.2 }])),  // slow, wide, off-grid
            // — weave modes (the first set only had LADDER) —
            ("Harmonic Weave", cell("violet", [slot(.weave) { $0.weaveMode = .harmonic; $0.weaveBaseStep = .r1_4; $0.weaveSpan = 5 }])),
            ("Euclid Weave",cell("purple",    [slot(.weave) { $0.weaveMode = .euclid; $0.weaveEuclidSteps = 8 }])),
            ("Drawn Weave", cell("blush",     [slot(.weave) { $0.weaveMode = .drawn; $0.weaveDrawn = [.r1_1, .r1_2, .r1_4, .r1_8, .r1_8, .r1_4, .r1_2, .r1_1] }])),
            // — sustained / pads —
            ("Pad",         cell("teal",      [slot(.drone) { $0.gate = 0.9 }])),                                // hold the entry chord flat
            ("Top Pad",     cell("cyan",      [slot(.split) { $0.splitSet = ChordSplit(mode: .top, n: 2) },       // the top two …
                                               slot(.drone) { $0.gate = 0.85 }])),                               // … held as a pad
            // — length / gate shapes (the first set only had the PASS/MUTE trance gate) —
            ("Gallop",      cell("wine",      [slot(.length) { $0.lenSlices = [.short, .short, .mute, .short, .short, .mute, .short, .mute] }])),
            ("Legato Tie",  cell("gold",      [slot(.length) { $0.lenSlices = [.long, .pass, .pass, .long, .pass, .pass, .long, .pass]; $0.lenLong = 0.85 }])),
            // — ratchet modes (the first set only had PATTERN) —
            ("Machine Gun", cell("vermilion", [slot(.ratchet) { $0.rtcMode = .all; $0.count = 4; $0.ramp = 0.3 }])),  // every step bursts
            ("Coin Roll",   cell("magenta",   [slot(.ratchet) { $0.rtcMode = .coin; $0.rtcChance = 0.5; $0.rtcCountLo = 2; $0.rtcCountHi = 4 }])),  // sometimes rolls
            // — set-level / voice —
            ("Tutti Pattern",cell("blush",    [slot(.tutti) { $0.tuttiMode = .pattern; $0.tuttiSlices = [.all, .low, .high, .top2, .all, .low, .high, .all]; $0.tuttiRate = .r1_8 }])),
            ("Glide Lead",  cell("green",     [slot(.glide) { $0.glideTime = 0.3; $0.glideRange = 7; $0.glidePriority = .high }])),  // slides, tracks the top note
            // — CC + gate (first set had neither MOD nor PASSGATE) —
            ("Filter Arp",  cell("slate",     [slot(.arp) { $0.pattern = .up; $0.rate = .r1_16; $0.octaves = 2 },
                                               slot(.mod) { $0.modCC = 74; $0.modShape = .sine; $0.modRate = .r2 }])),  // an arp under a filter LFO
            ("Skip Gate",   cell("azure",     [slot(.passgate) { $0.passes = [true, false, true, true] },        // drop every 2nd step …
                                               slot(.arp) { $0.pattern = .up; $0.rate = .r1_8 }])),              // … then arp what passes

            // ── THIRD SET (2026-08-17) — a deep dive on LENGTH (per-slice gate/duration) + TUTTI (solo vs whole
            //    chord), star-rated (the curation basis for the future library) ────────────────────────────────
            // LENGTH — trance gates, rhythms, ties
            ("Half Gate",    cell("cyan",      [slot(.length) { $0.lenSlices = [.pass, .pass, .mute, .mute, .pass, .pass, .mute, .mute] }], 4)),
            ("Off-Beat",     cell("teal",      [slot(.length) { $0.lenSlices = [.mute, .pass, .mute, .pass, .mute, .pass, .mute, .pass] }], 4)),
            ("Stutter",      cell("magenta",   [slot(.length) { $0.lenSlices = [.short, .mute, .short, .mute, .short, .mute, .short, .mute]; $0.lenShort = 0.3 }], 4)),
            ("Tremolo",      cell("vermilion", [slot(.length) { $0.lenSlices = [.short, .short, .short, .short, .short, .short, .short, .short]; $0.lenShort = 0.2 }], 3)),
            ("Tresillo",     cell("orange",    [slot(.length) { $0.lenSlices = [.pass, .mute, .mute, .pass, .mute, .mute, .pass, .mute] }], 5)),   // 3-3-2 clave feel
            ("Long Tie",     cell("gold",      [slot(.length) { $0.lenSlices = [.long, .pass, .pass, .pass, .long, .pass, .pass, .pass]; $0.lenLong = 0.9 }], 4)),
            ("Build Up",     cell("blush",     [slot(.length) { $0.lenSlices = [.mute, .mute, .short, .short, .pass, .pass, .long, .long]; $0.lenLong = 0.8 }], 3)),   // grows across the bar
            // TUTTI — solo vs full-chord shapes
            ("Sparse Stab",  cell("indigo",    [slot(.tutti) { $0.tuttiMode = .coin; $0.tuttiBalance = 0.2; $0.tuttiPick = .high }], 5)),          // mostly one note, rare full chord
            ("Full Swell",   cell("violet",    [slot(.tutti) { $0.tuttiMode = .coin; $0.tuttiBalance = 0.8 }], 3)),
            ("Call & Chord", cell("purple",    [slot(.tutti) { $0.tuttiMode = .pattern; $0.tuttiSlices = [.low, .all, .high, .all, .low, .all, .high, .all]; $0.tuttiRate = .r1_8 }], 5)),
            ("Downbeat",     cell("wine",      [slot(.tutti) { $0.tuttiMode = .pattern; $0.tuttiSlices = [.all, .rest, .all, .rest, .all, .rest, .all, .rest]; $0.tuttiRate = .r1_8 }], 4)),
            ("Bass & Top",   cell("green",     [slot(.tutti) { $0.tuttiMode = .pattern; $0.tuttiSlices = [.low, .low, .high, .low, .low, .low, .high, .low]; $0.tuttiRate = .r1_8 }], 4)),
            // LENGTH + TUTTI combined
            ("Gated Chords", cell("chartreuse",[slot(.tutti) { $0.tuttiMode = .coin; $0.tuttiBalance = 0.75 },
                                                slot(.length) { $0.lenSlices = [.pass, .mute, .pass, .mute, .pass, .mute, .pass, .mute] }], 5)),   // full chords, trance-gated
            ("Rhythm Voice", cell("mint",      [slot(.tutti) { $0.tuttiMode = .pattern; $0.tuttiSlices = [.low, .all, .high, .all, .low, .all, .high, .all] },
                                                slot(.length) { $0.lenSlices = [.short, .short, .pass, .short, .short, .short, .pass, .short]; $0.lenShort = 0.4 }], 4)),
        ]
    }
}
