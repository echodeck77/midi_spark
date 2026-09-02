import Foundation

// BUILD's PERSISTED workshop types. Moved here from BuildPage.swift (a SwiftUI extension outside the test target) so
// they compile into the pure test target AND can be serialized into the document. (Paul 2026-08-16)

// A PART — the workshop-level unit of the BUILD lifecycle (unassigned → built → staged → deployed). It owns its own
// staging grid + variations, its cast selection, and its PART-OWNED I/O (one input door + a set of output emitters,
// shared across every colour/cell of the part). `deployed` christens it (PART n) on first assignment to the play grid.
struct BuildPart: Codable, Equatable {
    // §E 16-STEP (Paul 2026-09-02): the STAGING columns are now maxCols(16)-wide (was 8). `length` is the part's active
    // width/loop 1…16 (nil ⇒ the 8-wide default → byte-identical). Old 8-col saves decode short + are padded on restore.
    var stagingCells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: Snap.maxCols)
    var stagingSel: [Int] = Array(repeating: -1, count: Snap.maxCols)
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

// PART AUTOMATION (Paul 2026-09-02) — the AUTO lanes. Per colour, FIVE lanes; one is ACTIVE at a time (activeLane,
// −1 = NONE/off). A lane picks a processor slot + a param and an EXTENT of grid cells (col*Snap.rows+row); the param
// RAMPS across the extent (low→high, column→row order) over a per-param musical SUB-RANGE, baked per-cell at build
// (rides the M2 substrate — the render is unchanged). `cells` is the extent SET (tap-toggle, Paul: no sliding).
// Foundation-only + Codable so the automation travels with the document (additive-Optional on PluginState).
struct AutoLane: Codable, Equatable {
    var slot: Int = 0                       // the processor slot in the colour's chain
    var param: String = ""                  // the param this lane automates ("" ⇒ the processor's pre-mapped useful default)
    var cells: Set<Int> = []                // the cells (col*Snap.rows+row) in the automation's EXTENT; the RANGE is a ramp swept across them
    // FROM → TO (Paul 2026-09-02): the sweep endpoints (the "before/after"). nil ⇒ the param's curated musical sub-range.
    // The extent (cells) is WHERE; these are the value RANGE the ramp sweeps between (FROM at the first cell → TO at the last).
    var lo: Double? = nil
    var hi: Double? = nil
}

// A colour's automation: which lane is ON (activeLane, −1 = NONE) + its five lanes. One active lane per colour (Paul).
struct PartAutoColour: Codable, Equatable {
    var activeLane: Int = -1                // −1 = NONE (off) · 0–4 = the enabled lane (plays immediately)
    var lanes: [AutoLane] = []              // up to 5 (padded on read)
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

// THE ROOMS PLAY GRID (Paul 2026-08-30) — the 8 INDEPENDENT play columns (buildPlayCells + their I/O + start state) plus
// the MULTI-STEP PASSES a flattened part rides (colLen/colSteps/colRate + per-step I/O). Persisted like BuildUnassignedData:
// it carries the EPHEMERAL colours it references (buildColourReg is session-only) so a reload restores the passes AND their
// machines. Before this the whole rooms play grid was in-memory → a fresh load lost it. Additive-Optional on PluginState.
struct BuildPlayGridData: Codable, Equatable {
    var cells: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    var sel: [Int] = Array(repeating: 0, count: 8)
    var colOn: [Bool] = Array(repeating: false, count: 8)
    var colRecv: [Int] = Array(repeating: 0, count: 8)
    var colEmit: [Set<Bus>] = Array(repeating: [.a], count: 8)
    var colLen: [Int] = Array(repeating: 1, count: 8)
    var colSteps: [[String?]] = Array(repeating: [], count: 8)
    var colRate: [StepRate?] = Array(repeating: nil, count: 8)
    var colStepRecv: [[Int]] = Array(repeating: [], count: 8)
    var colStepEmit: [[Set<Bus>]] = Array(repeating: [], count: 8)
    var colours: [Colour] = []          // referenced EPHEMERAL colours (colourID + templateChain machine + transpose)
    var hues: [String: UInt32] = [:]    // ephemeral colour hues (colourHueOverride is session-only)
    var idCounter: Int = 0              // the "b<n>" high-water mark so restored ids don't collide
}
extension BuildPlayGridData {   // decode-tolerant (the Macro/BuildUnassignedData pattern) — a field added later never fails an older save
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cells       = try c.decodeIfPresent([[String?]].self, forKey: .cells) ?? Array(repeating: Array(repeating: nil, count: 8), count: 8)
        sel         = try c.decodeIfPresent([Int].self, forKey: .sel) ?? Array(repeating: 0, count: 8)
        colOn       = try c.decodeIfPresent([Bool].self, forKey: .colOn) ?? Array(repeating: false, count: 8)
        colRecv     = try c.decodeIfPresent([Int].self, forKey: .colRecv) ?? Array(repeating: 0, count: 8)
        colEmit     = try c.decodeIfPresent([Set<Bus>].self, forKey: .colEmit) ?? Array(repeating: [.a], count: 8)
        colLen      = try c.decodeIfPresent([Int].self, forKey: .colLen) ?? Array(repeating: 1, count: 8)
        colSteps    = try c.decodeIfPresent([[String?]].self, forKey: .colSteps) ?? Array(repeating: [], count: 8)
        colRate     = try c.decodeIfPresent([StepRate?].self, forKey: .colRate) ?? Array(repeating: nil, count: 8)
        colStepRecv = try c.decodeIfPresent([[Int]].self, forKey: .colStepRecv) ?? Array(repeating: [], count: 8)
        colStepEmit = try c.decodeIfPresent([[Set<Bus>]].self, forKey: .colStepEmit) ?? Array(repeating: [], count: 8)
        colours     = try c.decodeIfPresent([Colour].self, forKey: .colours) ?? []
        hues        = try c.decodeIfPresent([String: UInt32].self, forKey: .hues) ?? [:]
        idCounter   = try c.decodeIfPresent(Int.self, forKey: .idCounter) ?? 0
    }
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
    var performLane: UInt16
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
        stagingCells = Snap.padCols(try c.decodeIfPresent([[String?]].self, forKey: .stagingCells) ?? [], Array(repeating: nil, count: 8))   // §E: pad an old 8-col save to 16
        stagingSel   = Snap.padCols(try c.decodeIfPresent([Int].self, forKey: .stagingSel) ?? [], -1)
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
        performCells      = Snap.padCols(try c.decodeIfPresent([[String?]].self, forKey: .performCells) ?? [], Array(repeating: nil, count: 8))   // §E: 16-col part grid, old 8-col saves padded
        performChain      = Snap.padCols(try c.decodeIfPresent([[[ProcessorSlot]]].self, forKey: .performChain) ?? [], Array(repeating: [], count: 8))
        performRecv       = try c.decodeIfPresent([Int].self, forKey: .performRecv) ?? Array(repeating: 0, count: 8)
        performEmit       = try c.decodeIfPresent([Set<Bus>].self, forKey: .performEmit) ?? Array(repeating: [.a], count: 8)
        performPart       = try c.decodeIfPresent([Int].self, forKey: .performPart) ?? Array(repeating: -1, count: 8)
        performMute       = try c.decodeIfPresent(Set<Int>.self, forKey: .performMute) ?? []
        performStagingRow = try c.decodeIfPresent([Int].self, forKey: .performStagingRow) ?? Array(repeating: -1, count: 8)
        performLane       = try c.decodeIfPresent(UInt16.self, forKey: .performLane) ?? 0
        row8On            = try c.decodeIfPresent([Bool].self, forKey: .row8On) ?? Array(repeating: false, count: 8)
        name              = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}
