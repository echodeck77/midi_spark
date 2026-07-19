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
}

struct Colour: Codable, Equatable {
    var colourID: String
    var type: ProcessorType
    var outChannel: Int = 0        // 0 = INHERIT, 1–16 stamped (§2.6)
    var transpose: Int = 0         // −24…+24, accumulates in chains, clamped
    var morph: Double = 0          // §3.2 — this IS the per-colour macro AUParameter
    var paramsA: ColourParams = ColourParams()
    var paramsB: ColourParams = ColourParams()   // sparse in spirit: unset fields inherit from A at merge time
}

// MARK: - Cell (the patch point) — §1.1: cells share nothing.

struct Cell: Codable, Equatable {
    var colourID: String
    var stack: Bool = false        // ▾
    var buses: Set<Bus> = [.a]     // sound leaves ONLY through a lit letter (§2.3)
    var srcMix: Bool = false       // +SRC
    var alt: Bool = false
    var bypassed: Bool = false
    var muted: Bool = false
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
    var formatVersion: Int = 2
    var colours: [Colour]
    var scenes: [SceneState]       // length 1 in v2.x; scenes are the flagship next feature
    var activeScene: Int = 0
    var morphMaster: Double = 0    // §13.5 — parameter #35, reserved & functional now

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
        colours[idx("magenta")].outChannel = 2

        var scene = SceneState.empty()
        scene.cells[0][0] = Cell(colourID: "gold")
        scene.cells[2][0] = Cell(colourID: "vermilion", stack: true)
        scene.cells[2][1] = Cell(colourID: "magenta", buses: [.b])
        scene.cells[4][0] = Cell(colourID: "gold")
        scene.cells[6][0] = Cell(colourID: "cyan")
        return PluginState(colours: colours, scenes: [scene])
    }
}
