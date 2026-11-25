//  KitTemplatesTests.swift — KIT TEMPLATES ferry (2026-11-25): the static table invariants (§7.1) + GM equivalence (§7.2).

import XCTest

final class KitTemplatesTests: XCTestCase {

    // §7.1 — every template: 8 ranks, notes 0–127, names ≤6 upper, each rank note in `keys` with the same name, unique ids.
    func testTableInvariants() {
        var ids = Set<String>()
        for t in euclideousKitTemplates {
            XCTAssertTrue(ids.insert(t.id).inserted, "duplicate id \(t.id)")
            XCTAssertEqual(t.ranks.count, 8, "\(t.id) needs 8 ranks")
            for r in t.ranks {
                XCTAssertTrue(r.note <= 127, "\(t.id) note \(r.note) out of range")
                XCTAssertLessThanOrEqual(r.name.count, 6, "\(t.id) name '\(r.name)' > 6 chars")
                XCTAssertEqual(r.name, r.name.uppercased(), "\(t.id) name '\(r.name)' not uppercase")
                // the rank note appears in keys with the SAME name (§1.4)
                let kn = t.keyName(r.note)
                XCTAssertEqual(kn, r.name, "\(t.id) rank note \(r.note) (\(r.name)) absent/mismatched in keys (\(kn ?? "nil"))")
            }
            for k in t.keys { XCTAssertLessThanOrEqual(k.name.count, 6, "\(t.id) key '\(k.name)' > 6"); XCTAssertEqual(k.name, k.name.uppercased()) }
        }
    }

    // §7.2 — GM's ranks equal the kit ferry's default kit exactly.
    func testGMEqualsDefaultKit() {
        let gm = euclideousKitTemplate(id: "gm")
        XCTAssertEqual(gm.notes, euclideousKitDefaultNotes)
        XCTAssertEqual(gm.names, euclideousKitNamesResolved(nil, notes: euclideousKitDefaultNotes))
        XCTAssertEqual(euclideousKitTemplate(id: nil).id, "gm")       // §1.1 nil ⇒ gm
        XCTAssertEqual(euclideousKitTemplate(id: "nope").id, "gm")    // unknown ⇒ gm
    }

    // §3.5/§0.4/§5 release line — APPS shows only ABLETON, MICROTONIC, RUISMAKER; HARDWARE every row except SP-404MKII.
    func testCommunityFilter() {
        let release = euclideousKitTemplatesForPicker(includeCommunity: false)
        let relApps = release.filter { $0.group == .apps }.map { $0.id }
        XCTAssertEqual(relApps, ["ableton", "microtonic", "ruismaker"])
        let relHw = release.filter { $0.group == .hardware }.map { $0.id }
        XCTAssertFalse(relHw.contains("sp404mk2"))
        XCTAssertTrue(relHw.contains("tr8s") && relHw.contains("mpc-classic") && relHw.contains("tr06") && relHw.contains("volca-beats"))
        let dev = euclideousKitTemplatesForPicker(includeCommunity: true).map { $0.id }
        XCTAssertTrue(dev.contains("gadget") && dev.contains("digistix") && dev.contains("sp404mk2") && dev.contains("ruismaker-fm"))
    }

    // §7.5 — shared maps: TR-8 and TR-909 have identical ranks; TR-1000's key 47 is NOT in its keys (so the UI shows the GM name).
    func testSharedMaps() {
        XCTAssertEqual(euclideousKitTemplate(id: "tr8").notes, euclideousKitTemplate(id: "tr909").notes)
        XCTAssertEqual(euclideousKitTemplate(id: "tr8").names, euclideousKitTemplate(id: "tr909").names)
        XCTAssertEqual(euclideousKitTemplate(id: "tr8s").notes, euclideousKitTemplate(id: "tr09").notes)
        XCTAssertNil(euclideousKitTemplate(id: "tr1000").keyName(47), "TR-1000 drops key 47 ⇒ it reads its GM name")
        XCTAssertEqual(euclideousKitTemplate(id: "tr8").keyName(47), "MT")   // TR-8 keeps 47 MT
        // §7.5 (Ruismaker names, role order): key 49 KICK, 50 is not Ruismaker's (GM fallback), rank note set
        XCTAssertEqual(euclideousKitTemplate(id: "ruismaker").keyName(49), "KICK")
        XCTAssertNil(euclideousKitTemplate(id: "ruismaker").keyName(50))   // 50 not in its keys ⇒ GM (H TOM)
    }
}
