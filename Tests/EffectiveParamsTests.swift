//  EffectiveParamsTests.swift
//  Re-homed (2026-08-05) as the MACRO MODULATION engine tests. The old A/B-morph interpolation these once covered
//  was removed; the file is now the natural home for the macro offset model (base ⊕ value×delta) per the map's
//  recommendation. M0 here = the STATE MODEL (persistence + snapshot plumbing); M1 adds the offset-math cases.

import XCTest

final class EffectiveParamsTests: XCTestCase {

    /// A minimal valid document (macro tests don't touch colours/scenes).
    private func doc() -> PluginState { PluginState(colours: [], scenes: [SceneState.empty()]) }

    // MARK: M0 — the macro state model

    /// A clean instrument (no macros persisted) resolves to 24 unset macros, correctly banked.
    func testMacrosResolveToTwentyFourUnsetByBank() {
        let doc = self.doc()
        XCTAssertNil(doc.macros)                                   // nothing persisted on a clean instrument
        let m = doc.macrosResolved
        XCTAssertEqual(m.count, 24)
        XCTAssertTrue(m.allSatisfy { $0.name.isEmpty && $0.value == 0 && !$0.fixed && $0.targets.isEmpty })
        XCTAssertEqual(PluginState.macroKind(0), .slider)
        XCTAssertEqual(PluginState.macroKind(7), .slider)
        XCTAssertEqual(PluginState.macroKind(8), .button)
        XCTAssertEqual(PluginState.macroKind(15), .button)
        XCTAssertEqual(PluginState.macroKind(16), .timeline)
        XCTAssertEqual(PluginState.macroKind(23), .timeline)
    }

    /// A short/partial macros array is padded (missing slots ⇒ unset) — forward/back compatible like the rack arrays.
    func testMacrosResolvedIsShortArraySafe() {
        var doc = self.doc()
        doc.macros = [Macro(name: "FILT", value: 0.5, fixed: true,
                            targets: [MacroTarget(col: 1, row: 2, slot: 0, param: "gate", delta: 0.3)])]
        let m = doc.macrosResolved
        XCTAssertEqual(m.count, 24)
        XCTAssertEqual(m[0].name, "FILT")
        XCTAssertEqual(m[0].value, 0.5)
        XCTAssertTrue(m[0].fixed)
        XCTAssertEqual(m[0].targets.first?.param, "gate")
        XCTAssertTrue(m[1].name.isEmpty)                            // the rest pad to unset
    }

    /// Macros survive a JSON round-trip, and an OLD doc (no `macros` key) decodes to nil (off) — additive-Optional.
    func testMacrosRoundTripAndOldDocDecodesNil() throws {
        var doc = self.doc()
        doc.macros = doc.macrosResolved
        doc.macros?[3] = Macro(name: "SWEEP", value: 0.8, fixed: false,
                               targets: [MacroTarget(col: 4, row: 5, slot: 1, param: "spread", delta: -0.4)])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.macros?.count, 24)
        XCTAssertEqual(back.macrosResolved[3].name, "SWEEP")
        XCTAssertEqual(back.macrosResolved[3].targets.first?.delta, -0.4)

        // An old document with no macros key: strip it, decode → nil, resolve → 24 unset.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "macros")
        let oldData = try JSONSerialization.data(withJSONObject: obj)
        let old = try JSONDecoder().decode(PluginState.self, from: oldData)
        XCTAssertNil(old.macros)
        XCTAssertEqual(old.macrosResolved.count, 24)
    }

    /// The builder mirrors the 24 macro values into the snapshot (clamped 0…1); a clean doc yields 24 zeros.
    func testBuilderMirrorsMacroValuesClamped() {
        var doc = self.doc()
        let clean = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(clean.macroValues.count, 24)
        XCTAssertTrue(clean.macroValues.allSatisfy { $0 == 0 })

        doc.macros = doc.macrosResolved
        doc.macros?[0].value = 0.75
        doc.macros?[1].value = 2.0                                 // out of range → clamps to 1
        doc.macros?[2].value = -1.0                                // → clamps to 0
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.macroValues[0], 0.75, accuracy: 1e-9)
        XCTAssertEqual(box.macroValues[1], 1.0, accuracy: 1e-9)
        XCTAssertEqual(box.macroValues[2], 0.0, accuracy: 1e-9)
    }
}
