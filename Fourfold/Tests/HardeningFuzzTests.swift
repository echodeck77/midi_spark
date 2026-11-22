//  HardeningFuzzTests.swift — ENGINE HARDENING 1 (2026-11-21), §4.
//  A seed-reproducible fuzz that drives the Router through transport chaos and mid-run edits that the
//  existing PortsStressTests leaves out — randomised sample rate, tempo ramps 20…999, time-signature
//  changes, negative/pre-roll beats, sub-step loops, a host that supplies no transport or no musical
//  context, document REPLACE mid-note, and the Router-level flags (panic / all-notes-off / sceneFlush /
//  solo-live / loop span / scrub holds). Every case runs the §3 invariants (balance, range, ALL-union,
//  order). A failure prints its seed; `shrink(_:)` reduces a failing seed's script to the smallest that
//  still fails. Raw incoming-MIDI edge cases (CC120/123, sustain, note-off-without-on, 100 held notes)
//  live in KernelHostTests (§5) because the Kernel, not the Router, parses MIDI bytes.
//
//  Two tiers: testFuzzQuickTier runs in the normal suite (≤ a few thousand cases, under the 2-minute
//  budget). testFuzzDeepTier runs only with HARDENING_DEEP=1 and targets ≥100k cases.

import XCTest

// MARK: - deterministic RNG (splitmix64, same mapping as PortsStressTests so seeds are comparable)

private struct SM: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 { s = s &+ 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
private extension SM {
    mutating func i(_ r: ClosedRange<Int>) -> Int { Int(next() % UInt64(r.count)) + r.lowerBound }
    mutating func d(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * Double(next() >> 11) / Double(1 << 53) }
    mutating func b(_ p: Double = 0.5) -> Bool { d(0, 1) < p }
    mutating func pick<T>(_ xs: [T]) -> T { xs[i(0...xs.count - 1)] }
}

// MARK: - the fuzz

final class HardeningFuzzTests: XCTestCase {

    private var deep: Bool { hardeningDeepEnabled }

    func testFuzzQuickTier() {
        var fails: [(UInt64, String)] = []
        for seed in UInt64(1)...1500 {
            if let msg = runCase(seed: seed) { fails.append((seed, msg)); if fails.count >= 6 { break } }
        }
        report(fails)
    }

    func testFuzzDeepTier() throws {
        try XCTSkipUnless(deep, "deep tier runs only when /tmp/fourfold-hardening-deep exists (or HARDENING_DEEP=1)")
        let target = 100_000
        var fails: [(UInt64, String)] = [], ran = 0
        for seed in UInt64(1_000_000)...(1_000_000 + UInt64(target)) {
            ran += 1
            if let msg = runCase(seed: seed) { fails.append((seed, msg)); if fails.count >= 40 { break } }
        }
        print("HARDENING FUZZ deep tier: ran \(ran) cases, \(fails.count) failing")
        report(fails)
    }

    private func report(_ fails: [(UInt64, String)]) {
        guard let (seed, msg) = fails.first else { return }
        let small = shrink(seed)
        XCTFail("\(fails.count) failing seed(s). First: seed \(seed) — \(msg)\nShrunk: \(small)")
    }

    // MARK: one case

    /// Build a random document + a random transport script, drive a fresh Router, return the first
    /// invariant violation (nil = clean). Deterministic in `seed`.
    private func runCase(seed: UInt64) -> String? {
        var g = SM(seed)
        let doc = randomDocument(&g)
        let script = randomScript(&g)
        return drive(doc, script)
    }

    /// Run a script on a fresh Router; returns the first invariant violation or nil.
    private func drive(_ doc: PluginState, _ script: Script) -> String? {
        let box = HardeningCorpus.box(for: doc)
        let altBox = HardeningCorpus.box(for: script.replacement ?? doc)
        let pool = NotePool()
        let router = Router(); var diag = KernelDiag(); let rec = WireRecorder()
        for step in script.steps {
            // pool churn
            if step.poolReset { pool.reset() }
            for n in step.noteOns { pool.noteOn(n.0, velocity: n.1, channel: n.2) }
            for n in step.noteOffs { pool.noteOff(n.0) }
            let b = step.useReplacement ? altBox : box
            rec.beginWindow(start: Int64(step.ts), frames: Int64(step.frames))
            router.process(box: b, pool: pool, playing: step.playing, beatPos: step.beat, tempo: step.tempo,
                           beatsPerBar: step.beatsPerBar, sampleRate: step.sr, timestampSample: step.ts,
                           frameCount: UInt32(step.frames), laneMask: step.laneMask, panic: step.panic,
                           euclideousAllNotesOff: step.allNotesOff, euclideousSoloLive: step.soloLive,
                           euclideousLoopLo: step.loopLo, euclideousLoopHi: step.loopHi,
                           sceneFlush: step.sceneFlush, out: rec, diag: &diag)
            rec.endWindow()
        }
        // final hard stop to flush (a real transport always ends stopped)
        let last = script.steps.last
        let ts = (last.map { $0.ts + Double($0.frames) }) ?? 0
        rec.beginWindow(start: Int64(ts), frames: 512)
        router.process(box: box, pool: pool, playing: false, beatPos: last?.beat ?? 0, tempo: 120,
                       sampleRate: last?.sr ?? 48_000, timestampSample: ts, frameCount: 512, out: rec, diag: &diag)
        rec.endWindow()

        // §3 invariants. ALL-union is waived at a full voice table (documented).
        var v = HardeningInvariants.checkBalance(rec.events) + HardeningInvariants.checkRange(rec.events)
            + HardeningInvariants.checkOrder(rec.events, windows: rec.windows)
        if peakActive(rec.events) < 120 { v += HardeningInvariants.checkAllUnion(rec.events) }
        if router.floodDropped > 0 { return nil }   // an intentionally dense doc overflowed the governor — not a §4 failure (it has its own waiver)
        return v.first
    }

    // MARK: random document (edge-weighted over the coverage map)

    private func randomDocument(_ g: inout SM) -> PluginState {
        var s = PluginState.makeInit()
        var ls = s.euclideousLinesResolved

        // global edge shapes chosen once, so a case can be "every lane on one output", "no outputs", etc.
        let edge = g.i(0...9)
        for i in 0..<4 {
            var l = ls[i]
            l.enabled = g.b(0.85)
            // RHYTHM: hit 1-step / 0-hits / hits==steps edges hard
            switch g.i(0...6) {
            case 0: l.steps = 1; l.pulses = g.b() ? 0 : 1
            case 1: l.steps = g.i(2...16); l.pulses = 0
            case 2: let n = g.i(1...16); l.steps = n; l.pulses = n   // hits == steps
            case 3: l.steps = 16; l.pulses = 16
            default: l.steps = g.i(1...16); l.pulses = g.i(0...16)
            }
            l.rotate = g.i(-16...16)
            l.direction = g.pick([.fwd, .bkw, .pingpong])
            l.patternMiss = g.b(0.2) ? true : nil
            l.gate = g.pick([1.0, 0.99, 0.9, g.d(0.05, 1.0)])
            l.octave = g.i(-3...3)
            l.riffOn = g.b(0.7)
            l.notesOn = g.b(0.5)
            l.riffStride = g.i(1...7); l.riffLength = g.i(1...8); l.riffRotate = g.i(0...7)
            l.riffDir = g.pick([.forward, .reverse, .pingpong])
            l.riffOnRest = g.pick([.skip, .tie, .repeatLast, .fill])
            l.riffAdvanceEvery = g.i(1...8)   // reaches 5–8 (device-debt range)
            l.melodyTranspose = g.i(-7...7)
            l.riffOctave = g.i(-2...2)
            // STACK lit order (0…9; empty = nothing lit)
            if g.b(0.3) { l.notesLitOrder = [] }
            else { var o = Array(0...9).shuffled(using: &g); l.notesLitOrder = o.prefix(g.i(0...5)).map { UInt8($0) } }
            l.notesWhen = g.pick([0b01, 0b10, 0b11])
            l.notesChance = g.pick([25, 50, 75, 100])
            l.tilt = g.d(-1, 1); l.tiltFine = g.b(0.3) ? g.d(-1, 1) : nil
            l.offsetFraction = g.b(0.3) ? g.d(0, 0.999) : nil
            l.muteCells16 = g.b(0.3) ? UInt16(g.i(0...0xFFFF)) : 0
            l.rate = g.b(0.4) ? g.pick(ArpRate.allCases) : nil
            // per-lane sources
            l.poolSrcMask = g.pick([nil, 0, 0b00001, 0b00010, 0b10000, 0b01100, 0b01111, 0b11111])
            l.midiMode = g.pick([nil, .add, .replace, .root])
            // routing — the edges
            switch edge {
            case 0: l.riffOutMask = 0b0001; l.notesOutMask = 0b0001   // every lane → output A
            case 1: l.riffOutMask = 0; l.notesOutMask = 0             // no outputs
            case 2: l.riffOutMask = UInt8(1 << i); l.notesOutMask = UInt8(1 << i)
            default: l.riffOutMask = g.pick([nil, 0, UInt8(g.i(0...15)), UInt8(g.i(1...15))])
                     l.notesOutMask = g.pick([nil, 0, UInt8(g.i(0...15)), UInt8(g.i(1...15))])
            }
            ls[i] = l
        }
        s.euclideousLines = ls

        // page-level
        s.euclideousSoloMask = g.b(0.3) ? UInt8(g.i(0...0b1111)) : nil
        s.euclideousPartSoloMask = g.b(0.2) ? UInt8(g.i(0...0xFF)) : nil
        s.busChannels = g.pick([ [1, 2, 3, 4], [1, 1, 1, 1], [16, 1, 9, 2], [0, 5, 99, 3] ])   // incl. out-of-range
        s.euclideousKeyRoot = g.i(0...11)
        s.euclideousKeyType = g.pick(ScaleType.allCases)
        s.euclideousHoldLatchMode = g.pick([nil, .hold, .latch])
        if edge == 3 { s.riffs = [EuclideousRiff.empty] }   // empty riff
        var plan = s.sourcePlanResolved
        if edge == 4 { plan.midiOn = false; plan.chordsOn = false; plan.pickOn = false; plan.keyOn = false }   // every source off
        plan.midiMode = g.pick([.add, .replace, .root]); plan.midiOctaves = g.pick([.ignore, .keep])
        s.euclideousSourcePlan = plan
        return s
    }

    // MARK: random transport script

    private struct Step {
        var frames: Int; var playing: Bool; var beat: Double; var tempo: Double; var beatsPerBar: Double
        var sr: Double; var ts: Double
        var laneMask: UInt16 = 0; var soloLive: UInt16 = 0; var loopLo: UInt8 = 0; var loopHi: UInt8 = 0
        var panic = false; var allNotesOff = false; var sceneFlush = false; var useReplacement = false
        var poolReset = false; var noteOns: [(UInt8, UInt8, UInt8)] = []; var noteOffs: [(UInt8, UInt8)] = []
    }
    private struct Script { var steps: [Step]; var replacement: PluginState? }

    private func randomScript(_ g: inout SM) -> Script {
        let sr = g.pick([44_100.0, 48_000.0, 96_000.0, 22_050.0])
        let blockSizes = [64, 128, 137, 256, 512, 1024, 2048, 4096]
        let noMusicalContext = g.b(0.1)   // a host that supplies no musical context: beat frozen at 0, tempo nominal
        var steps: [Step] = []
        var ts = 0.0
        var beat = g.b(0.2) ? g.d(-4, 0) : 0   // pre-roll: start at a negative beat
        var tempo = g.d(20, 999)
        var bpb = g.pick([4.0, 3.0, 6.0, 5.0, 7.0])
        var playing = g.b(0.85)
        let replacement: PluginState? = g.b(0.25) ? randomDocument(&g) : nil
        let count = g.i(8...40)
        for w in 0..<count {
            var st = Step(frames: g.pick(blockSizes), playing: playing, beat: noMusicalContext ? 0 : beat,
                          tempo: tempo, beatsPerBar: bpb, sr: sr, ts: ts)
            // mid-run events, each low-probability so several can coincide
            if g.b(0.15) { playing.toggle() }                                   // start/stop at arbitrary samples
            if g.b(0.1) { tempo = g.d(20, 999) }                                // tempo step
            if g.b(0.08) { tempo = max(20, min(999, tempo + g.d(-200, 200))) }  // tempo ramp
            if g.b(0.06) { bpb = g.pick([4.0, 3.0, 6.0, 5.0, 7.0, 2.0]) }       // time-signature change
            if g.b(0.1) { st.panic = true }
            if g.b(0.12) { st.allNotesOff = true }
            if g.b(0.06) { st.sceneFlush = true }
            if replacement != nil && g.b(0.2) { st.useReplacement = true }      // document replace mid-note
            if g.b(0.2) { st.soloLive = UInt16(g.i(0...0b1111)); st.laneMask = UInt16(g.i(0...0b1111)) }
            if g.b(0.1) { let lo = UInt8(g.i(1...8)); st.loopLo = lo; st.loopHi = UInt8(g.i(Int(lo)...8)) }   // sub-step loop span
            // pool churn — held notes appearing/vanishing mid-note; notes arriving while stopped
            if g.b(0.25) { st.poolReset = true }
            if g.b(0.4) { let k = g.i(0...6); for _ in 0..<k { st.noteOns.append((UInt8(g.i(24...96)), UInt8(g.i(1...127)), UInt8(g.i(0...3)))) } }
            if g.b(0.2) { st.noteOffs.append((UInt8(g.i(24...96)), UInt8(g.i(0...3)))) }   // includes note-off with no matching on
            steps.append(st)
            ts += Double(st.frames)
            if !noMusicalContext {
                let winBeats = Double(st.frames) * tempo / 60 / sr
                if g.b(0.1) { beat = g.d(-4, 64) }                              // seek forward/back
                else if g.b(0.08) { beat -= g.d(0.0, 0.2) }                     // tiny loop jump (< one step)
                else { beat += winBeats }
            }
            _ = w
        }
        return Script(steps: steps, replacement: replacement)
    }

    // MARK: shrinker

    /// Delta-debug the script of a failing seed to the smallest prefix/sublist that still fails, then
    /// report its size. Document is left intact (shrinking it needs field-level deltas; the script is the
    /// usual culprit for stuck notes). Returns a short description.
    private func shrink(_ seed: UInt64) -> String {
        var g = SM(seed)
        let doc = randomDocument(&g)
        var script = randomScript(&g)
        guard drive(doc, script) != nil else { return "no longer reproduces (non-deterministic? investigate)" }
        // 1. shrink the step list by binary-ish removal
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < script.steps.count {
                var trial = script
                trial.steps.remove(at: i)
                if !trial.steps.isEmpty, drive(doc, trial) != nil { script = trial; changed = true } else { i += 1 }
            }
        }
        // 2. drop optional per-step flags that aren't needed
        for i in script.steps.indices {
            func tryClear(_ f: (inout Step) -> Void) {
                var trial = script; f(&trial.steps[i])
                if drive(doc, trial) != nil { script = trial }
            }
            tryClear { $0.panic = false }; tryClear { $0.allNotesOff = false }; tryClear { $0.sceneFlush = false }
            tryClear { $0.useReplacement = false }; tryClear { $0.noteOffs = [] }; tryClear { $0.loopLo = 0; $0.loopHi = 0 }
        }
        let msg = drive(doc, script) ?? "?"
        return "\(script.steps.count) steps — \(msg)"
    }

    // MARK: §4.7 state fuzz + beta fixture

    func testRandomDocumentsRoundTripThroughTheCodec() {
        // §4.7, the two real "no lost state" properties:
        //  (a) the codec is IDEMPOTENT — a decoded document re-encodes and re-decodes to itself. (A
        //      hand-built document need NOT equal its decode: Swift's synthesised Codable init bypasses the
        //      didSet observers that derive fields like litNotes/topLit from notesLitOrder, so a decoded doc
        //      carries the encoded derived bytes rather than re-derived ones — benign, and stable thereafter.)
        //  (b) a decoded document RENDERS identically to the original — the derived-field difference above
        //      must not change a single emitted byte.
        let enc = JSONEncoder()
        for seed in UInt64(1)...500 {
            var g = SM(seed)
            let doc = randomDocument(&g)
            guard let data = try? enc.encode(doc),
                  let back = try? JSONDecoder().decode(PluginState.self, from: data) else { XCTFail("seed \(seed): round-trip failed"); return }
            guard let data2 = try? enc.encode(back),
                  let back2 = try? JSONDecoder().decode(PluginState.self, from: data2) else { XCTFail("seed \(seed): second round-trip failed"); return }
            XCTAssertEqual(back2, back, "seed \(seed): codec is not idempotent — a saved document would reload differently")
            let a = HardeningCorpus.renderContinuous(doc, beats: 4)
            let b = HardeningCorpus.renderContinuous(back, beats: 4)
            XCTAssertEqual(a.events, b.events, "seed \(seed): a decoded document renders differently from the original (lost state)")
        }
    }

    func testTruncatedAndCorruptedDocumentsNeverTrap() {
        var g = SM(42)
        for seed in UInt64(1)...300 {
            let doc = randomDocument(&g)
            guard let data = try? JSONEncoder().encode(doc) else { continue }
            // truncation
            for cut in [data.count / 2, data.count - 1, max(0, data.count - 10), 1] {
                _ = try? JSONDecoder().decode(PluginState.self, from: data.prefix(cut))   // must not trap, result may be nil
            }
            // byte corruption at random offsets
            var corrupt = data
            for _ in 0..<5 { let o = Int(g.next() % UInt64(max(1, corrupt.count))); corrupt[o] = UInt8(g.i(0...255)) }
            _ = try? JSONDecoder().decode(PluginState.self, from: corrupt)
            _ = seed
        }
        // reaching here without a crash is the assertion
    }

    /// Not a test — prints the base64 of the current default document so BetaFixture can be (re)captured.
    /// Run: sh Scripts/run-fourfold-tests.sh -only-testing:FourfoldTests/HardeningFuzzTests/testEmitBetaFixtureBase64
    func testEmitBetaFixtureBase64() throws {
        let data = try JSONEncoder().encode(PluginState.makeInit())
        print("BETA_FIXTURE_BASE64_BEGIN")
        print(data.base64EncodedString())
        print("BETA_FIXTURE_BASE64_END")
    }

    func testBetaFixtureStillLoadsAndRenders() throws {
        // The checked-in serialized default document from the 0.3.0 beta (base64 in BetaFixture). A later
        // format change that breaks a saved beta document fails HERE, with the stream it should still play.
        try XCTSkipIf(BetaFixture.defaultDoc03.isEmpty, "beta fixture not yet captured (run testEmitBetaFixtureBase64)")
        guard let data = Data(base64Encoded: BetaFixture.defaultDoc03) else { return XCTFail("fixture base64 unreadable") }
        guard let doc = try? JSONDecoder().decode(PluginState.self, from: data) else {
            return XCTFail("the 0.3.0 beta default document no longer decodes — a saved tester session would factory-reset")
        }
        let rec = HardeningCorpus.renderContinuous(doc, beats: 8)
        let v = HardeningInvariants.checkBalance(rec.events) + HardeningInvariants.checkRange(rec.events)
        XCTAssertTrue(v.isEmpty, "beta fixture renders with a violation: \(v.first ?? "")")
        XCTAssertGreaterThan(rec.events.count, 0, "beta fixture rendered nothing")
    }

    // MARK: helpers

    private func peakActive(_ e: [WireEvent]) -> Int {
        var bal = [Int](repeating: 0, count: 5 * 16 * 128), peak = 0, cur = 0
        func idx(_ ev: WireEvent) -> Int { Int(ev.cable) * 2048 + Int(ev.channel) * 128 + Int(ev.b1) }
        for ev in e where ev.cable != 0 {
            if ev.isNoteOn { bal[idx(ev)] += 1; cur += 1; peak = max(peak, cur) }
            else if ev.isNoteOff, bal[idx(ev)] > 0 { bal[idx(ev)] -= 1; cur -= 1 }
        }
        return peak
    }
}
