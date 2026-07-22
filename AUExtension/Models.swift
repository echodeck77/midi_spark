//  Models.swift
//  MidiSpark — document model per spec v2.8 §9.
//  Colour = the treatment · Cell = the patch point · Preset = host fullState (reserved word).

import Foundation

// MARK: - Vocabulary

enum ProcessorType: String, Codable, CaseIterable {
    case arp = "ARP", ratchet = "RATCHET", passgate = "PASSGATE"
    case strum = "STRUM", chance = "CHANCE", harmonize = "HARMONIZE"
    // §12: type IDs are append-only. Never reorder, never reuse.
}

enum ArpPattern: String, Codable, CaseIterable { case up = "UP", down = "DOWN", upDown = "UP-DN", random = "RANDOM", asPlayed = "AS PLAYED" }
enum ArpPhase: String, Codable, CaseIterable { case retrig = "RETRIG", legato = "LEGATO", free = "FREE" }   // §3.5
enum StepRate: String, Codable, CaseIterable {
    case r2_1 = "2/1", r1_1 = "1/1", r1_2 = "1/2", r1_2d = "1/2.", r1_4 = "1/4", r1_8 = "1/8"
    var beats: Double {
        switch self { case .r2_1: 8; case .r1_1: 4; case .r1_2: 2; case .r1_2d: 3; case .r1_4: 1; case .r1_8: 0.5 }
    }
}
enum ArpRate: String, Codable, CaseIterable {
    case r1_4 = "1/4", r1_8 = "1/8", r1_8t = "1/8T", r1_16 = "1/16", r1_16t = "1/16T", r1_32 = "1/32"
    var beats: Double {
        switch self { case .r1_4: 1; case .r1_8: 0.5; case .r1_8t: 1.0/3.0; case .r1_16: 0.25; case .r1_16t: 1.0/6.0; case .r1_32: 0.125 }
    }
}
enum Bus: String, Codable, CaseIterable { case a = "A", b = "B", c = "C", d = "D"
    var cable: UInt8 { UInt8(Bus.allCases.firstIndex(of: self)!) }
}
enum StrumDir: String, Codable, CaseIterable { case up = "UP", down = "DOWN", alternate = "ALT" }   // §3 STRUM
enum TapAction: String, Codable { case alt = "ALT", byp = "BYP", mute = "MUTE" }
enum Quant: String, Codable { case off = "OFF", step = "STEP", pass = "PASS" }                              // §6.8

let colourIDs: [String] = ["gold","orange","vermilion","wine","magenta","blush","purple","violet",
                           "indigo","azure","cyan","teal","mint","green","chartreuse","bronze"]

// MARK: - Colour (the treatment) — §1/§9

struct ColourParams: Codable, Equatable {
    // Superset of per-type params; only the active type's fields are meaningful. §12.0: append-only.
    var pattern: ArpPattern? = .up
    var rate: ArpRate? = .r1_16
    var octaves: Int? = 1
    var gate: Double? = 0.6
    var phase: ArpPhase? = .retrig
    var count: Int? = 3            // ratchet
    var ramp: Double? = 0.5        // ratchet
    var passes: [Bool]? = [true, true, true, true]  // passgate
    var strumDir: StrumDir? = .up  // strum
    var spread: Double? = 0.1      // strum: chord stagger in BEATS (0…1)
    var curve: Double? = 0         // strum: timing curve −1…1 (0 = linear)
    var velTilt: Double? = 0       // strum: velocity tilt −1…1 (0 = flat)
    var probability: Double? = 1   // chance: pass-through probability 0…1 per note-on
    // harmonize (§3): up to 3 added voices, each an interval −24…+24 st (0 = voice OFF), plus a
    // velocity scale 0.1…1 applied to the ADDED voices (root stays full). B overrides the intervals.
    var harmIntervals: [Int]? = [0, 0, 0]
    var harmVelScale: Double? = 0.8
}

struct Colour: Codable, Equatable {
    var colourID: String
    var type: ProcessorType
    // v3.0 (delta §7): per-Colour OUT CH is REMOVED — channel is a property of the WIRE (busChannels),
    // not the treatment. Old docs carrying an `outChannel` key decode fine (Codable ignores unknown keys).
    var transpose: Int = 0         // −24…+24, accumulates in chains, clamped
    var morph: Double = 0          // §3.2 — this IS the per-colour macro AUParameter
    var paramsA: ColourParams = ColourParams()
    var paramsB: ColourParams = ColourParams()   // sparse in spirit: unset fields inherit from A at merge time
}

// MARK: - Cell (the patch point) — §1.1: cells share nothing.

struct Cell: Codable, Equatable {
    var colourID: String
    var stack: Bool = false        // v2 LEGACY (▾) — decode-only after commit 3; removed at commit 4
    var buses: Set<Bus> = [.a]     // sound leaves ONLY through a lit letter (§2.3)
    var srcMix: Bool = false       // v2 LEGACY (+SRC) — no v3 equivalent; dropped on migration
    var alt: Bool = false
    var bypassed: Bool = false
    var muted: Bool = false
    // v3.0 (delta §1/§2): the cell's single input reference. nil = MIDI IN; else the referenced row
    // in the same column (any row; cycles legal-and-silent). Optional → old docs (no key) decode as
    // nil and are filled by migrateLegacyRoutingIfNeeded(); the render path uses SnapCell's Int
    // sentinel, not this.
    var inputRow: Int? = nil
    // v3.0 (delta §7): input-channel filter for a MIDI-IN cell. 0 = OMNI (default); 1–16 = only notes
    // arriving on that channel. Applies at the source boundary only (referenced parents aren't filtered).
    var inputChannel: Int = 0
}

// MARK: - Scene & document — §9

struct SceneState: Codable, Equatable {
    var cells: [[Cell?]]           // [column][row], 8×8
    var rowBypass: [Bool] = Array(repeating: false, count: 8)
    var stackMute: [Bool] = Array(repeating: false, count: 8)
    var stackSolo: [Bool] = Array(repeating: false, count: 8)
    var stepRate: StepRate = .r1_2
    var swing: Int = 50            // 50 straight … 75 (§4 v2.3)
    var tapAction: TapAction = .alt
    var quant: Quant = .off        // §6.8

    static func empty() -> SceneState {
        SceneState(cells: Array(repeating: Array(repeating: nil, count: 8), count: 8))
    }
}

struct PluginState: Codable, Equatable {
    var formatVersion: Int = 2     // 2 = v2.x chain routing · 3 = v3.0 graph routing (§migration)
    var colours: [Colour]
    var scenes: [SceneState]       // length 1 in v2.x; scenes are the flagship next feature
    var activeScene: Int = 0
    var morphMaster: Double = 0    // §13.5 — parameter #35, reserved & functional now
    var busChannels: [Int] = [1, 2, 3, 4]   // v3.0 (delta §7): each bus A–D stamps this channel on exit

    /// Migrate a legacy (v2.x) document to the v3.0 routing schema, in place. Idempotent and gated
    /// on formatVersion, so it is safe to call on every document entering the AU (load / factory /
    /// test session). Mapping (migration-tree-routing.md §1): a cell fed under the old model — i.e.
    /// the cell ABOVE is occupied and its `stack` is on — references that row (`inputRow = r-1`);
    /// everything else is MIDI IN (nil). `srcMix` has no v3 equivalent and is dropped (logged).
    /// The old fields are LEFT in place — the router still reads `stack` until the commit-3 flip.
    mutating func migrateLegacyRoutingIfNeeded() {
        guard formatVersion < 3 else { return }
        var droppedSrcMix = 0
        for si in scenes.indices {
            for col in scenes[si].cells.indices {
                for row in scenes[si].cells[col].indices {
                    guard var cell = scenes[si].cells[col][row] else { continue }
                    let aboveStacked = row > 0 && (scenes[si].cells[col][row - 1]?.stack ?? false)
                    cell.inputRow = aboveStacked ? row - 1 : nil
                    if cell.srcMix { droppedSrcMix += 1 }
                    scenes[si].cells[col][row] = cell
                }
            }
        }
        if droppedSrcMix > 0 {
            print("MidiSpark: migrated v2 document to graph routing; dropped +SRC on \(droppedSrcMix) cell(s) (no v3 equivalent).")
        }
        formatVersion = 3
    }

    static func factory() -> PluginState {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        // A few designed defaults so the factory session sounds immediately (§6.6) and demonstrates ALT.
        func idx(_ id: String) -> Int { colourIDs.firstIndex(of: id)! }
        colours[idx("gold")].paramsA.octaves = 2
        colours[idx("gold")].paramsB = { var b = ColourParams(); b.rate = .r1_32; b.octaves = 3; return b }()
        colours[idx("cyan")].type = .ratchet
        colours[idx("cyan")].paramsA.count = 4
        colours[idx("cyan")].paramsB.count = 8
        colours[idx("vermilion")].type = .passgate
        colours[idx("magenta")].transpose = 12

        var scene = SceneState.empty()
        scene.cells[0][0] = Cell(colourID: "gold")
        scene.cells[2][0] = Cell(colourID: "vermilion")
        scene.cells[2][1] = Cell(colourID: "magenta", buses: [.b], inputRow: 0)   // references row 0 (§1)
        scene.cells[4][0] = Cell(colourID: "gold")
        scene.cells[6][0] = Cell(colourID: "cyan")
        var state = PluginState(colours: colours, scenes: [scene])
        state.formatVersion = 3   // built directly in the v3.0 graph model
        return state
    }
}
