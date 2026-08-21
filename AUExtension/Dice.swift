import Foundation

// THE DICE (user 2026-08-10) — generate LONG processor chains where EVERY slot CONTRIBUTES (bypassing it changes the
// output), plus continuous (slider) + binary (button) MACROS whose impact is EVALUATED by running the candidate chain
// OFFLINE through the real Router against a held chord and comparing the emitted notes. Foundation-only (no audio):
// reuses the same Router / SnapshotBuilder the live engine uses. Seedable for tests; the app rolls with the system RNG.

/// Records note ON/OFF events for offline chain evaluation — the output "signature" (note+onset), the richer
/// "fingerprint" (note+onset+velocity+gate), AND peak concurrent-voice count. ONs carry velocity; OFFs are kept
/// (with note) so a gate change — which moves the OFF — is visible without fragile on/off pairing.
final class DiceRecorder: MIDIEmitter {
    private(set) var ons: [(note: UInt8, cable: UInt8, sample: Int64, vel: UInt8)] = []
    private(set) var offs: [(note: UInt8, cable: UInt8, sample: Int64)] = []
    private(set) var events: [(on: Bool, cable: UInt8, sample: Int64)] = []   // for peak concurrency (density cap)
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        if st == 0x90 && b2 > 0 { ons.append((b1, cable, sampleTime, b2)); events.append((true, cable, sampleTime)) }
        else if st == 0x80 || (st == 0x90 && b2 == 0) { offs.append((b1, cable, sampleTime)); events.append((false, cable, sampleTime)) }
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
    // Note-affecting processor types only (the rationale for every pool below). MOD/GLIDE emit CC/pitch-bend, not notes
    // → the note-signature can't see them, so they'd always read as "non-contributing"; excluded. PASSGATE is excluded
    // too — open = no-op (never contributes), closed = silence (kills the chain); both degenerate.
    // WEIGHTED pick (user 2026-08-10): lean HARD into the rhythmic / swelling processors (arp · ratchet · euclid ·
    // burst · cascade · drone), and pull HARMONIZE right down — its fixed intervals drift out of key and there's no
    // scale-correction yet (raise it once a KEY-LOCK processor lands). Weights = repeats in the pool.
    static let weightedTypes: [ProcessorType] =
        Array(repeating: .arp,      count: 4) + Array(repeating: .ratchet, count: 4) +
        Array(repeating: .euclid,   count: 4) + Array(repeating: .burst,   count: 3) +
        Array(repeating: .cascade,  count: 3) + Array(repeating: .drone,   count: 3) +
        Array(repeating: .humanize, count: 2) + Array(repeating: .shift,   count: 2) +
        Array(repeating: .strum,    count: 2) + Array(repeating: .chance,  count: 4) +   // CHANCE up (Paul's favourite, 2026-08-19)
        Array(repeating: .tutti,    count: 4) +                                           // TUTTI added — was ABSENT (Paul's favourite, esp. PATTERN)
        Array(repeating: .echo,     count: 2) + Array(repeating: .harmonize, count: 1)   // MUCH LESS harmonizer

    // ROLE-BASED COMPOSITION (user 2026-08-11): the engine's LAST tick-generator is the DRIVER; slots BEFORE it shape
    // the source chord, non-driver HOLDS after it fold onto each tick, echo is a TAIL. So compose to a plan —
    // [slow shapers] · DRIVER · [post-fold holds] · [echo] — rather than a flat random stack. Upstream rhythm runs
    // SLOWER than the driver (a moving root under a faster figure — Paul's slow→fast insight).
    static let driverTypes: [ProcessorType] =                       // the rhythm engine (fast)
        Array(repeating: .arp, count: 3) + Array(repeating: .ratchet, count: 3) + Array(repeating: .euclid, count: 3) +
        Array(repeating: .burst, count: 2) + Array(repeating: .cascade, count: 2) + Array(repeating: .strum, count: 1) + [.drone]
    static let shaperTypes: [ProcessorType] =                       // upstream: a MOVING root / voicing (slow) — must
        Array(repeating: .arp, count: 3) + Array(repeating: .euclid, count: 2) +   // change the source, so NO drone (it just
        Array(repeating: .chance, count: 2) + [.harmonize, .tutti]                   // re-sustains the held chord → doesn't contribute upstream)
    static let postFoldTypes: [ProcessorType] = [.chance, .chance, .harmonize, .tutti]   // per-tick/step HOLD transforms (a driver here would BECOME the driver). NOT length: the dice only rolls DParam values, so a rolled LENGTH = default all-PASS = a no-op
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

    static let evalTempo = 120.0, evalSR = 48_000.0            // the fixed probe conditions (see runRecorder)
    static var evalPerBucket: Double { evalSR * 60.0 / evalTempo / 16.0 }   // samples per 1/16 beat

    /// The shared OFFLINE PROBE: install `chain` as a single cell's machine, hold C-E-G at vel 100, freeze the playhead
    /// on the column, run the REAL Router for 3 beats, and return the recorder. It's the actual engine's output for the
    /// chain against a STANDARD input (so two chains compare on equal footing), not a capture of live playing.
    static func runRecorder(_ chain: [ProcessorSlot], chord: [UInt8] = [60, 64, 67]) -> DiceRecorder {
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
        let pool = NotePool(); for n in chord { pool.noteOn(n, velocity: 100, channel: 0) }; pool.rebuildSorted()
        let frames: UInt32 = 4096   // big windows → few process calls (speed: this runs 100s of times per roll)
        let wb = Double(frames) * evalTempo / 60.0 / evalSR; var beat = 0.0, ts = 0.0
        while beat < 3.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: evalTempo, sampleRate: evalSR,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return e
    }

    /// The OUTPUT SIGNATURE (emitter-A note-ons: note + onset bucket) + peak concurrent voices. Note+onset only — two
    /// chains with the same signature share a note PATTERN (used by the roll's all-contributing pruning + complexity).
    static func evalRun(_ chain: [ProcessorSlot]) -> (sig: [Int], peak: Int) {
        let e = runRecorder(chain)
        let sig = e.ons.filter { $0.cable == 1 }
            .map { Int($0.note) * 100_000 + Int((Double($0.sample) / evalPerBucket).rounded()) }
            .sorted()
        return (sig, e.peakConcurrency)
    }
    static func signature(_ chain: [ProcessorSlot]) -> [Int] { evalRun(chain).sig }

    /// A RICHER fingerprint (Paul 2026-08-16): note + onset + VELOCITY + GATE, so value-only tweaks (a softer strike, a
    /// shorter note) register as distinct — not just note-pattern changes. ONs carry note/onset/velocity; OFFs carry
    /// note/off-time, so a gate change (which moves the OFF) shifts the off-tuple with no fragile on/off pairing.
    static func fingerprint(_ chain: [ProcessorSlot]) -> [Int] {
        let e = runRecorder(chain), pb = evalPerBucket
        var out: [Int] = []
        for on in e.ons where on.cable == 1 {
            let onset = Int((Double(on.sample) / pb).rounded()), velB = min(7, Int(on.vel) / 16)   // 8 velocity levels
            out.append(((Int(on.note) * 200 + onset) * 8 + velB) * 4 + 1)   // tag 1 = ON (note · onset · velocity)
        }
        for off in e.offs where off.cable == 1 {
            let ob = Int((Double(off.sample) / pb).rounded())
            out.append((Int(off.note) * 200 + ob) * 4 + 2)                  // tag 2 = OFF (its time encodes the gate)
        }
        return out.sorted()
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
        // TUTTI — favour PATTERN (Paul's favourite, 2026-08-19): an authored per-slice chord shape, never all-ALL (that
        // would be a no-op / non-contributing). These fields are only read when the slot's type is .tutti.
        s.params.tuttiMode = Int.random(in: 0...2, using: &rng) == 0 ? .coin : .pattern    // ~2/3 PATTERN
        var slices: [TuttiSlice] = (0..<8).map { _ in [.all, .all, .low, .high, .top2, .bot2, .rest].randomElement(using: &rng)! }
        if slices.allSatisfy({ $0 == .all }) { slices[Int.random(in: 0..<8, using: &rng)] = .rest }
        s.params.tuttiSlices = slices
        s.params.tuttiRate = [.r1_8, .r1_16, .r1_8t].randomElement(using: &rng)
        s.params.tuttiRotate = Int.random(in: 0...7, using: &rng)
        s.params.tuttiBalance = Double.random(in: 0.3...0.8, using: &rng)
        s.params.tuttiPick = TuttiPick.allCases.randomElement(using: &rng)
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
        while chain.count < 4 && budget > 0 { budget -= 1; _ = tryAdd(randomSlot(using: &rng)) }   // same gate as the role fills
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

    // MARK: - THE ENSEMBLE ROLL (design-ratified 2026-08-19)
    // The grid RANDOMIZE hands back A BAND, not 8 rolls: 8 CONTRASTING archetypes (pad · bass · stab · arp · groove ·
    // texture · sparkle · wild), each with its own REGISTER (transpose) and inherent DENSITY. The set is sparse-biased
    // (most sparse→medium, ONE dense = texture, the FLOOR = pad), so the caller's complexity sort orders something real.

    struct EnsembleRow: Equatable { var chain: [ProcessorSlot]; var transpose: Int }
    enum Archetype: CaseIterable { case pad, bass, stab, arp, groove, texture, sparkle, wild }

    /// The flood CAP is judged at a 6-note WORST-CASE chord (design 2026-08-19) — closes the under-prediction: arp-driven
    /// chains stay low-peak, whole-chord strikers double, so a real flood shows here. CHARACTER stays judged at 3 notes.
    static let cap6Chord: [UInt8] = [48, 52, 55, 60, 64, 67]
    static func peakAt6(_ chain: [ProcessorSlot]) -> Int { runRecorder(chain, chord: cap6Chord).peakConcurrency }

    /// A chain's DENSITY = note-ONS per beat, judged at the 3-note probe (CHARACTER at 3, per the design). The measure
    /// the density BUDGET BANDS constrain — so "sparse→dense" is real, not a guess.
    static func densityPerBeat(_ chain: [ProcessorSlot]) -> Double {
        Double(runRecorder(chain).events.filter { $0.on }.count) / 3.0   // onsets over the 3-beat probe
    }
    /// The events/beat BAND per archetype — a SPARSE-BIASED PYRAMID assigned BEFORE rolling so simple→complex is true
    /// BY CONSTRUCTION: the FLOOR (pad) genuinely sparse (a two-note pulse must be possible), ONE dense row (texture),
    /// the rest graded between. Default banding (Paul 2026-08-21) — tune by ear.
    static func archetypeBand(_ a: Archetype) -> (lo: Double, hi: Double) {
        switch a {
        case .pad:     return (0.0, 2.5)    // the FLOOR — a held pad / two-note pulse (a chord drone measures ~1–2)
        case .bass:    return (0.5, 3.5)
        case .stab:    return (0.5, 4.0)
        case .sparkle: return (1.0, 5.5)    // high + thinned by chance
        case .groove:  return (1.5, 6.5)
        case .arp:     return (2.0, 8.0)
        case .texture: return (3.5, 14.0)   // the ONE dense row
        case .wild:    return (0.3, 10.0)   // surprise — a wide band
        }
    }

    static func rollEnsemble(using rng: inout some RandomNumberGenerator) -> [EnsembleRow] {
        Archetype.allCases.map { rollArchetype($0, using: &rng) }
    }

    static func rollArchetype(_ a: Archetype, using rng: inout some RandomNumberGenerator) -> EnsembleRow {
        func attempt() -> [ProcessorSlot] {
            var s = randomSlot(using: &rng)
            switch a {
            case .pad:                                                    // sustained bed — the sparsest FLOOR row
                s.type = .drone; s.params.gate = Double.random(in: 0.85...1, using: &rng); return [s]
            case .bass:                                                   // low pulse of the BOTTOM note only
                var sp = randomSlot(using: &rng); sp.type = .split; sp.params.splitSet = ChordSplit(mode: .bottom, n: 1)
                s.type = .euclid; s.params.rate = [.r1_4, .r1_8].randomElement(using: &rng)
                s.params.euclidSteps = 8; s.params.euclidPulses = Int.random(in: 2...4, using: &rng); s.params.octaves = 1
                return [sp, s]
            case .stab:                                                   // rhythmic FULL-chord shapes via TUTTI PATTERN (Paul's favourite)
                s.type = .tutti; s.params.tuttiMode = .pattern             // randomSlot already seeded a non-all-ALL slice pattern + rate/rotate
                return [s]
            case .arp:                                                    // an arpeggio lead, up a register
                s.type = .arp; s.params.pattern = [.up, .down, .upDown].randomElement(using: &rng)
                s.params.rate = [.r1_16, .r1_8].randomElement(using: &rng); s.params.octaves = Int.random(in: 1...2, using: &rng)
                return [s]
            case .groove:                                                 // a syncopated euclid figure
                s.type = .euclid; s.params.rate = .r1_16; s.params.euclidSteps = [8, 16].randomElement(using: &rng)!
                s.params.euclidPulses = Int.random(in: 4...6, using: &rng); s.params.euclidRot = Int.random(in: 1...4, using: &rng); s.params.octaves = 1
                return [s]
            case .texture:                                                // the ONE dense row — the full role chain
                return buildByRole(using: &rng)
            case .sparkle:                                                // high, glittery, thinned by chance
                var ch = randomSlot(using: &rng); ch.type = .chance; ch.params.probability = Double.random(in: 0.45...0.7, using: &rng)
                s.type = .arp; s.params.pattern = .up; s.params.octaves = Int.random(in: 2...3, using: &rng)
                s.params.rate = [.r1_16t, .r1_32, .r1_16].randomElement(using: &rng)
                return [ch, s]
            case .wild:                                                   // surprise — a short all-contributing roll
                return rollSimple(using: &rng)
            }
        }
        // Keep a candidate that is AUDIBLE, under the flood cap, AND inside this archetype's DENSITY BUDGET BAND — so
        // the pyramid is true by construction (Paul 2026-08-21). Best-effort: if none fits the band in `tries`, keep the
        // last audible non-flooding one (the band biases, it isn't a hard gate); a silent/flooding result → the fallback.
        let band = archetypeBand(a)
        func fits(_ c: [ProcessorSlot]) -> Bool {
            let d = densityPerBeat(c)
            return d > 0 && d >= band.lo && d <= band.hi && peakAt6(c) <= maxConcurrency
        }
        var chain = attempt(); var tries = 6
        while !fits(chain) && tries > 0 { tries -= 1; chain = attempt() }
        if densityPerBeat(chain) == 0 || peakAt6(chain) > maxConcurrency {   // guaranteed-audible, non-flooding fallback
            var s = randomSlot(using: &rng); s.type = .arp; s.params.octaves = 1; s.params.rate = .r1_8; chain = [s]
        }
        return EnsembleRow(chain: chain, transpose: transposeFor(a, using: &rng))
    }

    /// REGISTER HOME per archetype — bass drops, lead/sparkle lift, the rest sit mid; wild wanders. (Colour.transpose.)
    private static func transposeFor(_ a: Archetype, using rng: inout some RandomNumberGenerator) -> Int {
        switch a {
        case .bass:            return -12
        case .pad:             return [-12, 0].randomElement(using: &rng)!
        case .arp, .sparkle:   return 12
        case .wild:            return [-12, 0, 12].randomElement(using: &rng)!
        default:               return 0
        }
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
        case .humanize: return "HUM"; case .tutti: return "TUT"; case .length: return "LEN"; case .weave: return "WVE"; case .split: return "SPL"; default: return "PROC"
        }
    }
}
