//  MacroAuthoringTests.swift
//  Phase A of THE MACRO AUTHORING FLOW — the pure control-group registry + authoring logic
//  (sparse deltas · mover eligibility · the offset-preview morph). Spec: AcceptanceCriteria-macro-authoring.md.

import XCTest

final class MacroAuthoringTests: XCTestCase {

    private let params: [MacroControlParam] = [
        MacroControlParam(key: "gate", label: "GATE", kind: .continuous(lo: 0.05, hi: 1)),
        MacroControlParam(key: "bypass", label: "BYPASS", kind: .discrete),
        MacroControlParam(key: "spread", label: "SPREAD", kind: .continuous(lo: 0, hi: 1)),
    ]

    // §3 SPARSE DELTAS — only the params that actually diverge are stored (untouched carry nothing).
    func testSparseDeltaKeepsOnlyChanged() {
        let main = ["gate": 0.5, "bypass": 0.0, "spread": 0.3]
        let alt  = ["gate": 0.8, "bypass": 1.0, "spread": 0.3]      // gate +0.3, bypass flips, spread unchanged
        let d = macroSparseDelta(main: main, alt: alt, params: params)
        XCTAssertEqual(d["gate"]!, 0.3, accuracy: 1e-9)
        XCTAssertEqual(d["bypass"]!, 1.0)
        XCTAssertNil(d["spread"], "an untouched param carries nothing")
        XCTAssertEqual(d.count, 2)
    }

    func testSparseDeltaContinuousUsesEpsilonDiscreteExact() {
        let main = ["gate": 0.5, "bypass": 0.0]
        let alt  = ["gate": 0.5 + 1e-12, "bypass": 0.0]             // sub-epsilon continuous noise → ignored
        XCTAssertTrue(macroSparseDelta(main: main, alt: alt, params: params).isEmpty)
    }

    // §3 the offset PREVIEW — value 0 = MAIN, value 1 = ALT; continuous glides, discrete SNAPS past halfway.
    func testMacroApplyGlidesContinuousSnapsDiscrete() {
        let main = ["gate": 0.5, "bypass": 0.0]
        let delta = ["gate": 0.3, "bypass": 1.0]
        let at0 = macroApply(main: main, delta: delta, value: 0, params: params)
        XCTAssertEqual(at0["gate"]!, 0.5, accuracy: 1e-9); XCTAssertEqual(at0["bypass"]!, 0.0)   // home = MAIN
        let at1 = macroApply(main: main, delta: delta, value: 1, params: params)
        XCTAssertEqual(at1["gate"]!, 0.8, accuracy: 1e-9); XCTAssertEqual(at1["bypass"]!, 1.0)   // full = ALT
        let atHalf = macroApply(main: main, delta: delta, value: 0.5, params: params)
        XCTAssertEqual(atHalf["gate"]!, 0.65, accuracy: 1e-9, "continuous glides")
        XCTAssertEqual(atHalf["bypass"]!, 1.0, "discrete snaps to ALT at/after halfway")
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.4, params: params)["bypass"]!, 0.0, "…and stays MAIN before halfway")
    }

    func testMacroApplyClampsContinuousToRange() {
        let main = ["gate": 0.9]
        let out = macroApply(main: main, delta: ["gate": 0.5], value: 1, params: params)   // 0.9 + 0.5 = 1.4 → clamp 1
        XCTAssertEqual(out["gate"]!, 1.0, accuracy: 1e-9)
        let outVal = macroApply(main: main, delta: ["gate": 5], value: 3, params: params)   // value clamps to 1 too
        XCTAssertEqual(outVal["gate"]!, 1.0, accuracy: 1e-9)
    }

    // §5 mover eligibility — a delta touching any DISCRETE param is BUTTON-only.
    func testDeltaHasDiscrete() {
        XCTAssertFalse(macroDeltaHasDiscrete(["gate": 0.3], params: params), "continuous-only → slider-eligible")
        XCTAssertTrue(macroDeltaHasDiscrete(["gate": 0.3, "bypass": 1.0], params: params), "any discrete → buttons only")
    }

    // The processor descriptor — "all controls available to that processor" + the universal BYPASS; continuous
    // keys reuse MacroParam raws so their bindings fold through the existing engine.
    func testProcessorParamsCoverEveryTypeWithBypass() {
        for t in ProcessorType.allCases {
            let ps = macroParamsForProcessor(t)
            XCTAssertTrue(ps.contains { $0.key == "bypass" && $0.kind.isDiscrete }, "\(t) exposes a discrete BYPASS")
            XCTAssertFalse(ps.isEmpty)
        }
        XCTAssertEqual(macroParamsForProcessor(.chance).first { $0.key == "probability" }?.kind, .continuous(lo: 0, hi: 1))
        XCTAssertTrue(macroParamsForProcessor(.arp).contains { $0.key == "pattern" && $0.kind.isDiscrete })
        // continuous processor keys are a subset of the foldable MacroParam raws (binding compatibility)
        let foldable = Set(["gate", "ramp", "spread", "curve", "velTilt", "probability", "harmVelScale"])
        for t in ProcessorType.allCases {
            for p in macroParamsForProcessor(t) where !p.kind.isDiscrete {
                XCTAssertTrue(foldable.contains(p.key), "continuous \(p.key) must be a foldable MacroParam")
            }
        }
    }
}
