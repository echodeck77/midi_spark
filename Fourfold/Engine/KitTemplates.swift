//  KitTemplates.swift — KIT TEMPLATES ferry (draft 2, 2026-11-25): fixed drum-machine templates for the kit editor.
//
//  Static data only — the engine never reads this (it only ever sees `kitNotes`); the kit editor reads it to set a
//  lane's 8 ranks (notes + names) and to name the keyboard's keys (§4). §1.4: MAPS and ROWS are separate so several
//  rows share one map (the TR family shares `tr`, the chromatic-from-36 apps share `chrom36`) — a map holds the 8
//  ranks + the keys, a row names a map (+ optionally its own keys). `euclideousKitTemplate(…)` returns a RESOLVED row
//  (the public shape below), so the UI is map/row-agnostic. `KitTemplatesTests` pins the invariants.

import Foundation

enum EuclideousKitTemplateGroup: Equatable { case gm, apps, hardware }
enum EuclideousKitTemplateConfidence: Equatable { case verified, secondary, community }
struct EuclideousKitRank: Equatable { let note: UInt8; let name: String }
/// A resolved row (row fields + its map's ranks/keys) — the shape the kit editor + picker read.
struct EuclideousKitTemplate: Equatable {
    let id: String
    let name: String
    let group: EuclideousKitTemplateGroup
    let confidence: EuclideousKitTemplateConfidence
    let ranks: [EuclideousKitRank]
    let keys: [(note: UInt8, name: String)]
    static func == (a: EuclideousKitTemplate, b: EuclideousKitTemplate) -> Bool { a.id == b.id }
    var notes: [UInt8] { ranks.map { $0.note } }
    var names: [String] { ranks.map { $0.name } }
    func keyName(_ note: UInt8) -> String? { keys.first { $0.note == note }?.name }   // §4
}

private func rk(_ p: [(UInt8, String)]) -> [EuclideousKitRank] { p.map { EuclideousKitRank(note: $0.0, name: $0.1) } }
private typealias K = [(note: UInt8, name: String)]

// MARK: - §5 shared MAPS (ranks + keys)
private let gmRanks = rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (44, "PH"), (46, "OH"), (49, "CRASH")])
private let gmKeys: K = (UInt8(35)...UInt8(81)).map { ($0, euclideousGMDrumName($0)) }   // §5 GM keys = the 1.5 table
private let trRanks = rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (49, "CRASH")])
private let trKeys: K = [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (47, "MT"), (49, "CRASH"), (50, "HT"), (51, "RIDE")]
private let chromRanks = rk([(36, "PAD 1"), (37, "PAD 2"), (38, "PAD 3"), (39, "PAD 4"), (40, "PAD 5"), (41, "PAD 6"), (42, "PAD 7"), (43, "PAD 8")])
private let chromKeys: K = chromRanks.map { ($0.note, $0.name) } + [(44, "PAD 9"), (45, "PAD 10"), (46, "PAD 11"), (47, "PAD 12"), (48, "PAD 13"), (49, "PAD 14"), (50, "PAD 15"), (51, "PAD 16")]

private func row(_ id: String, _ name: String, _ group: EuclideousKitTemplateGroup, _ conf: EuclideousKitTemplateConfidence,
                 ranks: [EuclideousKitRank], keys: K) -> EuclideousKitTemplate {
    EuclideousKitTemplate(id: id, name: name, group: group, confidence: conf, ranks: ranks, keys: keys)
}

/// §5 the rows, in picker order (GM, then APPS, then HARDWARE).
let euclideousKitTemplates: [EuclideousKitTemplate] = [
    row("gm", "GM", .gm, .verified, ranks: gmRanks, keys: gmKeys),

    // APPS
    row("ableton", "ABLETON", .apps, .secondary, ranks: chromRanks, keys: chromKeys),
    row("ar909", "AR-909", .apps, .community,
        ranks: rk([(36, "KICK"), (40, "RIM"), (37, "SNR"), (41, "CLAP"), (38, "CH"), (42, "LT"), (39, "OH"), (46, "CRASH")]),
        keys: [(36, "KICK"), (37, "SNR"), (38, "CH"), (39, "OH"), (40, "RIM"), (41, "CLAP"), (42, "LT"), (43, "MT"), (44, "HT"), (45, "RIDE"), (46, "CRASH")]),
    row("beathawk", "BEATHAWK", .apps, .community, ranks: chromRanks, keys: chromKeys),
    row("digistix", "DIGISTIX", .apps, .community,
        ranks: rk([(48, "KICK"), (54, "RIM"), (49, "SNR"), (53, "CLAP"), (50, "CH"), (58, "LT"), (51, "OH"), (60, "CRASH")]),
        keys: [(48, "KICK"), (49, "SNR"), (50, "CH"), (51, "OH"), (52, "KICK 2"), (53, "CLAP"), (54, "RIM"), (55, "PERC"), (56, "HT"), (57, "MT"), (58, "LT"), (59, "F TOM"), (60, "CRASH"), (61, "SHAKER"), (62, "RIDE"), (63, "TAMB")]),
    row("egpulse", "EG PULSE", .apps, .community,
        ranks: rk([(36, "PAD 1"), (38, "PAD 2"), (42, "PAD 3"), (46, "PAD 4"), (49, "PAD 5"), (50, "PAD 6"), (47, "PAD 7"), (43, "PAD 8")]),
        keys: [(36, "PAD 1"), (38, "PAD 2"), (42, "PAD 3"), (46, "PAD 4"), (49, "PAD 5"), (50, "PAD 6"), (47, "PAD 7"), (43, "PAD 8"), (37, "PAD 9"), (39, "PAD 10"), (40, "PAD 11"), (41, "PAD 12"), (44, "PAD 13"), (45, "PAD 14"), (48, "PAD 15"), (51, "PAD 16")]),
    row("egdr808", "EGDR808", .apps, .community,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (49, "CYM")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (47, "MT"), (49, "CYM"), (50, "HT"), (56, "COWB")]),
    row("fac-drumkit", "FAC DRUMKIT", .apps, .community, ranks: chromRanks, keys: chromKeys),
    row("gadget", "GADGET", .apps, .community, ranks: chromRanks, keys: chromKeys),
    row("gr16", "GR-16", .apps, .community, ranks: chromRanks, keys: chromKeys),
    row("hammerhead", "HAMMERHEAD", .apps, .community,
        ranks: rk([(36, "KICK"), (45, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (48, "SNR 2"), (46, "OH"), (50, "COWB")]),
        keys: [(36, "KICK"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "RIM"), (46, "OH"), (48, "SNR 2"), (50, "COWB"), (49, "KICK"), (51, "SNR"), (54, "CLAP"), (56, "RIM"), (58, "SNR 2"), (61, "COWB"), (63, "CH"), (66, "OH")]),
    row("koala", "KOALA", .apps, .community, ranks: chromRanks, keys: chromKeys),
    row("microtonic", "MICROTONIC", .apps, .secondary, ranks: chromRanks, keys: chromKeys),
    row("mv08", "MV08", .apps, .community,
        ranks: rk([(60, "KICK"), (66, "RIM"), (61, "SNR"), (62, "CLAP"), (70, "CH"), (63, "LT"), (69, "OH"), (68, "CYM")]),
        keys: [(60, "KICK"), (61, "SNR"), (62, "CLAP"), (63, "LT"), (64, "MT"), (65, "HT"), (66, "RIM"), (67, "BELL"), (68, "CYM"), (69, "OH"), (70, "CH"), (71, "L CNGA"), (72, "M CNGA"), (73, "H CNGA"), (74, "CLAVE"), (75, "MARACA")]),
    row("ruismaker", "RUISMAKER", .apps, .secondary,
        ranks: rk([(49, "KICK"), (61, "HT"), (51, "SNR"), (54, "CLAP"), (63, "CH"), (56, "LT"), (66, "OH"), (58, "MT")]),
        keys: [(49, "KICK"), (51, "SNR"), (54, "CLAP"), (56, "LT"), (58, "MT"), (61, "HT"), (63, "CH"), (66, "OH")]),
    row("ruismaker-fm", "RUISMAKER FM", .apps, .community,
        ranks: rk([(49, "KICK"), (54, "FX1"), (51, "SNR"), (51, "SNR"), (58, "CH"), (56, "FX2"), (61, "OH"), (61, "OH")]),
        keys: [(49, "KICK"), (51, "SNR"), (54, "FX1"), (56, "FX2"), (58, "CH"), (61, "OH")]),
    row("va-drum-sm", "VA DRUM SM", .apps, .community,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (49, "CYM")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (40, "KICK 2"), (41, "LT 2"), (42, "CH"), (43, "MT 2"), (44, "HT 2"), (45, "LT"), (46, "OH"), (47, "MT"), (48, "HT"), (49, "CYM"), (50, "COWB"), (51, "SNR 2")]),
    row("va-drum2", "VA DRUM2", .apps, .community,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (40, "CH"), (42, "LT"), (41, "OH"), (45, "CYM")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (40, "CH"), (41, "OH"), (42, "LT"), (43, "MT"), (44, "HT"), (45, "CYM"), (46, "COWB"), (47, "L CNGA"), (48, "M CNGA"), (49, "H CNGA"), (50, "MARACA"), (51, "CLAVE"), (52, "KICK 2"), (53, "RIM 2"), (54, "SNR 2"), (55, "CLAP 2"), (56, "CH 2"), (57, "OH 2"), (58, "LT 2"), (59, "MT 2"), (60, "HT 2"), (61, "CRASH"), (62, "RIDE")]),

    // HARDWARE
    row("circuit-rhythm", "CIRCUIT RHYTHM", .hardware, .verified,
        ranks: rk([(36, "TRK 1"), (38, "TRK 2"), (40, "TRK 3"), (41, "TRK 4"), (43, "TRK 5"), (45, "TRK 6"), (47, "TRK 7"), (48, "TRK 8")]),
        keys: [(36, "TRK 1"), (38, "TRK 2"), (40, "TRK 3"), (41, "TRK 4"), (43, "TRK 5"), (45, "TRK 6"), (47, "TRK 7"), (48, "TRK 8")]),
    row("drumlogue", "DRUMLOGUE", .hardware, .verified,
        ranks: rk([(36, "KICK"), (37, "RIM"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (52, "SP1")]),
        keys: [(36, "KICK"), (37, "RIM"), (39, "CLAP"), (40, "SNR"), (42, "CH"), (45, "LT"), (46, "OH"), (50, "HT"), (52, "SP1"), (53, "SP2"), (55, "MULTI")]),
    row("mpc", "MPC", .hardware, .secondary, ranks: chromRanks, keys: chromKeys),
    row("mpc-classic", "MPC CLASSIC", .hardware, .secondary,
        ranks: rk([(37, "PAD 1"), (36, "PAD 2"), (42, "PAD 3"), (82, "PAD 4"), (40, "PAD 5"), (38, "PAD 6"), (46, "PAD 7"), (44, "PAD 8")]),
        keys: [(37, "PAD 1"), (36, "PAD 2"), (42, "PAD 3"), (82, "PAD 4"), (40, "PAD 5"), (38, "PAD 6"), (46, "PAD 7"), (44, "PAD 8")]),
    row("rd6", "RD-6", .hardware, .secondary,
        ranks: rk([(36, "KICK"), (50, "HT"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
        keys: [(36, "KICK"), (50, "HT"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
    row("rd8", "RD-8", .hardware, .secondary,
        ranks: rk([(36, "KICK"), (37, "RIM"), (40, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (51, "CYM")]),
        keys: [(36, "KICK"), (37, "RIM"), (39, "CLAP"), (40, "SNR"), (42, "CH"), (45, "LT"), (46, "OH"), (47, "MT"), (50, "HT"), (51, "CYM"), (56, "COWB")]),
    row("rd9", "RD-9", .hardware, .secondary,
        ranks: rk([(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (49, "CRASH")]),
        keys: [(36, "KICK"), (37, "RIM"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (45, "LT"), (46, "OH"), (47, "MT"), (49, "CRASH"), (50, "HT"), (51, "RIDE")]),
    row("sp404mk2", "SP-404MKII", .hardware, .community, ranks: chromRanks, keys: chromKeys),
    row("tr06", "TR-06", .hardware, .verified,
        ranks: rk([(36, "KICK"), (50, "HT"), (38, "SNR"), (38, "SNR"), (42, "CH"), (47, "LT"), (46, "OH"), (49, "CYM")]),
        keys: [(36, "KICK"), (38, "SNR"), (42, "CH"), (46, "OH"), (47, "LT"), (49, "CYM"), (50, "HT")]),
    row("tr707", "TR-707", .hardware, .secondary, ranks: trRanks, keys: trKeys + [(54, "TAMB"), (56, "COWB")]),
    row("tr8", "TR-8", .hardware, .verified, ranks: trRanks, keys: trKeys),
    row("tr8s", "TR-8S", .hardware, .verified, ranks: trRanks, keys: trKeys),
    row("tr09", "TR-09", .hardware, .verified, ranks: trRanks, keys: trKeys),
    row("tr909", "TR-909", .hardware, .secondary, ranks: trRanks, keys: trKeys),
    row("tr1000", "TR-1000", .hardware, .verified, ranks: trRanks, keys: trKeys.filter { $0.note != 47 }),
    row("volca-beats", "VOLCA BEATS", .hardware, .verified,
        ranks: rk([(36, "KICK"), (43, "LT"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (50, "HT"), (46, "OH"), (49, "CRASH")]),
        keys: [(36, "KICK"), (38, "SNR"), (39, "CLAP"), (42, "CH"), (43, "LT"), (46, "OH"), (49, "CRASH"), (50, "HT"), (67, "AGOGO"), (75, "CLAVE")]),
]

/// The row for `id` (nil / unknown ⇒ GM) — §1.1.
func euclideousKitTemplate(id: String?) -> EuclideousKitTemplate {
    guard let id = id, let t = euclideousKitTemplates.first(where: { $0.id == id }) else { return euclideousKitTemplates[0] }
    return t
}
/// The picker's rows: COMMUNITY rows appear only when `includeCommunity` (a DEBUG build), §3.5/§0.4.
func euclideousKitTemplatesForPicker(includeCommunity: Bool) -> [EuclideousKitTemplate] {
    euclideousKitTemplates.filter { includeCommunity || $0.confidence != .community }
}
