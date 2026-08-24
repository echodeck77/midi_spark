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

    // MARK: M1 — the offset math (applyMacros)

    /// effective = base + value × delta, and the base bag is returned UNMUTATED (a copy) — identity stays put.
    func testApplyMacrosOffsetsAndLeavesBaseUntouched() {
        var base = SnapParams(); base.gate = 0.5
        let mods = [MacroMod(macro: 0, param: .gate, delta: 0.4)]
        let out = applyMacros(base, mods: mods, values: [0.5])
        XCTAssertEqual(out.gate, 0.7, accuracy: 1e-9)          // 0.5 + 0.5×0.4
        XCTAssertEqual(base.gate, 0.5, accuracy: 1e-9)         // the base is never rewritten
    }

    /// A macro at 0 is HOME — no offset, byte-for-byte the base (nothing to revert).
    func testMacroAtZeroIsHome() {
        var base = SnapParams(); base.gate = 0.5; base.spread = 0.3
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .gate, delta: 0.4),
                                           MacroMod(macro: 0, param: .spread, delta: -0.2)], values: [0.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.spread, 0.3, accuracy: 1e-9)
    }

    /// Two macros on the SAME param SUM, then clamp ONCE (the offset law) — not sequential per-macro clamping.
    func testOverlappingOffsetsSumThenClamp() {
        var base = SnapParams(); base.probability = 0.6
        // 0.6 + 1.0×0.5 + 1.0×0.5 = 1.6 → clamps to 1 (sum first). Sequential clamping would also hit 1 here,
        // so use a case where order matters: +0.6 then −0.5 = net +0.1 → 0.7 (sequential-with-clamp: 0.6+0.6=1.2→1, then 1−0.5=0.5 ≠ 0.7).
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .probability, delta: 0.6),
                                           MacroMod(macro: 1, param: .probability, delta: -0.5)], values: [1.0, 1.0])
        XCTAssertEqual(out.probability, 0.7, accuracy: 1e-9)   // sum (+0.1) then clamp — proves it's not clamped per-mod
    }

    /// Each param clamps to its resolve() range: probability/ramp/spread → [0,1]; curve/velTilt → [−1,1];
    /// gate → [0.05,1]; harmVelScale → [0.1,1].
    func testOffsetsClampToLegalRanges() {
        var base = SnapParams(); base.curve = 0.8; base.gate = 0.9; base.harmVelScale = 0.9
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .curve, delta: 0.9),        // 0.8+0.9=1.7 → 1
                                           MacroMod(macro: 0, param: .gate, delta: 0.5),          // 0.9+0.5=1.4 → 1
                                           MacroMod(macro: 0, param: .harmVelScale, delta: -2)],  // 0.9−2=−1.1 → 0.1
                              values: [1.0])
        XCTAssertEqual(out.curve, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.gate, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.harmVelScale, 0.1, accuracy: 1e-9)
    }

    // MARK: M1 — end to end through the builder

    /// A macro bound to a cell's chain-slot param shifts the RESOLVED param, while the document cell (and its seal)
    /// are untouched — the whole point of the offset model (performance, not identity).
    func testBuilderFoldsMacroOffsetIntoResolvedChainButNotTheDocument() {
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(name: "GATE", value: 0.5, fixed: false,
                               targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4)])

        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0].procs[0].gate, 0.7, accuracy: 1e-9)   // 0.5 + 0.5×0.4, folded at build

        // The base is untouched: the DOCUMENT slot param is still 0.5, and the seal (document-derived) is stable.
        XCTAssertEqual(doc.scenes[0].cells[0][0]?.processors?[0].params.gate, 0.5)
        let sealWith = sealHash(cell, colours: doc.colours)
        var docNoMacro = doc; docNoMacro.macros = nil
        XCTAssertEqual(sealHash(cell, colours: docNoMacro.colours), sealWith)   // macro presence never moves the seal
    }

    /// Macro at 0 through the builder is home — the resolved chain equals the un-macro'd build.
    func testBuilderMacroAtZeroMatchesNoMacro() {
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [s])
        let plain = SnapshotBuilder.build(from: doc).cells[0].procs[0].gate

        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 0.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, plain, accuracy: 1e-9)
    }

    /// M4 A/B semantic: a binding stores delta = B − A; the macro at 1 reconstructs B, at 0 returns to A. The base
    /// (A) is what the document holds — authoring never rewrites it (this is the offset model's contract end-to-end).
    func testABBindingReconstructsBAtOneAndAAtZero() {
        let A = 0.3, B = 0.9
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = A     // the A state lives in the document
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0].targets = [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: B - A)]   // the authored delta

        doc.macros?[0].value = 1.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, B, accuracy: 1e-9)     // full = B
        doc.macros?[0].value = 0.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, A, accuracy: 1e-9)     // home = A
        doc.macros?[0].value = 0.5
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.6, accuracy: 1e-9)   // halfway
    }

    // MARK: M1 — builder fold edge cases (guards + summing + multi-cell)

    /// A gold ARP chain cell at (col,row) with the given head gate, ready for macro targeting.
    private func chainCellDoc(gate: Double, at pos: (Int, Int) = (0, 0)) -> PluginState {
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = gate
        cell.processors = [slot]
        s.cells[pos.0][pos.1] = cell
        var doc = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        return doc
    }

    /// An out-of-range macro index in the values array contributes no offset (no crash, treated as 0).
    func testApplyMacrosIgnoresOutOfRangeMacroIndex() {
        var base = SnapParams(); base.gate = 0.5
        let out = applyMacros(base, mods: [MacroMod(macro: 99, param: .gate, delta: 0.4),
                                           MacroMod(macro: -1, param: .gate, delta: 0.4)], values: [1.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
    }

    /// The builder SKIPS a target with an unknown param string (forward-compat) — no crash, no change.
    func testBuilderSkipsUnknownParamString() {
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[0] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "bogus", delta: 0.4)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.5, accuracy: 1e-9)
    }

    /// The builder SKIPS out-of-bounds cell/slot targets (a stale binding after a resize) — no crash, no change.
    func testBuilderSkipsOutOfBoundsTarget() {
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[0] = Macro(value: 1.0, targets: [
            MacroTarget(col: 99, row: 0, slot: 0, param: "gate", delta: 0.4),   // col out of range
            MacroTarget(col: 0, row: 0, slot: 7, param: "gate", delta: 0.4),    // slot past the 1-slot chain
        ])
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0].procs[0].gate, 0.5, accuracy: 1e-9)          // unchanged; no trap
    }

    /// Two macros bound to the SAME (cell,slot,param) SUM through the full build, then clamp once.
    func testBuilderTwoMacrosOnSameParamSumEndToEnd() {
        var doc = chainCellDoc(gate: 0.4)
        doc.macros?[0] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.2)])
        doc.macros?[1] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.9, accuracy: 1e-9)   // 0.4+0.2+0.3
    }

    /// One macro bound to TWO cells (a twin set) modulates BOTH — the multi-cell write law.
    func testBuilderMacroModulatesEveryTargetedCell() {
        var s = SceneState.empty()
        for pos in [(0, 0), (3, 5)] {
            var cell = Cell(colourID: "gold"); var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
            cell.processors = [slot]; s.cells[pos.0][pos.1] = cell
        }
        var doc = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, targets: [
            MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3),
            MacroTarget(col: 3, row: 5, slot: 0, param: "gate", delta: 0.3),
        ])
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0 * 8 + 0].procs[0].gate, 0.8, accuracy: 1e-9)
        XCTAssertEqual(box.cells[3 * 8 + 5].procs[0].gate, 0.8, accuracy: 1e-9)
    }

    /// A BUTTON-bank macro (index ≥ 8) folds identically to a slider — the builder iterates all 24 banks, so a
    /// button snapped to B (value 1) reconstructs B just like M1. Locks that non-slider banks aren't excluded.
    func testButtonBankMacroModulatesLikeSlider() {
        XCTAssertEqual(PluginState.macroKind(8), .button)
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[8] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.8, accuracy: 1e-9)   // 0.5 + 1×0.3
    }

    // MARK: OUTPUT — macros modulate the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET)

    /// A macro bound to an emitter's DUCK amount shifts the RESOLVED amount; the document base is untouched, and a
    /// macro at 0 is home. The amount lives per-emitter (folded in the builder, not through applyMacros).
    func testOutputMacroModulatesEmitterAmountAndLeavesBaseUntouched() {
        var doc = self.doc()
        doc.flattenAmount = [40, 0, 0, 0]                    // base DUCK 40% on emitter A
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, emitterTargets: [MacroEmitterTarget(emitter: 0, param: "duck", delta: 50)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).flattenAmount[0], 90)   // 40 + 1×50
        XCTAssertEqual(doc.flattenAmountResolved[0], 40)                        // document base untouched
        doc.macros?[0].value = 0.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).flattenAmount[0], 40)   // home = base
    }

    // MARK: TIMELINE — the pure lane evaluator (value = f(column))

    private func flat(_ v: Int) -> [Int] { Array(repeating: v, count: 8) }

    func testLaneStepHoldsValueAcrossColumn() {
        let lane = [0.2, 0.8] + Array(repeating: 0.0, count: 6)
        let modes = flat(0)                                        // all STEP
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.0, stepBeats: 1, manual: 0.5), 0.2, accuracy: 1e-9)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.5, stepBeats: 1, manual: 0.5), 0.2, accuracy: 1e-9)  // holds mid-column
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 1.0, stepBeats: 1, manual: 0.5), 0.8, accuracy: 1e-9)  // next step
    }

    func testLaneSmoothGlidesTowardNextValue() {
        var modes = flat(0); modes[0] = 1                          // step 0 SMOOTH
        let lane = [0.0, 1.0] + Array(repeating: 0.0, count: 6)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.0, stepBeats: 1, manual: 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.5, stepBeats: 1, manual: 0.5), 0.5, accuracy: 1e-9)  // halfway glide
    }

    func testLaneBypassReturnsManual() {
        var modes = flat(0); modes[0] = 2                          // step 0 BYPASS → the fader value governs
        let lane = [0.9] + Array(repeating: 0.0, count: 7)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.3, stepBeats: 1, manual: 0.42), 0.42, accuracy: 1e-9)
    }

    func testLaneSmoothSkipsBypassedColumnsForTarget() {
        var modes = flat(0); modes[0] = 1; modes[1] = 2            // 0 SMOOTH · 1 BYPASS · 2 STEP
        let lane = [0.0, 0.3, 1.0] + Array(repeating: 0.0, count: 5)
        // from step 0 the next non-bypassed target is step 2 (1.0), NOT the bypassed step 1 (0.3) → glide 0→1.
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.5, stepBeats: 1, manual: 0.5), 0.5, accuracy: 1e-9)
    }

    func testLaneRateScalesAndWraps() {
        let lane = (0..<8).map { Double($0) / 10.0 }               // 0.0, 0.1, … 0.7
        let modes = flat(0)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 2, absoluteBeat: 0.5, stepBeats: 1, manual: 0), 0.1, accuracy: 1e-9)  // ×2 → step 1 by half a column
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 8.0, stepBeats: 1, manual: 0), 0.0, accuracy: 1e-9)  // wraps to step 0
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 9.0, stepBeats: 1, manual: 0), 0.1, accuracy: 1e-9)  // step 9 → 1
    }

    func testMacroLaneResolversAreShortArraySafe() {
        var m = Macro(); m.lane = [0.5]; m.laneModes = [2]
        XCTAssertEqual(m.laneResolved.count, 8)
        XCTAssertEqual(m.laneResolved[0], 0.5); XCTAssertEqual(m.laneResolved[1], 0.0)
        XCTAssertEqual(m.laneModesResolved[0], 2); XCTAssertEqual(m.laneModesResolved[1], 0)
        XCTAssertEqual(m.laneRateMulResolved, 1.0)                 // default index 3 = ×1
        m.laneRate = 0; XCTAssertEqual(m.laneRateMulResolved, 8.0) // ×8
    }

    /// Each OUTPUT amount clamps to its native range (LEAK/DUCK 0…100 · CURVE −100…100 · POCKET −50…50), summing
    /// overlaps ONCE. A half-value macro scales the delta.
    func testOutputAmountsSumThenClampToRanges() {
        var doc = self.doc()
        doc.flattenAmount = [40, 0, 0, 0]; doc.curveAmount = [0, 0, 0, 0]; doc.pocketMs = [0, 0, 0, 0]
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, emitterTargets: [
            MacroEmitterTarget(emitter: 0, param: "duck", delta: 80),     // 40 + 80 = 120 (before the 2nd) …
            MacroEmitterTarget(emitter: 0, param: "duck", delta: -30),    // … + −30 = 90 (sum first, not clamp-per-mod)
            MacroEmitterTarget(emitter: 1, param: "curve", delta: 200),   // 0 + 200 → clamp 100
            MacroEmitterTarget(emitter: 2, param: "pocket", delta: -80),  // 0 − 80 → clamp −50
        ])
        doc.macros?[1] = Macro(value: 0.5, emitterTargets: [MacroEmitterTarget(emitter: 3, param: "leak", delta: 40)])  // 0.5×40 = 20
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.flattenAmount[0], 90)      // sum then clamp (proves not clamped per-mod)
        XCTAssertEqual(box.curveAmount[1], 100)       // clamped to +100
        XCTAssertEqual(box.pocketMs[2], -50)          // clamped to −50
        XCTAssertEqual(box.claimLeak[3], 20)          // half-value scales the delta
    }

    // MARK: applyMacros — guard edges (negative index · zero-offset short-circuit)

    /// A NEGATIVE macro index contributes nothing (the guard's lower half) and a zero-value/zero-delta mod leaves
    /// the base bit-identical (the `off == 0` short-circuit — never a needless re-clamp).
    func testApplyMacrosNegativeIndexAndZeroOffsetLeaveBaseUntouched() {
        var base = SnapParams(); base.gate = 0.5; base.spread = 0.3
        let out = applyMacros(base, mods: [
            MacroMod(macro: -1, param: .gate, delta: 0.5),     // negative index → skipped
            MacroMod(macro: 0, param: .spread, delta: 0.0),    // zero delta → off == 0 → skipped
        ], values: [1.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.spread, 0.3, accuracy: 1e-9)
    }

    // MARK: Snapshot effective* — the quantize/clamp helpers (render-side, §3.2)

    private func snapColour(_ mutate: (inout SnapParams) -> Void) -> SnapColour {
        var sc = SnapColour(); mutate(&sc.a); return sc
    }

    /// RATCHET repeats quantize to the nearest LEGAL count in [2,3,4,6,8], first-wins on a tie.
    func testEffectiveRepeatsQuantizesToLegalCount() {
        XCTAssertEqual(effectiveRepeats(snapColour { $0.count = 2 }), 2)
        XCTAssertEqual(effectiveRepeats(snapColour { $0.count = 5 }), 4, "5 is equidistant 4/6 → first (4) wins")
        XCTAssertEqual(effectiveRepeats(snapColour { $0.count = 7 }), 6, "7 is equidistant 6/8 → first (6) wins")
        XCTAssertEqual(effectiveRepeats(snapColour { $0.count = 8 }), 8)
    }

    /// The scalar effective* helpers saturate at their native bounds — no trap, no off-by-one in the voice switch.
    func testEffectiveScalarClamps() {
        XCTAssertEqual(effectiveOctaves(snapColour { $0.octaves = 9 }), 4, "octaves clamp 1…4")
        XCTAssertEqual(effectiveOctaves(snapColour { $0.octaves = 0 }), 1)
        // harmIntervals voice select: 0/1 pick .0/.1, any other index picks .2; each clamps ±24.
        let c = snapColour { $0.harmIntervals = (100, -100, 7) }
        XCTAssertEqual(effectiveHarmInterval(c, voice: 0), 24)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 1), -24)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 2), 7)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 99), 7, "an out-of-range voice falls to the 3rd interval")
        // rateIndex saturates into the arpRateBeats ladder rather than trapping.
        XCTAssertEqual(effectiveRateBeats(snapColour { $0.rateIndex = 127 }), Snap.arpRateBeats.last!)
        XCTAssertEqual(effectiveRateBeats(snapColour { $0.rateIndex = -5 }), Snap.arpRateBeats.first!)
    }

    /// The unit-range render-side reads saturate at their floors/ceilings (the render thread's last line of defence
    /// even though `resolve` already clamps on ingest): ramp/spread/probability ∈ [0,1], harmVelScale ∈ [0.1,1].
    func testEffectiveUnitRangeScalarsClamp() {
        XCTAssertEqual(effectiveRamp(snapColour { $0.ramp = 2 }), 1)
        XCTAssertEqual(effectiveRamp(snapColour { $0.ramp = -1 }), 0)
        XCTAssertEqual(effectiveSpread(snapColour { $0.spread = 5 }), 1)
        XCTAssertEqual(effectiveSpread(snapColour { $0.spread = -0.5 }), 0)
        XCTAssertEqual(effectiveProbability(snapColour { $0.probability = 3 }.a), 1)
        XCTAssertEqual(effectiveProbability(snapColour { $0.probability = -2 }.a), 0)
        XCTAssertEqual(effectiveHarmVelScale(snapColour { $0.harmVelScale = 5 }), 1)
        XCTAssertEqual(effectiveHarmVelScale(snapColour { $0.harmVelScale = -1 }), 0.1, "the floor is 0.1, not 0")
    }

    // MARK: laneValue — guard + wrap + all-bypass-smooth edges

    /// The guard returns the manual value for a degenerate lane (empty, zero step, zero rate) — no divide-by-zero.
    func testLaneValueGuardReturnsManual() {
        XCTAssertEqual(laneValue(lane: [], modes: [], rateMul: 1, absoluteBeat: 2, stepBeats: 1, manual: 0.7), 0.7)
        let lane = [0.2] + Array(repeating: 0.0, count: 7), modes = Array(repeating: 0, count: 8)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 2, stepBeats: 0, manual: 0.7), 0.7)   // stepBeats 0
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 0, absoluteBeat: 2, stepBeats: 1, manual: 0.7), 0.7)   // rateMul 0
    }

    /// A NEGATIVE absoluteBeat wraps into a valid step (the ((idx%n)+n)%n fold) — no negative index trap.
    func testLaneValueNegativeBeatWraps() {
        let lane = (0..<8).map { Double($0) / 10.0 }               // 0.0 … 0.7
        let modes = Array(repeating: 0, count: 8)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: -1.0, stepBeats: 1, manual: 0), 0.7, accuracy: 1e-9)  // step -1 → 7
    }

    /// SMOOTH when EVERY other step is BYPASS: the target search wraps back to `s`, so it holds `lane[s]` — no glide
    /// to a stale index.
    func testLaneValueSmoothWithAllOthersBypassedHolds() {
        var modes = Array(repeating: 2, count: 8); modes[0] = 1     // only step 0 is SMOOTH; the rest BYPASS
        let lane = [0.3] + Array(repeating: 0.0, count: 7)
        XCTAssertEqual(laneValue(lane: lane, modes: modes, rateMul: 1, absoluteBeat: 0.5, stepBeats: 1, manual: 0.9), 0.3, accuracy: 1e-9)
    }
}
