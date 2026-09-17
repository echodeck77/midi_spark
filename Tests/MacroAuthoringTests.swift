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

    // Every param a processor ADVERTISES (macroParamsForProcessor) must be READABLE by processorValues AND WRITABLE by
    // applyProcessorValues — a changed value must survive the round-trip. The euclid MUTATE bug (Paul 2026-08-16) was
    // exactly this: euclidPulses/Steps/Rot were advertised but fell through to `default: break`, so a tweak did nothing
    // and MUTATE could only ever toggle bypass (one variant, then dead). This guards EVERY type against that class.
    func testEveryAdvertisedParamIsGettableAndSettable() {
        for type in ProcessorType.allCases {
            let slot = ProcessorSlot(type: type)
            let vals = processorValues(slot)
            for p in macroParamsForProcessor(type) {
                guard let cur = vals[p.key] else {
                    XCTFail("\(type).\(p.key) is advertised but NOT readable by processorValues"); continue
                }
                let alt: Double                                   // a DIFFERENT legal value
                switch p.kind {
                case .continuous(let lo, let hi): alt = (cur - lo) > (hi - cur) ? lo : hi   // the far end
                case .toggle:                     alt = cur >= 0.5 ? 0 : 1
                case .option(let labels):         alt = Double((Int(cur.rounded()) + 1) % max(1, labels.count))
                case .stepper(_, let hi):         alt = cur < Double(hi) ? cur + 1 : cur - 1
                case .mask:                       alt = Double(Int(cur.rounded()) ^ 1)
                }
                if alt == cur { continue }                        // only one legal value → nothing to prove
                var changed = vals; changed[p.key] = alt
                let back = processorValues(applyProcessorValues(changed, to: slot))
                XCTAssertEqual(back[p.key] ?? .nan, alt, accuracy: 1e-6, "\(type).\(p.key): a CHANGE must survive applyProcessorValues (it's advertised but unwired)")
            }
        }
    }

    // §7 the ALTERNATIVE set persists on the slot (additive Optional → old docs decode nil).
    func testProcessorAltPersistsAndOldDocDecodesNil() throws {
        var slot = ProcessorSlot(type: .arp)
        slot.paramsAlt = { var p = MachineParams(); p.gate = 0.9; p.pattern = .random; return p }()
        slot.bypassedAlt = true
        let rt = try JSONDecoder().decode(ProcessorSlot.self, from: JSONEncoder().encode(slot))
        XCTAssertEqual(rt.paramsAlt?.gate, 0.9); XCTAssertEqual(rt.paramsAlt?.pattern, .random); XCTAssertEqual(rt.bypassedAlt, true)
        // an "old" slot without the keys decodes nil
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProcessorSlot(type: .arp))) as! [String: Any]
        obj.removeValue(forKey: "paramsAlt"); obj.removeValue(forKey: "bypassedAlt")
        let old = try JSONDecoder().decode(ProcessorSlot.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.paramsAlt); XCTAssertNil(old.bypassedAlt)
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
