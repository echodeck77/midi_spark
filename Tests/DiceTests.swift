import XCTest

// THE DICE — the offline evaluator + generation guarantees (user 2026-08-10).
final class DiceTests: XCTestCase {

    // A rolled chain is LONGER than 3 and EVERY slot contributes (bypassing it changes the output).
    func testRollChainIsLongAndEverySlotContributes() {
        for seed: UInt64 in [0xD1CE, 0x5A3F, 7, 99, 0xBEEF] {
            var rng = DiceRNG(seed: seed)
            let chain = Dice.rollChain(target: 5, using: &rng)
            XCTAssertGreaterThan(chain.count, 3, "seed \(seed): the chain is longer than 3 (got \(chain.count))")
            let full = Dice.signature(chain)
            for k in 0..<chain.count {
                XCTAssertTrue(Dice.contributes(chain, slot: k, sigFull: full),
                              "seed \(seed): slot \(k) (\(chain[k].type)) must contribute — bypassing it changes nothing")
            }
        }
    }

    // Every generated SLIDER and BUTTON macro has a tangible effect (the output differs from the base).
    func testRolledMacrosEachChangeTheOutput() {
        var rng = DiceRNG(seed: 0x5A3F)
        let r = Dice.roll(target: 5, using: &rng)
        let sigBase = Dice.signature(r.base)
        XCTAssertFalse(r.sliders.isEmpty || r.buttons.isEmpty, "a roll yields slider + button macros")
        for m in r.sliders {
            var alt = r.base; Dice.setD(&alt[m.slot], m.param, m.alt)
            XCTAssertNotEqual(Dice.signature(alt), sigBase, "slider on slot \(m.slot)/\(m.param) must change the output")
        }
        for b in r.buttons {
            var alt = r.base
            switch b.op {
            case .bypass(let k):           alt[k].bypassed.toggle()
            case .switchType(let k, let t): alt[k].type = t
            }
            XCTAssertNotEqual(Dice.signature(alt), sigBase, "button \(b.label) must change the output")
        }
    }

    // Rolls are DENSITY-CAPPED (user 2026-08-10: "70 voices from two rows") — the chain, and each slider at full,
    // never exceed the peak-concurrency cap.
    func testRollsAreDensityCapped() {
        for seed: UInt64 in [0xD1CE, 0x5A3F, 7, 99, 0xBEEF] {
            var rng = DiceRNG(seed: seed)
            let r = Dice.roll(target: 5, using: &rng)
            XCTAssertLessThanOrEqual(Dice.evalRun(r.base).peak, Dice.maxConcurrency, "seed \(seed): the rolled chain isn't a flood")
            for m in r.sliders {
                var alt = r.base; Dice.setD(&alt[m.slot], m.param, m.alt)
                XCTAssertLessThanOrEqual(Dice.evalRun(alt).peak, Dice.maxConcurrency, "seed \(seed): slider at full stays capped")
            }
        }
    }

    // A seed reproduces the same roll (deterministic — no Date/Math.random on the path).
    func testRollIsDeterministicForASeed() {
        var a = DiceRNG(seed: 42), b = DiceRNG(seed: 42)
        XCTAssertEqual(Dice.roll(target: 5, using: &a), Dice.roll(target: 5, using: &b))
    }

    // The effective-chain composition: sliders at 0 + buttons off == the base; a slider at 1 reaches its alt.
    func testEffectiveChainComposition() {
        var rng = DiceRNG(seed: 123)
        let r = Dice.roll(target: 5, using: &rng)
        XCTAssertEqual(r.chain(sliderVals: [0, 0, 0, 0], buttonOn: [false, false, false, false]), r.base,
                       "all sliders 0 + buttons off ⇒ the base chain")
        if let m = r.sliders.first {
            let full = r.chain(sliderVals: [1, 0, 0, 0], buttonOn: [false, false, false, false])
            XCTAssertEqual(Dice.getD(full[m.slot], m.param), m.alt, accuracy: 1e-9, "slider 0 at 1.0 reaches its alt value")
        }
    }

    // rollSimple (BUILD): 1–3 slots, never empty, every slot contributes (audible + bypass-affecting), density-capped.
    func testRollSimpleIsShortAllContributingAndAudible() {
        for seed: UInt64 in [1, 7, 42, 0xD1CE, 0x5A3F, 99, 0xBEEF, 3] {
            var rng = DiceRNG(seed: seed)
            let chain = Dice.rollSimple(using: &rng)
            XCTAssertFalse(chain.isEmpty, "seed \(seed): never empty")
            XCTAssertLessThanOrEqual(chain.count, 3, "seed \(seed): ≤ 3 slots")
            XCTAssertGreaterThanOrEqual(chain.count, 1, "seed \(seed): ≥ 1 slot")
            XCTAssertFalse(Dice.signature(chain).isEmpty, "seed \(seed): audible (non-empty output)")
            XCTAssertTrue(Dice.allContribute(chain), "seed \(seed): every slot changes the output when bypassed")
            XCTAssertLessThanOrEqual(Dice.evalRun(chain).peak, Dice.maxConcurrency, "seed \(seed): not a flood")
        }
    }

    // The BUTTON branch of chain(buttonOn:) — the path the live engine actually calls for a toggle (the existing tests
    // only drive sliders through chain(), or apply buttons MANUALLY). Composing all buttons ON must equal applying each
    // op to the base, and a switchType button must set its slot's type.
    func testEffectiveChainAppliesButtons() {
        var rng = DiceRNG(seed: 0x0B77)
        let r = Dice.roll(target: 5, using: &rng)
        guard !r.buttons.isEmpty else { return XCTFail("a roll yields button macros") }
        let composed = r.chain(sliderVals: [0, 0, 0, 0], buttonOn: Array(repeating: true, count: r.buttons.count))
        var expected = r.base
        for b in r.buttons {
            switch b.op {
            case .bypass(let k):            if k < expected.count { expected[k].bypassed.toggle() }
            case .switchType(let k, let t): if k < expected.count { expected[k].type = t }
            }
        }
        XCTAssertEqual(composed, expected, "chain(buttonOn:) applies each button's op through the composition path")
        for b in r.buttons { if case .switchType(let k, let t) = b.op, k < composed.count {
            XCTAssertEqual(composed[k].type, t, "switchType button sets slot \(k)'s type")
        } }
    }

    // getD/setD are two independent switches; a SYMMETRIC mis-mapping (both swap spread↔curve) round-trips and would
    // pass testEffectiveChainComposition. Lock each DParam to its OWN field in both directions + the nil-defaults that
    // seed rollSliders' base. (coverage 2026-08-15)
    func testDiceGetSetMapEachParamToItsOwnField() {
        var s = ProcessorSlot(type: .arp)
        Dice.setD(&s, .spread, 0.42)
        XCTAssertEqual(s.params.spread, 0.42, "setD(.spread) writes spread")
        XCTAssertEqual(s.params.curve, 0, "…not curve (its default is untouched)")
        XCTAssertEqual(s.params.gate, 0.6, "…not gate")
        Dice.setD(&s, .ramp, 0.7); XCTAssertEqual(s.params.ramp, 0.7); XCTAssertEqual(s.params.probability, 1, "ramp ≠ probability")
        // getD reads each field; a fresh slot's populated defaults
        let fresh = ProcessorSlot(type: .arp)
        XCTAssertEqual(Dice.getD(fresh, .gate), 0.6); XCTAssertEqual(Dice.getD(fresh, .probability), 1)
        XCTAssertEqual(Dice.getD(fresh, .spread), 0.1); XCTAssertEqual(Dice.getD(fresh, .curve), 0); XCTAssertEqual(Dice.getD(fresh, .ramp), 0.5)
        // the nil-fallback branch (a param cleared to nil → the documented default)
        var cleared = ProcessorSlot(type: .arp)
        cleared.params.gate = nil; cleared.params.spread = nil; cleared.params.ramp = nil
        XCTAssertEqual(Dice.getD(cleared, .gate), 0.6, "nil → default"); XCTAssertEqual(Dice.getD(cleared, .spread), 0.1); XCTAssertEqual(Dice.getD(cleared, .ramp), 0.5)
    }

    // DiceRecorder.peakConcurrency (the density/flood cap's measurement): OFFs must sort before ONs at a coincident
    // sample so a restrike doesn't spike the peak. Without the tie-break this reads 4, not 2. (coverage 2026-08-15)
    func testPeakConcurrencyOrdersOffBeforeOnAtATie() {
        let r = DiceRecorder()
        r.emit(sampleTime: 0, cable: 1, 0x90, 60, 100)     // two voices sounding
        r.emit(sampleTime: 0, cable: 1, 0x90, 64, 100)
        r.emit(sampleTime: 480, cable: 1, 0x80, 60, 0)      // restrike both at the SAME sample (off, on, off, on)
        r.emit(sampleTime: 480, cable: 1, 0x90, 60, 100)
        r.emit(sampleTime: 480, cable: 1, 0x80, 64, 0)
        r.emit(sampleTime: 480, cable: 1, 0x90, 64, 100)
        XCTAssertEqual(r.peakConcurrency, 2, "off-before-on tie-break keeps the peak at 2 (not 4)")
    }

    // Result.chain guards: fewer live values than macros ⇒ home/off (== base); oversized inputs / out-of-range slots
    // must not trap or grow the chain. (coverage 2026-08-15)
    func testChainDefaultsMissingControlsToHome() {
        var rng = DiceRNG(seed: 77)
        let r = Dice.roll(target: 5, using: &rng)
        XCTAssertEqual(r.chain(sliderVals: [], buttonOn: []), r.base, "no live values ⇒ the base chain")
        let big = r.chain(sliderVals: Array(repeating: 0.5, count: 8), buttonOn: Array(repeating: true, count: 8))
        XCTAssertEqual(big.count, r.base.count, "extra live values neither trap nor grow the chain")
    }

    // THE ENSEMBLE ROLL (design 2026-08-19): 8 contrasting archetypes — every row audible + under the 6-note flood cap,
    // registers separated (a low and a high present), and a real density spread (the floor sparser than the peak).
    func testEnsembleRollIsAudibleRegisterSpreadAndDensitySpread() {
        for seed: UInt64 in [1, 7, 42, 99, 2024] {
            var rng = DiceRNG(seed: seed)
            let rows = Dice.rollEnsemble(using: &rng)
            XCTAssertEqual(rows.count, 8, "one row per archetype")
            for (i, row) in rows.enumerated() {
                XCTAssertFalse(Dice.signature(row.chain).isEmpty, "row \(i) sounds (seed \(seed))")
                XCTAssertLessThanOrEqual(Dice.peakAt6(row.chain), Dice.maxConcurrency, "row \(i) stays under the 6-note flood cap")
            }
            let transposes = rows.map { $0.transpose }
            XCTAssertLessThan(transposes.min()!, 0, "a LOW register is present (bass)")
            XCTAssertGreaterThan(transposes.max()!, 0, "a HIGH register is present (lead/sparkle)")
            let cx = rows.map { Dice.evalRun($0.chain).sig.count }.sorted()
            XCTAssertLessThan(cx.first!, cx.last!, "a real density spread — the sparsest floor below the densest peak")
        }
    }

    // The CAP is judged at a 6-note chord: a whole-chord striker's peak scales with chord size (an arp's does not).
    func testPeakAtSixExceedsPeakAtThreeForAWholeChordStriker() {
        var euclid = ProcessorSlot(type: .euclid)
        euclid.params.euclidPulses = 8; euclid.params.euclidSteps = 8; euclid.params.octaves = 1   // strikes the WHOLE chord every step
        XCTAssertGreaterThan(Dice.peakAt6([euclid]), Dice.evalRun([euclid]).peak, "6 held notes ring where 3 did")
    }

    // TUTTI PATTERN must SOUND through the Dice probe (Paul's favourite; the STAB archetype forces it). If it rendered
    // silent, rollArchetype's arp fallback would quietly replace it and the ensemble test wouldn't notice → STAB dead.
    func testRolledTuttiPatternActuallySoundsThroughTheProbe() {
        var s = ProcessorSlot(type: .tutti)
        s.params.tuttiMode = .pattern
        s.params.tuttiSlices = [.all, .rest, .low, .high, .all, .top2, .bot2, .all]   // a known non-all-ALL pattern
        s.params.tuttiRate = .r1_8
        XCTAssertFalse(Dice.signature([s]).isEmpty, "an authored TUTTI PATTERN sounds")
        XCTAssertGreaterThanOrEqual(Dice.evalRun([s]).peak, 1)
        // and randomSlot's seeded tutti-pattern (what the STAB archetype rides) is genuinely audible, not a dead no-op:
        for seed: UInt64 in [1, 5, 19, 77] {
            var rng = DiceRNG(seed: seed)
            var sl = Dice.randomSlot(using: &rng); sl.type = .tutti; sl.params.tuttiMode = .pattern
            XCTAssertFalse(Dice.signature([sl]).isEmpty, "randomSlot's tutti-pattern sounds (seed \(seed)) → STAB is a real tutti")
        }
    }
}
