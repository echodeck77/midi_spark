//  SceneFactory.swift
//  MidiSpark — the sixteen FACTORY SCENES that ship in the scene strip (Docs/factory-scenes.md).
//  A curriculum, slot 1 → 16: each is musical alone and introduces one capability; 16 uses nearly
//  everything. DISTINCT from TestSessions T1–T17 (engine coverage) — never merge the two.
//
//  Foundation-only (seam rule: engine-adjacent, no AudioToolbox). Each scene is a complete
//  PluginState (formatVersion 3, one scene). Doc notation is 1-based (columns C1–C8, rows R1–R8,
//  inputRow ⇐Rn); the builder converts to 0-based. Unlisted params take the Colour-type defaults.

import Foundation

enum SceneFactory {
    struct Scene { let name: String; let make: () -> PluginState }

    static func load(_ i: Int) -> PluginState { scenes[i].make() }

    // MARK: - builder

    private final class B {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        var scene = SceneState.empty()
        var busCh = [1, 2, 3, 4]

        func global(step: StepRate = .r1_2, swing: Int = 50) { scene.stepRate = step; scene.swing = swing }
        func buses(_ a: Int, _ b: Int, _ c: Int, _ d: Int) { busCh = [a, b, c, d] }

        // Colour configurators (A-state); alt* set the B-state (sparse over A).
        private func edit(_ id: String, _ f: (inout Colour) -> Void) {
            if let i = colourIDs.firstIndex(of: id) { f(&colours[i]) }
        }
        func arp(_ id: String, _ pattern: ArpPattern = .up, _ rate: ArpRate = .r1_16,
                 oct: Int = 1, gate: Double = 0.6, phase: ArpPhase = .retrig, t: Int = 0) {
            edit(id) { c in
                c.type = .arp; c.transpose = t
                c.paramsA.pattern = pattern; c.paramsA.rate = rate; c.paramsA.octaves = oct
                c.paramsA.gate = gate; c.paramsA.phase = phase
            }
        }
        func altArp(_ id: String, pattern: ArpPattern? = nil, rate: ArpRate? = nil, oct: Int? = nil) {
            edit(id) { c in
                if let p = pattern { c.paramsB.pattern = p }
                if let r = rate { c.paramsB.rate = r }
                if let o = oct { c.paramsB.octaves = o }
            }
        }
        func ratchet(_ id: String, count: Int = 3, t: Int = 0) {
            edit(id) { c in c.type = .ratchet; c.transpose = t; c.paramsA.count = count }
        }
        func altRatchet(_ id: String, count: Int) { edit(id) { $0.paramsB.count = count } }
        func pass(_ id: String, _ passes: [Bool] = [true, true, true, true], gate: Double = 0.6, t: Int = 0) {
            edit(id) { c in c.type = .passgate; c.transpose = t; c.paramsA.passes = passes; c.paramsA.gate = gate }
        }
        func chance(_ id: String, _ prob: Double, t: Int = 0) {
            edit(id) { c in c.type = .chance; c.transpose = t; c.paramsA.probability = prob }
        }
        func altChance(_ id: String, _ prob: Double) { edit(id) { $0.paramsB.probability = prob } }
        func harmonize(_ id: String, _ intervals: [Int] = [0, 0, 0], t: Int = 0) {
            edit(id) { c in c.type = .harmonize; c.transpose = t; c.paramsA.harmIntervals = intervals }
        }

        /// Place a cell. 1-based col/row; `from` is a 1-based referenced row (nil = MIDI IN).
        func put(_ col: Int, _ row: Int, _ id: String, from: Int? = nil, ch: Int = 0,
                 to bus: [Bus] = [.a], alt: Bool = false, muted: Bool = false) {
            var cell = Cell(colourID: id)
            cell.inputRow = from.map { $0 - 1 }
            cell.inputChannel = ch
            cell.buses = Set(bus)
            cell.alt = alt
            cell.muted = muted
            scene.cells[col - 1][row - 1] = cell
        }

        func build() -> PluginState {
            var s = PluginState(colours: colours, scenes: [scene])
            s.busChannels = busCh
            s.formatVersion = 3
            return s
        }
    }

    // MARK: - the sixteen scenes

    static let scenes: [Scene] = [

        Scene(name: "FIRST LIGHT") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16, oct: 1, gate: 0.6)
            b.put(1, 1, "gold", to: [.a])
            return b.build()
        },

        Scene(name: "FOUR ON THE FLOOR") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16, oct: 1)
            for col in [1, 3, 5, 7] { b.put(col, 1, "gold", to: [.a]) }
            return b.build()
        },

        Scene(name: "CALL AND ANSWER") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16); b.arp("azure", .down, .r1_16)
            for col in 1...4 { b.put(col, 1, "gold", to: [.a]) }
            for col in 5...8 { b.put(col, 1, "azure", to: [.b]) }
            return b.build()
        },

        Scene(name: "STAIRCASE") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16, t: 0); b.arp("mint", .up, .r1_16, t: 5)
            b.arp("azure", .up, .r1_16, t: 7); b.arp("violet", .up, .r1_16, t: 12)
            for col in [1, 2] { b.put(col, 1, "gold", to: [.a]) }
            for col in [3, 4] { b.put(col, 1, "mint", to: [.a]) }
            for col in [5, 6] { b.put(col, 1, "azure", to: [.a]) }
            for col in [7, 8] { b.put(col, 1, "violet", to: [.a]) }
            return b.build()
        },

        Scene(name: "THE LIMP") {
            let b = B(); b.global(swing: 62)
            b.arp("gold", .up, .r1_16); b.ratchet("vermilion", count: 3)
            for col in [1, 3, 5, 7] { b.put(col, 1, "gold", to: [.a]) }
            for col in [2, 4, 6, 8] { b.put(col, 1, "vermilion", to: [.a]) }
            return b.build()
        },

        Scene(name: "CHAIN OF COMMAND") {
            let b = B(); b.global()
            b.arp("violet", .upDown, .r1_8, oct: 2); b.ratchet("vermilion", count: 2)
            for col in 1...8 {
                b.put(col, 1, "violet", to: [])           // pure engine, no buses
                b.put(col, 2, "vermilion", from: 1, to: [.a])
            }
            return b.build()
        },

        Scene(name: "TWO HANDS") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16); b.arp("wine", .down, .r1_4, oct: 1, gate: 0.9)
            for col in 1...8 {
                b.put(col, 1, "gold", ch: 1, to: [.a])    // right hand, ch1
                b.put(col, 2, "wine", ch: 2, to: [.b])    // left hand, ch2
            }
            return b.build()
        },

        Scene(name: "THE FAN") {
            let b = B(); b.global()
            b.arp("violet", .asPlayed, .r1_8, oct: 2); b.ratchet("vermilion", count: 3)
            b.chance("magenta", 0.65); b.arp("azure", .up, .r1_16)
            for col in 1...8 {
                b.put(col, 1, "violet", to: [])
                b.put(col, 2, "vermilion", from: 1, to: [.a])
                b.put(col, 3, "magenta", from: 1, to: [.b])
                b.put(col, 4, "azure", from: 2, to: [.c])
            }
            return b.build()
        },

        Scene(name: "EVERY OTHER TIME") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16)
            b.pass("teal", [true, false, true, false])                       // every 2nd
            b.pass("wine", [true, false, false, false], gate: 1.0, t: -12)   // every 4th
            for col in 1...8 { b.put(col, 1, "gold", to: [.a]) }
            for col in [1, 5] { b.put(col, 2, "teal", to: [.b]) }
            b.put(1, 3, "wine", to: [.c])
            return b.build()
        },

        Scene(name: "DICE MUSIC") {
            let b = B(); b.global(swing: 54)
            b.chance("magenta", 0.70); b.chance("blush", 0.35, t: 12)
            b.arp("gold", .random, .r1_16); b.ratchet("vermilion", count: 4)
            for col in 1...8 {
                b.put(col, 1, "gold", to: [])
                b.put(col, 2, "magenta", from: 1, to: [.a])
            }
            for col in [2, 4, 6, 8] { b.put(col, 3, "blush", from: 1, to: [.b]) }
            for col in [4, 8] { b.put(col, 4, "vermilion", from: 2, to: [.a]) }
            return b.build()
        },

        Scene(name: "LONG WALK") {
            let b = B(); b.global()
            b.arp("violet", .up, .r1_16, oct: 2, phase: .legato)
            b.arp("teal", .upDown, .r1_8t, oct: 1, phase: .free)
            b.arp("gold", .up, .r1_16, phase: .retrig)
            for col in 1...4 { b.put(col, 1, "violet", to: [.a]) }   // 4-column LEGATO run
            for col in 5...8 { b.put(col, 2, "teal", to: [.b]) }
            for col in 5...8 { b.put(col, 1, "gold", to: [.a]) }
            return b.build()
        },

        Scene(name: "UNDERTOW") {
            let b = B(); b.global(step: .r1_1)
            b.arp("indigo", .up, .r1_8, oct: 2); b.chance("magenta", 0.80)
            b.ratchet("vermilion", count: 2); b.pass("wine", gate: 1.0, t: -12)
            b.arp("chartreuse", .up, .r1_32, oct: 1, t: 12)
            for col in 1...8 {
                b.put(col, 1, "indigo", to: [])
                b.put(col, 2, "magenta", from: 1, to: [])
                b.put(col, 3, "vermilion", from: 2, to: [.a])
                b.put(col, 4, "wine", from: 1, to: [.b])
                b.put(col, 5, "chartreuse", from: 3, to: [.c])
            }
            return b.build()
        },

        Scene(name: "TWO ROOMS") {
            let b = B(); b.global(); b.buses(1, 2, 3, 10)
            b.arp("gold", .up, .r1_16); b.arp("wine", .asPlayed, .r1_4, gate: 1.0, t: -24)   // doc says 1/2; slowest arp rate is 1/4
            b.arp("azure", .upDown, .r1_16t, t: 12); b.ratchet("bronze", count: 3)
            for col in 1...8 { b.put(col, 1, "gold", to: [.a]) }
            for col in 1...8 { b.put(col, 2, "wine", to: [.b]) }
            for col in [3, 7] { b.put(col, 3, "azure", to: [.c]) }
            for col in [4, 8] { b.put(col, 4, "bronze", from: 1, to: [.d]) }
            return b.build()
        },

        Scene(name: "ALT EGO") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16); b.altArp("gold", pattern: .down, rate: .r1_32, oct: 2)
            b.arp("azure", .upDown, .r1_8); b.altArp("azure", pattern: .random, rate: .r1_16t)
            b.ratchet("vermilion", count: 2); b.altRatchet("vermilion", count: 4)
            b.chance("magenta", 0.90); b.altChance("magenta", 0.40)
            for col in [1, 2] { b.put(col, 1, "gold", to: [.a]) }
            for col in [3, 4] { b.put(col, 1, "azure", to: [.a]) }
            for col in [5, 6] { b.put(col, 1, "vermilion", to: [.b]) }
            for col in [7, 8] { b.put(col, 1, "magenta", to: [.b]) }
            for col in [5, 6] { b.put(col, 2, "gold", from: 1, to: [.a]) }
            return b.build()
        },

        Scene(name: "THE LOOP THAT ISN'T") {
            let b = B(); b.global()
            b.arp("gold", .up, .r1_16); b.arp("azure", .down, .r1_8)
            b.ratchet("purple", count: 3); b.pass("teal")
            for col in 1...4 {
                b.put(col, 2, "gold", to: [.a])
                b.put(col, 1, "azure", from: 2, to: [.b])     // backward tap: child above parent
            }
            for col in [6, 7] {
                b.put(col, 3, "purple", from: 5, to: [.c])    // ↺ cycle: R3⇐R5 and R5⇐R3
                b.put(col, 5, "teal", from: 3, to: [.c])      //   both lit, both silent, forever
            }
            return b.build()
        },

        Scene(name: "PACIFIC") {
            let b = B(); b.global(swing: 57); b.buses(1, 2, 3, 4)
            b.arp("violet", .up, .r1_16, oct: 2, phase: .legato)
            b.arp("gold", .up, .r1_16); b.altArp("gold", rate: .r1_32)
            b.ratchet("vermilion", count: 3); b.altRatchet("vermilion", count: 4)
            b.chance("magenta", 0.60)
            b.pass("wine", [true, false, true, false], gate: 1.0, t: -12)   // every 2nd
            b.arp("azure", .upDown, .r1_16t, phase: .free, t: 12)
            b.pass("teal", gate: 1.0)
            b.harmonize("mint", [4, 7, 0], t: 7)   // intervals unlisted in doc → a major-triad pad (chosen)
            for col in 1...4 {
                b.put(col, 1, "violet", to: [])              // LEGATO lead engine
                b.put(col, 2, "gold", from: 1, to: [.a])
                b.put(col, 3, "wine", to: [.b])
            }
            for col in [5, 6] {
                b.put(col, 1, "violet", to: [])              // second run
                b.put(col, 2, "magenta", from: 1, to: [.a])
            }
            for col in 5...8 { b.put(col, 4, "azure", to: [.c]) }   // FREE shimmer
            for col in [7, 8] {
                b.put(col, 1, "gold", to: [.a])
                b.put(col, 2, "vermilion", from: 1, to: [.a])       // the build
            }
            for col in [2, 6] { b.put(col, 6, "teal", to: [.d]) }
            for col in [4, 8] { b.put(col, 6, "mint", to: [.d]) }   // pad room on D
            return b.build()
        },
    ]
}
