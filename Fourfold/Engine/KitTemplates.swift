//  KitTemplates.swift — KIT TEMPLATES ferry (2026-11-25): fixed drum-machine templates for the kit editor.
//
//  Static data only — the engine never reads this (it only ever sees `kitNotes`); the kit editor reads it to set
//  a lane's 8 ranks (notes + names) and to name the keyboard's keys (§4). Every value is from §5 of the ferry;
//  `KitTemplatesTests` pins the invariants (8 ranks, notes 0–127, names ≤6 chars uppercase, each rank note in `keys`
//  with the same name, unique ids). COMMUNITY-confidence rows show in the picker only in a DEBUG build (§0.4/§3.5).

import Foundation

enum EuclideousKitTemplateGroup: Equatable { case gm, apps, hardware }
enum EuclideousKitTemplateConfidence: Equatable { case verified, secondary, community }
struct EuclideousKitRank: Equatable { let note: UInt8; let name: String }
struct EuclideousKitTemplate: Equatable {
    let id: String
    let name: String
    let group: EuclideousKitTemplateGroup
    let confidence: EuclideousKitTemplateConfidence
    let ranks: [EuclideousKitRank]                 // exactly 8 (rank 1→8)
    let keys: [(note: UInt8, name: String)]         // a superset of the rank notes (§1.4)
    static func == (a: EuclideousKitTemplate, b: EuclideousKitTemplate) -> Bool { a.id == b.id }
    var notes: [UInt8] { ranks.map { $0.note } }
    var names: [String] { ranks.map { $0.name } }
    /// §4: the device's name for a note, if it answers on it.
    func keyName(_ note: UInt8) -> String? { keys.first { $0.note == note }?.name }
}

private func rk(_ pairs: [(UInt8, String)]) -> [EuclideousKitRank] { pairs.map { EuclideousKitRank(note: $0.0, name: $0.1) } }
/// §5 GM "keys": the GM short names across 35…81 (the ferry's 1.5 table).
private let euclideousGMKeys: [(note: UInt8, name: String)] = (UInt8(35)...UInt8(81)).map { ($0, euclideousGMDrumName($0)) }

/// §5 the template table, in picker order (GM, then APPS, then HARDWARE).
let euclideousKitTemplates: [EuclideousKitTemplate] = [
    EuclideousKitTemplate(id: "gm", name: "GM", group: .gm, confidence: .verified,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (44, "PH"), (46, "OH"), (49, "CRASH")]),
        keys: euclideousGMKeys),

    // APPS
    EuclideousKitTemplate(id: "ableton", name: "ABLETON", group: .apps, confidence: .secondary,
        ranks: rk([(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
        keys: [(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
    EuclideousKitTemplate(id: "gadget", name: "GADGET", group: .apps, confidence: .community,
        ranks: rk([(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
        keys: [(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
    EuclideousKitTemplate(id: "koala", name: "KOALA", group: .apps, confidence: .community,
        ranks: rk([(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
        keys: [(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")]),
    EuclideousKitTemplate(id: "microtonic", name: "MICROTONIC", group: .apps, confidence: .secondary,
        ranks: rk([(36, "CH 1"), (37, "CH 2"), (38, "CH 3"), (39, "CH 4"), (40, "CH 5"), (41, "CH 6"), (42, "CH 7"), (43, "CH 8")]),
        keys: [(36, "CH 1"), (37, "CH 2"), (38, "CH 3"), (39, "CH 4"), (40, "CH 5"), (41, "CH 6"), (42, "CH 7"), (43, "CH 8")]),
    EuclideousKitTemplate(id: "ruismaker", name: "RUISMAKER", group: .apps, confidence: .secondary,   // SECONDARY notes, COMMUNITY names (shows in release per §5)
        ranks: rk([(49, "KICK"), (51, "SNR"), (54, "CLAP"), (56, "TOM 1"), (58, "TOM 2"), (61, "TOM 3"), (63, "CH"), (66, "OH")]),
        keys: [(49, "KICK"), (51, "SNR"), (54, "CLAP"), (56, "TOM 1"), (58, "TOM 2"), (61, "TOM 3"), (63, "CH"), (66, "OH")]),
    EuclideousKitTemplate(id: "digistix", name: "DIGISTIX", group: .apps, confidence: .community,
        ranks: rk([(48, "KICK"), (54, "RIM"), (49, "SNR"), (53, "CLAP"), (50, "CH"), (58, "LT"), (51, "OH"), (60, "CRASH")]),
        keys: [(48, "KICK"), (49, "SNR"), (50, "CH"), (51, "OH"), (52, "KICK 2"), (53, "CLAP"), (54, "RIM"), (55, "PERC"), (56, "HT"), (57, "MT"), (58, "LT"), (59, "F TOM"), (60, "CRASH"), (61, "SHAKER"), (62, "RIDE"), (63, "TAMB")]),

    // HARDWARE
    EuclideousKitTemplate(id: "circuit-rhythm", name: "CIRCUIT RHYTHM", group: .hardware, confidence: .verified,
        ranks: rk([(36, "TRK 1"), (38, "TRK 2"), (40, "TRK 3"), (41, "TRK 4"), (43, "TRK 5"), (45, "TRK 6"), (47, "TRK 7"), (48, "TRK 8")]),
        keys: [(36, "TRK 1"), (38, "TRK 2"), (40, "TRK 3"), (41, "TRK 4"), (43, "TRK 5"), (45, "TRK 6"), (47, "TRK 7"), (48, "TRK 8")]),
    EuclideousKitTemplate(id: "drumlogue", name: "DRUMLOGUE", group: .hardware, confidence: .verified,
        ranks: rk([(36, "KICK"), (37, "RIM"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (52, "SP1")]),
        keys: [(36, "KICK"), (37, "RIM"), (39, "CLAP"), (40, "SNR"), (42, "CH"), (45, "LT"), (46, "OH"), (50, "HT"), (52, "SP1"), (53, "SP2"), (55, "MULTI")]),
    EuclideousKitTemplate(id: "mpc", name: "MPC", group: .hardware, confidence: .secondary,
        ranks: rk([(37, "PAD 1"), (36, "PAD 2"), (42, "PAD 3"), (82, "PAD 4"), (40, "PAD 5"), (38, "PAD 6"), (46, "PAD 7"), (44, "PAD 8")]),
        keys: [(37, "PAD 1"), (36, "PAD 2"), (42, "PAD 3"), (82, "PAD 4"), (40, "PAD 5"), (38, "PAD 6"), (46, "PAD 7"), (44, "PAD 8")]),
    EuclideousKitTemplate(id: "rd6", name: "RD-6", group: .hardware, confidence: .secondary,
        ranks: rk([(36, "KICK"), (50, "HT"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
        keys: [(36, "KICK"), (50, "HT"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
    EuclideousKitTemplate(id: "rd8", name: "RD-8", group: .hardware, confidence: .secondary,
        ranks: rk([(36, "KICK"), (37, "RIM"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
        keys: [(36, "KICK"), (37, "RIM"), (39, "CLAP"), (40, "SNR"), (42, "CH"), (45, "LT"), (46, "OH"), (47, "MT"), (50, "HT"), (51, "CYM"), (56, "COWB")]),
    EuclideousKitTemplate(id: "rd9", name: "RD-9", group: .hardware, confidence: .secondary,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (49, "CRASH")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (47, "MT"), (49, "CRASH"), (50, "HT"), (51, "RIDE")]),
    EuclideousKitTemplate(id: "tr8s", name: "TR-8S", group: .hardware, confidence: .verified,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (49, "CRASH")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (47, "MT"), (49, "CRASH"), (50, "HT"), (51, "RIDE")]),
    EuclideousKitTemplate(id: "volca-beats", name: "VOLCA BEATS", group: .hardware, confidence: .verified,
        ranks: rk([(36, "KICK"), (43, "LT"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (50, "HT"), (46, "OH"), (49, "CRASH")]),
        keys: [(36, "KICK"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (49, "CRASH"), (50, "HT"), (67, "AGOGO"), (75, "CLAVE")]),
]

/// The template for `id` (nil / unknown ⇒ GM) — §1.1.
func euclideousKitTemplate(id: String?) -> EuclideousKitTemplate {
    guard let id = id, let t = euclideousKitTemplates.first(where: { $0.id == id }) else { return euclideousKitTemplates[0] }
    return t
}
/// The picker's rows, filtered by confidence: COMMUNITY rows appear only when `includeCommunity` (a DEBUG build), §3.5/§0.4.
func euclideousKitTemplatesForPicker(includeCommunity: Bool) -> [EuclideousKitTemplate] {
    euclideousKitTemplates.filter { includeCommunity || $0.confidence != .community }
}
