import Foundation

// BUILD's PERSISTED workshop types. Moved here from BuildPage.swift (a SwiftUI extension outside the test target) so
// they compile into the pure test target AND can be serialized into the document. (Paul 2026-08-16)

// A PART — the workshop-level unit of the BUILD lifecycle (unassigned → built → staged → deployed). It owns its own
// staging grid + variations, its cast selection, and its PART-OWNED I/O (one input door + a set of output emitters,
// shared across every colour/cell of the part). `deployed` christens it (PART n) on first assignment to the play grid.
struct BuildPart: Codable, Equatable {
    var stagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    var stagingSel: [Int] = Array(repeating: -1, count: 8)
    var rowChain: [[ProcessorSlot]] = Array(repeating: [], count: 8)
    var rowShade: [Double] = Array(repeating: 0, count: 8)
    var rowUnder: [String?] = Array(repeating: nil, count: 8)   // one-colour-per-row: what a row REVERTS to when its colour is stamped elsewhere
    var selID: String? = nil          // the cast selection BY ID (supports ephemeral colours)
    var cast: [String] = []           // §2 CAST VIEW: the part's visible palette — a per-part MEMBERSHIP over the global colour store
    var castSlots: [Int: String] = [:] // §2 explicit slot→colourID placements for NON-default colours (long-press lands a colour on its pressed cell)
    var receiver: Int = 0             // the PART's DEFAULT input door (R1–R4) — a row inherits it unless overridden
    var emitters: Set<Bus> = [.a]     // the PART's DEFAULT output emitters — a row inherits it unless overridden
    // PER-ROW I/O overrides (Paul 2026-08-18, additive-Optional): a nil array OR a nil entry = inherit the part default.
    var rowReceiver: [Int?]? = nil
    var rowEmitters: [Set<Bus>?]? = nil
    var deployed: Bool = false        // christened (PART n) once deployed to the play grid
    // PER-PART CLOCK (Paul 2026-08-19): the part is a TRACK — its own rate + loop length, so deployed parts play at
    // independent tempos. Additive-Optional (old parts decode nil ⇒ the scene default rate + a full 8).
    var rate: StepRate? = nil         // the part's step rate (nil ⇒ the scene default)
    var length: Int? = nil            // the part's LOOP length in columns 1…8 (nil ⇒ 8; < 8 = a shorter loop, a future step)
}

// The single UNASSIGNED part saved WITH THE DOCUMENT (Paul 2026-08-16, "saving = committing"): the part plus the
// EPHEMERAL colours it references (their machine + custom hue), so the half-built piece reconstructs on reload.
// Canonical document colours are NOT bundled — they're always present. Persisted as an additive-Optional field on
// PluginState, so old saves decode as nil (no migration break).
struct BuildUnassignedData: Codable, Equatable {
    var part: BuildPart
    var colours: [Colour] = []          // the referenced EPHEMERAL colours (colourID + templateChain machine + defined)
    var hues: [String: UInt32] = [:]    // ephemeral colour hues, id → packed RGB (colourHueOverride is session-only)
    var idCounter: Int = 0              // the ephemeral "b<n>" counter high-water mark, so restored ids don't collide
}

// SCENES V2 (Paul 2026-08-12, Docs/scenes-v2-multigrids.md) — a SCENE = one PLAY-GRID ARRANGEMENT: which part sits in
// each band, the flatten/copy content, the rung/mute/lane state, and the ROW 8 lit toggles. The PARTS, colours, casts,
// doors + the master are SHARED across scenes (a scene arranges the same band; it never owns the musicians). v1 is an
// IN-MEMORY switcher (not yet persisted with the document); switching is INSTANT (pass-quantized arm/blink = a follow-up).
struct BuildSceneSnapshot: Codable, Equatable {
    var performCells: [[String?]]
    var performChain: [[[ProcessorSlot]]]
    var performRecv: [Int]
    var performEmit: [Set<Bus>]
    var performPart: [Int]
    var performMute: Set<Int>
    var performStagingRow: [Int]
    var performLane: UInt8
    var row8On: [Bool]                 // the scene's lit ROW 8 toggles (FREEZE/HALFTIME/… state)
    var name: String = ""
}

// DECODE-TOLERANT INITS (Paul 2026-08-27 housekeeping — the `Macro` pattern, Models.swift:890). These three BUILD
// persistence types are the newest, fastest-churning SAVED types; synthesized Decodable THROWS on a MISSING non-Optional
// key, so a field added AFTER a save shipped makes an older document fail to decode → the WHOLE PluginState decode throws
// → the session silently resets to factory (the CR-8 data-loss class). This ALREADY bit `BuildPart.castSlots` (added
// 2026-08-17, ONE DAY after buildUnassigned first persisted 2026-08-16 → every save in that window is currently un-loadable).
// decodeIfPresent every field so a missing key falls back to its default instead of throwing. In EXTENSIONS so the
// memberwise init + synthesized Encodable are preserved. Guards this whole class of type forever, not just castSlots.
extension BuildPart {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stagingCells = try c.decodeIfPresent([[String?]].self, forKey: .stagingCells) ?? Array(repeating: Array(repeating: nil, count: 8), count: 8)
        stagingSel   = try c.decodeIfPresent([Int].self, forKey: .stagingSel) ?? Array(repeating: -1, count: 8)
        rowChain     = try c.decodeIfPresent([[ProcessorSlot]].self, forKey: .rowChain) ?? Array(repeating: [], count: 8)
        rowShade     = try c.decodeIfPresent([Double].self, forKey: .rowShade) ?? Array(repeating: 0, count: 8)
        rowUnder     = try c.decodeIfPresent([String?].self, forKey: .rowUnder) ?? Array(repeating: nil, count: 8)
        selID        = try c.decodeIfPresent(String.self, forKey: .selID)
        cast         = try c.decodeIfPresent([String].self, forKey: .cast) ?? []
        castSlots    = try c.decodeIfPresent([Int: String].self, forKey: .castSlots) ?? [:]
        receiver     = try c.decodeIfPresent(Int.self, forKey: .receiver) ?? 0
        emitters     = try c.decodeIfPresent(Set<Bus>.self, forKey: .emitters) ?? [.a]
        rowReceiver  = try c.decodeIfPresent([Int?].self, forKey: .rowReceiver)
        rowEmitters  = try c.decodeIfPresent([Set<Bus>?].self, forKey: .rowEmitters)
        deployed     = try c.decodeIfPresent(Bool.self, forKey: .deployed) ?? false
        rate         = try c.decodeIfPresent(StepRate.self, forKey: .rate)
        length       = try c.decodeIfPresent(Int.self, forKey: .length)
    }
}
extension BuildUnassignedData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        part      = try c.decodeIfPresent(BuildPart.self, forKey: .part) ?? BuildPart()
        colours   = try c.decodeIfPresent([Colour].self, forKey: .colours) ?? []
        hues      = try c.decodeIfPresent([String: UInt32].self, forKey: .hues) ?? [:]
        idCounter = try c.decodeIfPresent(Int.self, forKey: .idCounter) ?? 0
    }
}
extension BuildSceneSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        performCells      = try c.decodeIfPresent([[String?]].self, forKey: .performCells) ?? Array(repeating: Array(repeating: nil, count: 8), count: 8)
        performChain      = try c.decodeIfPresent([[[ProcessorSlot]]].self, forKey: .performChain) ?? Array(repeating: Array(repeating: [], count: 8), count: 8)
        performRecv       = try c.decodeIfPresent([Int].self, forKey: .performRecv) ?? Array(repeating: 0, count: 8)
        performEmit       = try c.decodeIfPresent([Set<Bus>].self, forKey: .performEmit) ?? Array(repeating: [.a], count: 8)
        performPart       = try c.decodeIfPresent([Int].self, forKey: .performPart) ?? Array(repeating: -1, count: 8)
        performMute       = try c.decodeIfPresent(Set<Int>.self, forKey: .performMute) ?? []
        performStagingRow = try c.decodeIfPresent([Int].self, forKey: .performStagingRow) ?? Array(repeating: -1, count: 8)
        performLane       = try c.decodeIfPresent(UInt8.self, forKey: .performLane) ?? 0
        row8On            = try c.decodeIfPresent([Bool].self, forKey: .row8On) ?? Array(repeating: false, count: 8)
        name              = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}
