import Foundation

// THE DICE (user 2026-08-10) — generate LONG processor chains where EVERY slot CONTRIBUTES (bypassing it changes the
// output), plus continuous (slider) + binary (button) MACROS whose impact is EVALUATED by running the candidate chain
// OFFLINE through the real Router against a held chord and comparing the emitted notes. Foundation-only (no audio):
// reuses the same Router / SnapshotBuilder the live engine uses. Seedable for tests; the app rolls with the system RNG.

/// Records note-ONs for offline chain evaluation (a chain's output "signature").
final class DiceRecorder: MIDIEmitter {
    private(set) var ons: [(note: UInt8, cable: UInt8, sample: Int64)] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if (b0 & 0xF0) == 0x90 && b2 > 0 { ons.append((b1, cable, sampleTime)) }
    }
}

/// SplitMix64 — a tiny seedable RNG so a roll is reproducible in tests; the app passes the system RNG.
struct DiceRNG: RandomNumberGenerator {
    private var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Dice {
    // Note-affecting processor types only. MOD/GLIDE emit CC/pitch-bend, not notes → the note-signature can't see them,
    // so they'd always read as "non-contributing"; excluded from the pool.
    // PASSGATE is excluded — open = no-op (never contributes), closed = silence (kills the chain); both degenerate.
    static let types: [ProcessorType] = [.arp, .ratchet, .strum, .chance, .harmonize,
                                         .echo, .euclid, .burst, .cascade, .drone, .shift, .humanize]
    // WEIGHTED pick (user 2026-08-10): lean HARD into the rhythmic / swelling processors (arp · ratchet · euclid ·
    // burst · cascade · drone), and pull HARMONIZE right down — its fixed intervals drift out of key and there's no
    // scale-correction yet (raise it once a KEY-LOCK processor lands). Weights = repeats in the pool.
    static let weightedTypes: [ProcessorType] =
        Array(repeating: .arp,      count: 4) + Array(repeating: .ratchet, count: 4) +
        Array(repeating: .euclid,   count: 4) + Array(repeating: .burst,   count: 3) +
        Array(repeating: .cascade,  count: 3) + Array(repeating: .drone,   count: 3) +
        Array(repeating: .humanize, count: 2) + Array(repeating: .shift,   count: 2) +
        Array(repeating: .strum,    count: 2) + Array(repeating: .chance,  count: 2) +
        Array(repeating: .echo,     count: 2) + Array(repeating: .harmonize, count: 1)   // MUCH LESS harmonizer

    /// The continuous (Double, 0…1-ish) params a SLIDER can morph.
    enum DParam: CaseIterable { case gate, probability, spread, curve, ramp }

    struct SliderMacro: Equatable { var slot: Int; var param: DParam; var base: Double; var alt: Double }
    enum BinaryOp: Equatable { case bypass(Int); case switchType(Int, ProcessorType) }
    struct ButtonMacro: Equatable { var op: BinaryOp; var label: String }

    /// A rolled result: the all-contributing base chain + the evaluated slider/button macros. `chain(...)` composes the
    /// effective chain the engine renders, given the live slider positions (0…1) and button states.
    struct Result: Equatable {
        var base: [ProcessorSlot]
        var sliders: [SliderMacro]   // ≤ 4
        var buttons: [ButtonMacro]   // ≤ 4
        func chain(sliderVals: [Double], buttonOn: [Bool]) -> [ProcessorSlot] {
            var c = base
            for (i, m) in sliders.enumerated() where m.slot < c.count {
                let v = i < sliderVals.count ? max(0, min(1, sliderVals[i])) : 0
                Dice.setD(&c[m.slot], m.param, m.base + v * (m.alt - m.base))
            }
            for (i, b) in buttons.enumerated() where i < buttonOn.count && buttonOn[i] {
                switch b.op {
                case .bypass(let k):          if k < c.count { c[k].bypassed.toggle() }
                case .switchType(let k, let t): if k < c.count { c[k].type = t }
                }
            }
            return c
        }
    }

    // MARK: - Double param get / set

    static func getD(_ s: ProcessorSlot, _ p: DParam) -> Double {
        switch p {
        case .gate: return s.params.gate ?? 0.6; case .probability: return s.params.probability ?? 1
        case .spread: return s.params.spread ?? 0.1; case .curve: return s.params.curve ?? 0; case .ramp: return s.params.ramp ?? 0.5
        }
    }
    static func setD(_ s: inout ProcessorSlot, _ p: DParam, _ v: Double) {
        switch p {
        case .gate: s.params.gate = v; case .probability: s.params.probability = v
        case .spread: s.params.spread = v; case .curve: s.params.curve = v; case .ramp: s.params.ramp = v
        }
    }

    // MARK: - offline evaluation

    /// A chain's OUTPUT SIGNATURE: emitter-A note-ONs (note + 1/32-beat onset bucket) over a fixed run against a held
    /// chord, playhead frozen on the cell's column. Deterministic (the engine derives everything from the beat), so two
    /// chains with the same signature are audibly identical here — the basis for "does this slot / macro matter?".
    static func signature(_ chain: [ProcessorSlot]) -> [Int] {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .passgate)], scenes: [SceneState.empty()])
        st.colours[0].templateChain = chain.isEmpty
            ? [{ var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }()] : chain
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 0
        s.cells[0][0] = cell
        st.scenes = [s]; st.busChannels = [1, 2, 3, 4]
        st.synthesizeReceiversIfNeeded()
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = DiceRecorder()
        let pool = NotePool(); for n: UInt8 in [60, 64, 67] { pool.noteOn(n, velocity: 100, channel: 0) }; pool.rebuildSorted()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 4096   // big windows → few process calls (speed: this runs 100s of times per roll)
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        let perBucket = sr * 60.0 / tempo / 16.0
        while beat < 3.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return e.ons.filter { $0.cable == 1 }
            .map { Int($0.note) * 100_000 + Int((Double($0.sample) / perBucket).rounded()) }
            .sorted()
    }

    /// True iff bypassing slot `k` changes the output (i.e. the slot CONTRIBUTES). `sigFull` may be supplied to save a run.
    static func contributes(_ chain: [ProcessorSlot], slot k: Int, sigFull: [Int]? = nil) -> Bool {
        guard k >= 0, k < chain.count else { return false }
        var byp = chain; byp[k].bypassed.toggle()
        return (sigFull ?? signature(chain)) != signature(byp)
    }

    // MARK: - generation

    static func randomSlot(using rng: inout some RandomNumberGenerator) -> ProcessorSlot {
        var s = ProcessorSlot(type: weightedTypes.randomElement(using: &rng)!)   // rhythmic/swelling-weighted (user 2026-08-10)
        s.params.rate = ArpRate.allCases.randomElement(using: &rng)
        s.params.octaves = Int.random(in: 1...3, using: &rng)
        s.params.gate = Double.random(in: 0.3...0.95, using: &rng)
        s.params.count = Int.random(in: 2...6, using: &rng)
        s.params.ramp = Double.random(in: 0...1, using: &rng)
        s.params.spread = Double.random(in: 0...0.5, using: &rng)
        s.params.curve = Double.random(in: -0.6...0.6, using: &rng)
        s.params.probability = Double.random(in: 0.5...1, using: &rng)
        // HARMONIZE only as an OCTAVE JUMP / INVERSION (user 2026-08-10): octaves stay in key; thirds/fifths drift out
        // (no scale-correction yet). Intervals are octave multiples only, so a rolled harmonizer is always in key.
        s.params.harmIntervals = [[12, -12, 24, -24].randomElement(using: &rng)!, [12, -12, 0].randomElement(using: &rng)!, 0]
        s.params.euclidPulses = Int.random(in: 2...7, using: &rng)
        s.params.euclidSteps = [8, 16].randomElement(using: &rng)!
        s.params.echoRepeats = Int.random(in: 2...6, using: &rng)
        s.params.echoDelayDiv = [2, 3, 4, 6].randomElement(using: &rng)!
        return s
    }

    /// A chain of `target` slots (repeated types allowed) where EVERY slot CONTRIBUTES: build up, keeping a slot only if
    /// it changes the output; then PRUNE any slot whose bypass no longer changes the output (a later slot can mask an
    /// earlier one), repeated until stable — so bypassing any surviving slot has a tangible effect.
    /// True iff the chain is audible AND EVERY slot contributes — the invariant the build maintains at each step.
    static func allContribute(_ chain: [ProcessorSlot]) -> Bool {
        guard !chain.isEmpty else { return false }
        let full = signature(chain)
        guard !full.isEmpty else { return false }
        for k in 0..<chain.count where !contributes(chain, slot: k, sigFull: full) { return false }
        return true
    }
    /// Grow an ALL-CONTRIBUTING chain toward `target`: add a slot only if the whole chain stays audible AND every slot
    /// still contributes (a cheap "did it change?" pre-filter guards the expensive all-contributing check). No pruning
    /// — the invariant holds at every step. A light diversity nudge avoids same-type collapses (arp→arp masks).
    private static func buildAllContributing(target: Int, using rng: inout some RandomNumberGenerator) -> [ProcessorSlot] {
        var chain: [ProcessorSlot] = []
        var sig = signature(chain)
        var budget = target * 30
        while chain.count < target && budget > 0 {
            budget -= 1
            var cand = randomSlot(using: &rng)
            if cand.type == chain.last?.type { cand = randomSlot(using: &rng) }   // nudge away from immediate repeats
            let trial = chain + [cand]
            let tsig = signature(trial)
            guard tsig != sig, !tsig.isEmpty else { continue }                    // cheap: changed + audible
            if allContribute(trial) { chain = trial; sig = tsig }                 // expensive: full invariant, only on promising candidates
        }
        return chain
    }
    static func rollChain(target: Int, using rng: inout some RandomNumberGenerator) -> [ProcessorSlot] {
        var best: [ProcessorSlot] = []                          // a few whole-build attempts; keep the LONGEST all-contributing chain
        for _ in 0..<3 {
            let c = buildAllContributing(target: target, using: &rng)
            if c.count > best.count { best = c }
            if best.count >= target { break }
        }
        return best
    }

    /// Up to 4 SLIDER macros — each morphs one (slot, Double-param) toward the far end of its range, KEPT only if that
    /// change alters the output (so every slider is audible). `sigBase` is the base chain's signature (computed once).
    static func rollSliders(_ base: [ProcessorSlot], sigBase: [Int], using rng: inout some RandomNumberGenerator) -> [SliderMacro] {
        guard !base.isEmpty else { return [] }
        var out: [SliderMacro] = []
        var budget = 48
        while out.count < 4 && budget > 0 {
            budget -= 1
            let k = Int.random(in: 0..<base.count, using: &rng)
            let p = DParam.allCases.randomElement(using: &rng)!
            if out.contains(where: { $0.slot == k && $0.param == p }) { continue }
            let b = getD(base[k], p)
            let alt: Double = {
                if p == .curve { return b < 0 ? Double.random(in: 0.3...0.8, using: &rng) : Double.random(in: -0.8...(-0.3), using: &rng) }
                return b < 0.5 ? Double.random(in: 0.7...1.0, using: &rng) : Double.random(in: 0.0...0.3, using: &rng)
            }()
            var alt2 = base; setD(&alt2[k], p, alt)
            if signature(alt2) != sigBase { out.append(SliderMacro(slot: k, param: p, base: b, alt: alt)) }
        }
        return out
    }

    /// Up to 4 BUTTON (binary) macros — bypass a slot, or switch a slot's TYPE — KEPT only if the toggle changes the
    /// output. Bypassing a contributing slot always qualifies; a type switch is evaluated.
    static func rollButtons(_ base: [ProcessorSlot], sigBase: [Int], using rng: inout some RandomNumberGenerator) -> [ButtonMacro] {
        guard !base.isEmpty else { return [] }
        var out: [ButtonMacro] = []
        var budget = 48
        while out.count < 4 && budget > 0 {
            budget -= 1
            let k = Int.random(in: 0..<base.count, using: &rng)
            if Bool.random(using: &rng) {
                let m = ButtonMacro(op: .bypass(k), label: "BYP \(k + 1)")
                if !out.contains(m) { out.append(m) }                       // a contributing slot's bypass always changes output
            } else {
                let t = weightedTypes.filter { $0 != base[k].type }.randomElement(using: &rng)!   // weighted switch target (user 2026-08-10)
                let m = ButtonMacro(op: .switchType(k, t), label: "\(shortName(t))\(k + 1)")
                if out.contains(where: { if case .switchType(k, _) = $0.op { return true } else { return false } }) { continue }
                var alt = base; alt[k].type = t
                if signature(alt) != sigBase { out.append(m) }
            }
        }
        return out
    }

    /// One full roll: an all-contributing chain of `target` slots + its evaluated slider & button macros.
    static func roll(target: Int, using rng: inout some RandomNumberGenerator) -> Result {
        let base = rollChain(target: target, using: &rng)
        let sig = signature(base)
        return Result(base: base, sliders: rollSliders(base, sigBase: sig, using: &rng),
                      buttons: rollButtons(base, sigBase: sig, using: &rng))
    }

    static func shortName(_ t: ProcessorType) -> String {
        switch t {
        case .arp: return "ARP"; case .ratchet: return "RTC"; case .strum: return "STR"; case .passgate: return "GATE"
        case .chance: return "CHN"; case .harmonize: return "HRM"; case .echo: return "ECHO"; case .euclid: return "EUC"
        case .burst: return "BST"; case .cascade: return "CSC"; case .drone: return "DRN"; case .shift: return "SHF"
        case .humanize: return "HUM"; default: return "PROC"
        }
    }
}
