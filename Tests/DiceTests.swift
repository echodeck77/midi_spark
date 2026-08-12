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
}
