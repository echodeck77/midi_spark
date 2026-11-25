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

    // §3.5/§0.4 — the picker hides COMMUNITY rows in a release build, shows them in a dev build.
    func testCommunityFilter() {
        let release = euclideousKitTemplatesForPicker(includeCommunity: false).map { $0.id }
        XCTAssertFalse(release.contains("gadget")); XCTAssertFalse(release.contains("koala")); XCTAssertFalse(release.contains("digistix"))
        XCTAssertTrue(release.contains("ableton") && release.contains("microtonic") && release.contains("ruismaker"))
        // all 8 hardware show in release (none are COMMUNITY — the §5 "seven" is a miscount)
        let relHardware = euclideousKitTemplatesForPicker(includeCommunity: false).filter { $0.group == .hardware }
        XCTAssertEqual(relHardware.count, 8)
        let dev = euclideousKitTemplatesForPicker(includeCommunity: true).map { $0.id }
        XCTAssertTrue(dev.contains("gadget") && dev.contains("koala") && dev.contains("digistix"))
    }
}
