//  KitCardV2Tests.swift — KIT CARD V2 ferry (2026-11-26): the model, the default-kit rule, the store (§8.1-8.12 subset).

import XCTest
import CoreGraphics

final class KitCardV2Tests: XCTestCase {

    // §8.1 — a fresh line follows the default; its effective kit is GM @100.
    func testDefaultsFollowGM() {
        let line = EuclidLine(noteSel: .all)
        XCTAssertTrue(line.kitFollowsDefaultResolved)
        let eff = euclideousLaneEffectiveKit(line, defaultNotes: euclideousKitDefaultNotes, defaultVel: euclideousKitDefaultVel)
        XCTAssertEqual(eff.notes, euclideousKitDefaultNotes)
        XCTAssertEqual(eff.vel, euclideousKitDefaultVel)
    }

    // §1.3 resolver — a custom stored kit or a template id ⇒ NOT following.
    func testResolverNotFollowing() {
        var custom = EuclidLine(noteSel: .all); custom.kitNotes = [36, 36, 36, 36, 36, 36, 36, 36]
        XCTAssertFalse(custom.kitFollowsDefaultResolved)
        var tmpl = EuclidLine(noteSel: .all); tmpl.kitTemplate = "tr909"
        XCTAssertFalse(tmpl.kitFollowsDefaultResolved)
        var explicitTrue = custom; explicitTrue.kitFollowsDefault = true   // an explicit flag wins
        XCTAssertTrue(explicitTrue.kitFollowsDefaultResolved)
    }

    // §8.2/§8.3 — push a custom kit: the lane owns it (custom, not following), defaultKit updates, followers read it.
    func testPushCustomKit() {
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        var dn: [UInt8]? = nil, dv: [UInt8]? = nil, dc: Bool? = nil
        let nn: [UInt8] = [60, 61, 62, 63, 64, 65, 66, 67], nv: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80]
        euclideousPushCustomKit(lines: &lines, defaultNotes: &dn, defaultVel: &dv, defaultIsCustom: &dc, lane: 0, notes: nn, vel: nv)
        XCTAssertEqual(dn, nn); XCTAssertEqual(dv, nv); XCTAssertEqual(dc, true)
        XCTAssertFalse(lines[0].kitFollowsDefaultResolved); XCTAssertEqual(lines[0].kitTemplate, "custom"); XCTAssertEqual(lines[0].kitNotes, nn)
        for i in 1...3 {
            XCTAssertTrue(lines[i].kitFollowsDefaultResolved)
            let eff = euclideousLaneEffectiveKit(lines[i], defaultNotes: euclideousKitNotesClamped(dn), defaultVel: euclideousKitVelClamped(dv))
            XCTAssertEqual(eff.notes, nn); XCTAssertEqual(eff.vel, nv)
        }
    }

    // §8.4 — drag target: which rank cell the finger x is over (nil in a gap / outside).
    func testRankAtX() {
        let cells = (0..<8).map { CGRect(x: CGFloat($0) * 20, y: 0, width: 18, height: 40) }
        XCTAssertEqual(euclideousKitRankAtX(5, cells: cells), 0)
        XCTAssertEqual(euclideousKitRankAtX(45, cells: cells), 2)
        XCTAssertNil(euclideousKitRankAtX(19, cells: cells))   // the 2-pt gap
        XCTAssertNil(euclideousKitRankAtX(-5, cells: cells))
    }

    // §4.3 — name helpers: prefill lowest unused, uppercase/≤16/empty-fallback, clash → " 2".
    func testNameHelpers() {
        XCTAssertEqual(KitTemplateStore.prefillName([]), "KIT 1")
        XCTAssertEqual(KitTemplateStore.prefillName(["KIT 1", "KIT 3"]), "KIT 2")
        XCTAssertEqual(KitTemplateStore.uniqueName("my kit", fallback: "KIT 1", existing: []), "MY KIT")
        XCTAssertEqual(KitTemplateStore.uniqueName("", fallback: "KIT 2", existing: []), "KIT 2")
        XCTAssertEqual(KitTemplateStore.uniqueName("KIT 1", fallback: "KIT 2", existing: ["KIT 1"]), "KIT 1 2")
        XCTAssertEqual(KitTemplateStore.uniqueName("abcdefghijklmnopqrstu", fallback: "x", existing: []).count, 16)
    }

    // §8.10 — store round-trip in a temp dir (save → clash → rename → delete).
    func testStoreRoundTrip() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kctest-\(ProcessInfo.processInfo.globallyUniqueString)")
        KitTemplateStore.directoryOverride = tmp
        defer { KitTemplateStore.directoryOverride = nil; try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(KitTemplateStore.load().count, 0)
        let id = KitTemplateStore.save(name: "foo", notes: euclideousKitDefaultNotes, vel: euclideousKitDefaultVel)
        let kits = KitTemplateStore.load()
        XCTAssertEqual(kits.count, 1); XCTAssertEqual(kits[0].name, "FOO"); XCTAssertEqual(kits[0].notes, euclideousKitDefaultNotes)
        KitTemplateStore.save(name: "foo", notes: euclideousKitDefaultNotes, vel: euclideousKitDefaultVel)   // clash
        XCTAssertEqual(KitTemplateStore.load().map { $0.name }.sorted(), ["FOO", "FOO 2"])
        KitTemplateStore.rename(id: id, to: "bar")
        XCTAssertTrue(KitTemplateStore.load().contains { $0.id == id && $0.name == "BAR" })
        KitTemplateStore.delete(id: id)
        XCTAssertFalse(KitTemplateStore.load().contains { $0.id == id })
    }

    // §8.12 — normalise at load: a non-GM kit ⇒ not following + custom; a GM lane follows; idempotent.
    func testNormaliseAtLoad() {
        var s = PluginState.makeInit()
        var lanes = (0..<4).map { _ in EuclidLine(noteSel: .all) }   // all kitFollowsDefault nil, GM kits
        lanes[0].kitNotes = [36, 36, 36, 36, 36, 36, 36, 36]          // a custom kit, flag nil
        s.euclideousLines = lanes
        s.normalizeKitFollowsAtLoad()
        XCTAssertEqual(s.euclideousLines![0].kitFollowsDefault, false)
        XCTAssertEqual(s.euclideousLines![0].kitTemplate, "custom")
        XCTAssertEqual(s.euclideousLines![1].kitFollowsDefault, true)
        let before = s; s.normalizeKitFollowsAtLoad(); XCTAssertEqual(s, before, "idempotent")
    }
}
