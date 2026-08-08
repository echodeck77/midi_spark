//  MacroAuthoringTests.swift
//  Phase A of THE MACRO AUTHORING FLOW — the pure control-group registry + authoring logic
//  (sparse deltas · mover eligibility · the offset-preview morph). Spec: AcceptanceCriteria-macro-authoring.md.

import XCTest

final class MacroAuthoringTests: XCTestCase {

    private let params: [MacroControlParam] = [
        MacroControlParam(key: "gate", label: "GATE", kind: .continuous(lo: 0.05, hi: 1)),
        MacroControlParam(key: "bypass", label: "BYPASS", kind: .toggle),
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
        let foldable = Set(MacroParam.allCases.map(\.rawValue))   // the descriptor's continuous keys must be foldable MacroParams
        for t in ProcessorType.allCases {
            for p in macroParamsForProcessor(t) where !p.kind.isDiscrete {
                XCTAssertTrue(foldable.contains(p.key), "continuous \(p.key) must be a foldable MacroParam")
            }
        }
    }

    // Value get/set — the descriptor's keys read a live slot's values and write them back, round-trip clean.
    func testProcessorValuesRoundTripPerType() {
        var slots: [ProcessorSlot] = []
        var arp = ProcessorSlot(type: .arp); arp.bypassed = true
        arp.params.pattern = .upDown; arp.params.rate = .r1_8; arp.params.octaves = 3; arp.params.phase = .legato; arp.params.gate = 0.42
        slots.append(arp)
        var rat = ProcessorSlot(type: .ratchet); rat.params.count = 6; rat.params.ramp = 0.7; rat.params.gate = 0.3; slots.append(rat)
        var str = ProcessorSlot(type: .strum); str.params.strumDir = .alternate; str.params.spread = 0.4; str.params.curve = -0.5; str.params.velTilt = 0.6; slots.append(str)
        var chn = ProcessorSlot(type: .chance); chn.params.probability = 0.33; slots.append(chn)
        var harm = ProcessorSlot(type: .harmonize); harm.params.harmIntervals = [3, 7, -12]; harm.params.harmVelScale = 0.5; slots.append(harm)
        var pass = ProcessorSlot(type: .passgate); pass.params.passes = [true, false, true, false]; slots.append(pass)
        for s in slots {
            let back = applyProcessorValues(processorValues(s), to: ProcessorSlot(type: s.type))
            XCTAssertEqual(back.bypassed, s.bypassed, "\(s.type) bypass round-trips")
            for p in macroParamsForProcessor(s.type) {
                XCTAssertEqual(processorValues(back)[p.key] ?? .nan, processorValues(s)[p.key] ?? .nan, accuracy: 1e-9, "\(s.type).\(p.key) round-trips")
            }
        }
    }

    // §7 the ALTERNATIVE set persists on the slot (additive Optional → old docs decode nil).
    func testProcessorAltPersistsAndOldDocDecodesNil() throws {
        var slot = ProcessorSlot(type: .arp)
        slot.paramsAlt = { var p = ColourParams(); p.gate = 0.9; p.pattern = .random; return p }()
        slot.bypassedAlt = true
        let rt = try JSONDecoder().decode(ProcessorSlot.self, from: JSONEncoder().encode(slot))
        XCTAssertEqual(rt.paramsAlt?.gate, 0.9); XCTAssertEqual(rt.paramsAlt?.pattern, .random); XCTAssertEqual(rt.bypassedAlt, true)
        // an "old" slot without the keys decodes nil
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProcessorSlot(type: .arp))) as! [String: Any]
        obj.removeValue(forKey: "paramsAlt"); obj.removeValue(forKey: "bypassedAlt")
        let old = try JSONDecoder().decode(ProcessorSlot.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.paramsAlt); XCTAssertNil(old.bypassedAlt)
    }

    // A processor ALT diverging on gate (continuous) + pattern (option) yields a delta that binds BUTTON-only.
    func testProcessorDeltaEligibility() {
        var main = ProcessorSlot(type: .arp); main.params.gate = 0.5; main.params.pattern = .up
        var alt = main; alt.params.gate = 0.8   // continuous only
        let ps = macroParamsForProcessor(.arp)
        let dCont = macroSparseDelta(main: processorValues(main), alt: processorValues(alt), params: ps)
        XCTAssertFalse(macroDeltaHasDiscrete(dCont, params: ps), "gate-only → slider-eligible")
        alt.params.pattern = .random   // now touches a discrete option too
        let dDisc = macroSparseDelta(main: processorValues(main), alt: processorValues(alt), params: ps)
        XCTAssertTrue(macroDeltaHasDiscrete(dDisc, params: ps), "a pattern flip → buttons only")
    }

    // macroApply SWEEPS multi-value kinds (option · stepper) through their intermediate values; mask stays binary.
    func testMacroApplySweepsOptionStepperSnapsMask() {
        let ps = [MacroControlParam(key: "opt", label: "", kind: .option(["A", "B", "C"])),
                  MacroControlParam(key: "step", label: "", kind: .stepper(lo: 0, hi: 8)),
                  MacroControlParam(key: "mask", label: "", kind: .mask(bits: 4))]
        let main = ["opt": 0.0, "step": 2.0, "mask": 0.0], delta = ["opt": 2.0, "step": 6.0, "mask": 5.0]
        // OPTION + STEPPER run through the options (user 2026-08-07: a multi-select isn't binary)
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.5, params: ps)["opt"], 1, "option sweeps to the middle option at half")
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.4, params: ps)["step"], 4, "stepper sweeps to an intermediate step")
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.6, params: ps)["step"], 6)
        // endpoints: MAIN at 0, ALT at 1
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0, params: ps)["opt"], 0)
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 1, params: ps)["opt"], 2)
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 1, params: ps)["step"], 8)
        // MASK stays binary — snap at half
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.4, params: ps)["mask"], 0)
        XCTAssertEqual(macroApply(main: main, delta: delta, value: 0.6, params: ps)["mask"], 5)
    }

    // macroSlotBindings reads the macros already bound to a slot (col,row,slot) → each one's param→delta map.
    func testMacroSlotBindingsReadsBackPerSlot() {
        var m0 = Macro(name: "M1"); m0.targets = [MacroTarget(col: 1, row: 2, slot: 0, param: "gate", delta: 0.3),
                                                  MacroTarget(col: 1, row: 2, slot: 0, param: "spread", delta: -0.2),
                                                  MacroTarget(col: 5, row: 5, slot: 0, param: "gate", delta: 0.1)]  // other slot — excluded
        var m3 = Macro(name: "M4"); m3.targets = [MacroTarget(col: 1, row: 2, slot: 0, param: "curve", delta: 0.5)]
        let m1 = Macro(name: "M2")                                                                                   // no targets — absent
        let b = macroSlotBindings([m0, m1, Macro(name: "x"), m3], col: 1, row: 2, slot: 0)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.first { $0.macro == 0 }?.deltas, ["gate": 0.3, "spread": -0.2])
        XCTAssertEqual(b.first { $0.macro == 3 }?.deltas, ["curve": 0.5])
    }

    // Two targets on the SAME (slot,param) SUM (macroSlotBindings:100 uses `+=`) — not overwrite. The read-back must
    // report the combined offset so the dropdown reflects the true authored delta.
    func testMacroSlotBindingsSumsRepeatedParamTargets() {
        var m = Macro(name: "M1")
        m.targets = [MacroTarget(col: 1, row: 2, slot: 0, param: "gate", delta: 0.3),
                     MacroTarget(col: 1, row: 2, slot: 0, param: "gate", delta: 0.2)]
        let b = macroSlotBindings([m], col: 1, row: 2, slot: 0)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.deltas.count, 1, "one param, summed — not two entries")
        XCTAssertEqual(b.first?.deltas["gate"] ?? 0, 0.5, accuracy: 1e-9, "0.3 + 0.2 summed, not overwritten to 0.2")
    }

    // The processor group descriptor: a stable id (col,row,slot) · the processor domain · the type's param list.
    func testMacroGroupForProcessor() {
        let g = macroGroupForProcessor(col: 3, row: 5, slot: 1, type: .arp)
        XCTAssertEqual(g.id, "proc:3,5,1")
        XCTAssertEqual(g.domain, .processor)
        XCTAssertEqual(g.title, ProcessorType.arp.rawValue.uppercased())
        XCTAssertEqual(g.params, macroParamsForProcessor(.arp))
    }

    // Each processor type exposes its own kinds (mask · steppers) so the generic renderer picks the right widget.
    func testProcessorParamKindsPerType() {
        XCTAssertTrue(macroParamsForProcessor(.passgate).contains { $0.key == "passMask" && $0.kind == .mask(bits: 4) })
        XCTAssertTrue(macroParamsForProcessor(.ratchet).contains { $0.key == "count" && $0.kind == .stepper(lo: 2, hi: 8) })
        XCTAssertTrue(macroParamsForProcessor(.harmonize).contains { $0.key == "harm0" && $0.kind == .stepper(lo: -24, hi: 24) })
        XCTAssertTrue(macroParamsForProcessor(.arp).contains { $0.key == "octaves" && $0.kind == .stepper(lo: 1, hi: 4) })
    }

    // Write-back clamps discretes into their legal domain — a stale/out-of-range value never traps.
    func testApplyProcessorValuesClampsDiscretes() {
        var v = processorValues(ProcessorSlot(type: .arp)); v["octaves"] = 99; v["pattern"] = 99   // out of range
        let arp = applyProcessorValues(v, to: ProcessorSlot(type: .arp))
        XCTAssertEqual(arp.params.octaves, 4, "octaves clamp 1…4")
        XCTAssertEqual(arp.params.pattern, ArpPattern.allCases.last, "an out-of-range option index clamps to the last case")
        var pv = processorValues(ProcessorSlot(type: .passgate)); pv["passMask"] = 5               // 0b0101
        XCTAssertEqual(applyProcessorValues(pv, to: ProcessorSlot(type: .passgate)).params.passes, [true, false, true, false])
    }
}
