import Foundation

// THE DICE (user 2026-08-10) — generate LONG processor chains where EVERY slot CONTRIBUTES (bypassing it changes the
// output), plus continuous (slider) + binary (button) MACROS whose impact is EVALUATED by running the candidate chain
// OFFLINE through the real Router against a held chord and comparing the emitted notes. Foundation-only (no audio):
// reuses the same Router / SnapshotBuilder the live engine uses. Seedable for tests; the app rolls with the system RNG.

/// Records note ON/OFF events for offline chain evaluation — the output "signature" AND peak concurrent-voice count.
final class DiceRecorder: MIDIEmitter {
    private(set) var ons: [(note: UInt8, cable: UInt8, sample: Int64)] = []
    private(set) var events: [(on: Bool, cable: UInt8, sample: Int64)] = []   // for peak concurrency (density cap)
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        if st == 0x90 && b2 > 0 { ons.append((b1, cable, sampleTime)); events.append((true, cable, sampleTime)) }
        else if st == 0x80 || (st == 0x90 && b2 == 0) { events.append((false, cable, sampleTime)) }
    }
    /// Peak simultaneous SOUNDING voices on emitter A (cable 1) — off-before-on at a tie so a restrike doesn't spike.
    var peakConcurrency: Int {
        let evs = events.filter { $0.cable == 1 }.sorted { $0.sample != $1.sample ? $0.sample < $1.sample : (!$0.on && $1.on) }
        var running = 0, peak = 0
        for e in evs { running += e.on ? 1 : -1; peak = max(peak, running) }
        return peak
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

    // ROLE-BASED COMPOSITION (user 2026-08-11): the engine's LAST tick-generator is the DRIVER; slots BEFORE it shape
    // the source chord, non-driver HOLDS after it fold onto each tick, echo is a TAIL. So compose to a plan —
    // [slow shapers] · DRIVER · [post-fold holds] · [echo] — rather than a flat random stack. Upstream rhythm runs
    // SLOWER than the driver (a moving root under a faster figure — Paul's slow→fast insight).
    static let driverSet: Set<ProcessorType> = [.arp, .ratchet, .strum, .euclid, .burst, .cascade, .drone, .shift, .humanize]
    static let driverTypes: [ProcessorType] =                       // the rhythm engine (fast)
        Array(repeating: .arp, count: 3) + Array(repeating: .ratchet, count: 3) + Array(repeating: .euclid, count: 3) +
        Array(repeating: .burst, count: 2) + Array(repeating: .cascade, count: 2) + Array(repeating: .strum, count: 1) + [.drone]
    static let shaperTypes: [ProcessorType] =                       // upstream: a MOVING root / voicing (slow) — must
        Array(repeating: .arp, count: 3) + Array(repeating: .euclid, count: 2) +   // change the source, so NO drone (it just
        Array(repeating: .chance, count: 2) + [.harmonize]                          // re-sustains the held chord → doesn't contribute upstream)
    static let postFoldTypes: [ProcessorType] = [.chance, .chance, .harmonize]   // per-tick HOLD transforms only (a driver here would BECOME the driver)
    static let slowRates: [ArpRate] = [.r1_4, .r1_8, .r1_8t]
    static let fastRates: [ArpRate] = [.r1_16, .r1_16t, .r1_32]

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

    /// The most concurrent SOUNDING voices a chain may reach in the eval before it's rejected as a FLOOD (user
    /// 2026-08-10: "70 voices from two rows"). The spec's "density-capped" bound. Dev-tunable.
    static let maxConcurrency = 12

    /// One offline run of `chain` against a held chord (playhead frozen on the cell's column): returns the OUTPUT
    /// SIGNATURE (emitter-A note-ons: note + onset bucket) AND the PEAK concurrent voices. Deterministic (the engine
    /// derives everything from the beat), so two chains with the same signature are audibly identical here.
    static func evalRun(_ chain: [ProcessorSlot]) -> (sig: [Int], peak: Int) {
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
        let sig = e.ons.filter { $0.cable == 1 }
            .map { Int($0.note) * 100_000 + Int((Double($0.sample) / perBucket).rounded()) }
            .sorted()
        return (sig, e.peakConcurrency)
    }
    static func signature(_ chain: [ProcessorSlot]) -> [Int] { evalRun(chain).sig }

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

    /// True iff the chain is audible AND EVERY slot contributes — the invariant the build maintains at each step.
    static func allContribute(_ chain: [ProcessorSlot]) -> Bool {
        guard !chain.isEmpty else { return false }
        let full = signature(chain)
        guard !full.isEmpty else { return false }
        for k in 0..<chain.count where !contributes(chain, slot: k, sigFull: full) { return false }
        return true
    }
    /// A role slot: rolled params with the TYPE forced, and RATE-COHERENT for rhythm-gens — SLOW upstream (shaper),
    /// FAST as the driver — so a slow-moving root sits under a faster figure. euclid/ratchet density scales the same way.
    private static func roleSlot(type: ProcessorType, slow: Bool, using rng: inout some RandomNumberGenerator) -> ProcessorSlot {
        var s = randomSlot(using: &rng)          // reuse the param roll
        s.type = type
        if type == .arp || type == .euclid || type == .cascade {
            s.params.rate = (slow ? slowRates : fastRates).randomElement(using: &rng)
        }
        if type == .euclid {
            s.params.euclidSteps = slow ? [8, 16].randomElement(using: &rng)! : 16
            s.params.euclidPulses = slow ? Int.random(in: 2...4, using: &rng) : Int.random(in: 4...9, using: &rng)
        }
        if type == .ratchet { s.params.count = slow ? Int.random(in: 2...3, using: &rng) : Int.random(in: 3...6, using: &rng) }
        return s
    }
    /// Build to a musical PLAN — [1–2 slow shapers] · DRIVER (fast) · [post-fold hold] · [echo] — each stage added only
    /// if it stays audible + all-contributing + under the density cap (else skipped). Position = role, by construction.
    private static func buildByRole(using rng: inout some RandomNumberGenerator) -> [ProcessorSlot] {
        var chain: [ProcessorSlot] = []
        var sig = signature(chain)
        func tryAdd(_ slot: ProcessorSlot) -> Bool {
            let trial = chain + [slot]
            let (tsig, tpeak) = evalRun(trial)
            guard tsig != sig, !tsig.isEmpty, tpeak <= maxConcurrency else { return false }
            if allContribute(trial) { chain = trial; sig = tsig; return true }
            return false
        }
        /// Try up to `n` candidates for a role until one lands (each stage otherwise often fails the gates → short chains).
        func fillRole(_ n: Int, _ make: () -> ProcessorSlot) { for _ in 0..<n where !tryAdd(make()) {} }
        for _ in 0..<2 {                                                        // upstream SHAPERS (slow) — two attempts
            fillRole(4) { roleSlot(type: shaperTypes.randomElement(using: &rng)!, slow: true, using: &rng) }
        }
        fillRole(8) { roleSlot(type: driverTypes.randomElement(using: &rng)!, slow: false, using: &rng) }   // THE DRIVER (fast)
        fillRole(5) { roleSlot(type: postFoldTypes.randomElement(using: &rng)!, slow: false, using: &rng) }  // POST-FOLD hold (thins/doubles each tick)
        if Int.random(in: 0...2, using: &rng) == 0 {                            // ~1/3 ECHO tail
            fillRole(3) { roleSlot(type: .echo, slow: false, using: &rng) }
        }
        // TOP-UP: if the plan came up short, append any all-contributing + capped slot (weighted pool) to reach ≥4.
        var budget = 24
        while chain.count < 4 && budget > 0 {
            budget -= 1
            let trial = chain + [randomSlot(using: &rng)]
            let (tsig, tpeak) = evalRun(trial)
            guard tsig != sig, !tsig.isEmpty, tpeak <= maxConcurrency else { continue }
            if allContribute(trial) { chain = trial; sig = tsig }
        }
        return chain
    }
    static func rollChain(target: Int, using rng: inout some RandomNumberGenerator) -> [ProcessorSlot] {
        var best: [ProcessorSlot] = []                          // a few plan attempts; keep the LONGEST all-contributing chain (`target` = the ambition, not a hard length)
        for _ in 0..<3 {
            let c = buildByRole(using: &rng)
            if c.count > best.count { best = c }
            if best.count >= max(4, target - 1) { break }
        }
        return best
    }

    /// A SIMPLER roll (BUILD): a SHORT all-contributing chain of 1–3 slots — every slot changes the output when
    /// bypassed (`allContribute`), the chain never sounds empty, and it stays under the density cap. NO macros. (The
    /// full `roll(target:)` — with evaluated slider/button macros — is kept for elsewhere, e.g. the DRAG&DROP page.)
    static func rollSimple(using rng: inout some RandomNumberGenerator) -> [ProcessorSlot] {
        let want = Int.random(in: 1...3, using: &rng)
        var best: [ProcessorSlot] = []
        for _ in 0..<6 {                                         // a few attempts; keep the longest all-contributing ≤ want
            var chain: [ProcessorSlot] = []; var sig = signature(chain); var budget = 12
            while chain.count < want && budget > 0 {
                budget -= 1
                let trial = chain + [randomSlot(using: &rng)]
                let (tsig, tpeak) = evalRun(trial)
                guard tsig != sig, !tsig.isEmpty, tpeak <= maxConcurrency else { continue }
                if allContribute(trial) { chain = trial; sig = tsig }
            }
            if chain.count > best.count { best = chain }
            if best.count >= want { break }
        }
        if best.isEmpty {                                        // guarantee ≥1 audible slot — never a silent chain
            var budget = 24
            while budget > 0 { budget -= 1; let one = [randomSlot(using: &rng)]; if !signature(one).isEmpty { best = one; break } }
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
            // A MODERATE move toward the roomier side, not the far extreme (user 2026-08-11: full range isn't needed).
            // The eval below still drops it if the move changes nothing / floods.
            let alt: Double = {
                if p == .curve { let step = Double.random(in: 0.4...0.9, using: &rng); return max(-1, min(1, b + (b < 0 ? step : -step))) }
                let step = Double.random(in: 0.3...0.5, using: &rng); return max(0, min(1, b + (b < 0.5 ? step : -step)))
            }()
            var alt2 = base; setD(&alt2[k], p, alt)
            let e = evalRun(alt2)   // KEEP only if the full-slider morph changes the output AND doesn't flood (e.g. long gates overlapping)
            if e.sig != sigBase && e.peak <= maxConcurrency { out.append(SliderMacro(slot: k, param: p, base: b, alt: alt)) }
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
                let e = evalRun(alt)   // KEEP only if the switch changes the output AND doesn't flood (density cap)
                if e.sig != sigBase && e.peak <= maxConcurrency { out.append(m) }
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
