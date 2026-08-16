import XCTest
import Foundation

// ENGINE FUZZ HARNESS (Layer 1 of the fuzz+chaos plan, 2026-08-04). Seeded, deterministic sequences against the
// pure engine (Router + SnapshotBuilder + NotePool). Asserts INVARIANTS, not outputs. The SEED LAW: every run is
// replayable from its logged seed; a failing seed is PINNED in `testPinnedRegressionSeeds` (the LEGATO pattern).
//
// MIDI INPUT is generated in SPELLS, cycling HELD notes → SHORT notes → SILENCE (user 2026-08-04): a held spell
// sustains a chord across windows (adoption + drone), a short spell churns staccato on/off (note lifecycle), a
// silence spell empties the pool (settle → quiescence). Pathological orderings (off-before-on, double-on, full-128)
// are sprinkled throughout.

// mulberry32 — the same PRNG family as SealRNG; reproducible from a UInt32 seed (the SEED LAW).
private struct FuzzRNG {
    private var s: UInt32
    init(_ seed: UInt32) { s = seed &+ 0x9E3779B9 }
    mutating func u32() -> UInt32 {
        s &+= 0x6D2B79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ (t ^ (t >> 7)) &* (t | 61)
        return t ^ (t >> 14)
    }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(u32() % UInt32(n)) }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + int(max(1, hi - lo + 1)) }
    mutating func double() -> Double { Double(u32()) / Double(UInt32.max) }
    mutating func chance(_ p: Double) -> Bool { double() < p }
    mutating func note() -> UInt8 { UInt8(int(128)) }
    mutating func vel() -> UInt8 { let r = int(10); return r == 0 ? 0 : (r == 1 ? 1 : (r == 2 ? 127 : UInt8(range(1, 127)))) }  // vel extremes weighted in
}

private final class FuzzEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
}

private enum Spell: CaseIterable { case held, short, silence }

private struct FuzzResult {
    var events: [FuzzEmitter.Ev]
    var quiescent: Bool          // I8/I10: engine fully settled after the flush (authoritative — refcount/voices all zero)
    var soundingKeys: Int        // I1/I2: (cable,ch,note) whose LAST emitted event was an ON (must be 0). NOTE: NOT a
                                 // net on/off count — the collision refcount emits ONE off for several ons, so a net
                                 // count legitimately runs positive; the last-event-per-key is the correct sounding test.
    var boundsBad: String?       // I5: first out-of-range emitted value, if any
}

final class FuzzTests: XCTestCase {

    // MARK: random document (I12 exercises the builder; the run exercises the Router)
    private func randomDoc(_ r: inout FuzzRNG) -> PluginState {
        let types: [ProcessorType] = [.arp, .ratchet, .passgate, .strum, .chance, .harmonize, .echo,   // echo exercises the tail ring across edges
                                      .euclid, .burst, .cascade, .drone, .shift, .humanize,   // the generators — hammered for no-stuck-notes across every edge
                                      .mod,   // the CC generator — emits CC (no notes); its column-exit resets ride every edge
                                      .glide,   // notes→pitch-bend — its mono sustained voice must close on every flush (no stuck notes)
                                      .tutti,   // SET-level chance — per-step SOLO/TUTTI subset; hammered for no-stuck-notes across every edge
                                      .length,  // per-slice GATE override — its re-articulator + downstream override hammered for no-stuck-notes
                                      .weave]   // rank-clocked polyrhythm DRIVER — per-rank clocks hammered for no-stuck-notes across every edge
        // 40 colours (was 6) so cells reach indices ≥16 AND ≥33 — the unlimited-ephemeral-colours space, and the
        // exact range that overflowed the render override table (the 2026-08-15 SIGTRAP). The old 6-colour cap left
        // that whole corner permanently un-fuzzed — the same class that once made this suite vacuous. (Paul 2026-08-16)
        let ids = (0..<40).map { "c\($0)" }
        let colours = ids.map { id -> Colour in
            var c = Colour(colourID: id, type: types[r.int(types.count)])
            if c.type == .tutti && r.chance(0.5) { applyRandomTuttiPattern(&c.paramsA, &r) }   // exercise the per-slice cadence
            if c.type == .length && r.chance(0.5) { applyRandomLengthPattern(&c.paramsA, &r) }
            if c.type == .weave && r.chance(0.6) { applyRandomWeave(&c.paramsA, &r) }
            return c
        }
        var scene = SceneState.empty()
        let occupied = r.range(1, 40)
        for _ in 0..<occupied {
            let col = r.int(8), row = r.int(8)
            var cell = Cell(colourID: ids[r.int(ids.count)], buses: randomBuses(&r))
            if r.chance(0.7) { cell.inputReceiver = r.int(4) }        // most cells subscribe to a receiver
            if r.chance(0.4) {                                        // some carry a short chain
                let n = r.range(1, 3)
                cell.processors = (0..<n).map { _ -> ProcessorSlot in
                    var s = ProcessorSlot(type: types[r.int(types.count)])
                    if s.type == .tutti && r.chance(0.5) { applyRandomTuttiPattern(&s.params, &r) }
                    if s.type == .length && r.chance(0.5) { applyRandomLengthPattern(&s.params, &r) }
                    if s.type == .weave && r.chance(0.6) { applyRandomWeave(&s.params, &r) }
                    return s
                }
            }
            scene.cells[col][row] = cell
        }
        if r.chance(0.5) { scene.masterKey = r.range(-12, 12) }        // KEY± under held chords
        var st = PluginState(colours: colours, scenes: [scene])
        if r.chance(0.2) { st.ladderMode = true }                     // LADDER (exclusive columns) resolves in the builder
        st.busChannels = (0..<4).map { _ in r.range(1, 16) }
        st.receivers = (0..<4).map { i in
            var rv = Receiver(name: "\(i + 1)")
            rv.channel = r.int(17)                                    // 0 = OMNI … 16
            if r.chance(0.25) { let lo = r.int(128); rv.rangeLo = lo; rv.rangeHi = r.range(lo, 127) }
            if r.chance(0.15) { rv.inputEnabled = false }
            if r.chance(0.15) { rv.muted = true }
            if r.chance(0.20) { rv.bypass = true; rv.bypassDest = r.range(1, 15) }
            if r.chance(0.30) { rv.latchAdd = r.chance(0.5) }
            return rv
        }
        return st
    }
    private func applyRandomTuttiPattern(_ p: inout ColourParams, _ r: inout FuzzRNG) {
        p.tuttiMode = .pattern
        p.tuttiSlices = (0..<8).map { _ in TuttiSlice.allCases[r.int(TuttiSlice.allCases.count)] }   // incl. REST + octave shifts
        p.tuttiRate = ArpRate.allCases[r.int(ArpRate.allCases.count)]                                 // incl. the fastest rates
        p.tuttiRotate = r.int(8)
    }
    private func applyRandomLengthPattern(_ p: inout ColourParams, _ r: inout FuzzRNG) {
        p.lenSlices = (0..<8).map { _ in LenState.allCases[r.int(LenState.allCases.count)] }   // incl. MUTE cuts + SHORT/LONG
        p.lenShort = Double(r.range(5, 95)) / 100
        p.lenLong = Double(r.range(0, 100)) / 100                                                // incl. LONG rings-to-step-end
        p.lenRotate = r.int(8)
    }
    private func applyRandomWeave(_ p: inout ColourParams, _ r: inout FuzzRNG) {
        p.weaveMode = WeaveMode.allCases[r.int(WeaveMode.allCases.count)]   // LADDER + HARMONIC
        p.weaveBase = ArpRate.allCases[r.int(ArpRate.allCases.count)]        // incl. the fastest bass clocks
        p.weaveSpan = r.range(1, 8)
    }
    private func randomBuses(_ r: inout FuzzRNG) -> Set<Bus> {
        var s = Set<Bus>()
        for b in Bus.allCases where r.chance(0.5) { s.insert(b) }
        if s.isEmpty { s.insert(.a) }
        return s
    }

    // MARK: one seeded run — spells drive the pool; config/latch/scene events are sprinkled; then flush + assert.
    private func runFuzz(_ seed: UInt32, windows: Int = 64) -> FuzzResult {
        var r = FuzzRNG(seed)
        var doc = randomDoc(&r)
        var box = SnapshotBuilder.build(from: doc)          // I12: must not trap on any random doc
        let router = Router(); var diag = KernelDiag(); let out = FuzzEmitter()
        let pool = NotePool()
        var held: [UInt8] = []                              // notes currently down
        var shorts: [UInt8] = []                            // last window's staccato notes (released next window)
        var spell = Spell.held, spellLeft = r.range(3, 8)
        var latchMask: UInt8 = 0
        let sr = 48_000.0, tempo = 120.0; let frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0

        func noteOn(_ n: UInt8) { let v = r.vel(); if v == 0 { pool.noteOff(n) } else { pool.noteOn(n, velocity: v, channel: 0, cable: 1) } }

        for _ in 0..<windows {
            // advance the SPELL cycle: held → short → silence → held …
            if spellLeft == 0 {
                spell = Spell.allCases[(Spell.allCases.firstIndex(of: spell)! + 1) % Spell.allCases.count]
                spellLeft = r.range(3, 8)
                if spell != .held { held.forEach { pool.noteOff($0) }; held.removeAll() }   // leaving held releases the chord
                if spell == .silence { shorts.forEach { pool.noteOff($0) }; shorts.removeAll() }
            }
            spellLeft -= 1
            switch spell {
            case .held:
                if held.isEmpty || r.chance(0.3) { let n = r.note(); noteOn(n); held.append(n) }   // grow/sustain the chord
                if r.chance(0.1), let h = held.randomPick(&r) { noteOn(h) }                         // double-on a held note
            case .short:
                shorts.forEach { pool.noteOff($0) }; shorts.removeAll()                             // release last window's staccato
                for _ in 0..<r.range(1, 3) { let n = r.note(); noteOn(n); shorts.append(n) }
            case .silence:
                break                                                                              // pool stays empty
            }
            // pathological sprinkles (any spell)
            if r.chance(0.05) { pool.noteOff(r.note()) }                                            // off-before-on / stray off
            if r.chance(0.02) { for _ in 0..<20 { noteOn(r.note()) } }                              // dense blast toward full-128
            pool.rebuildSorted()

            // config / transport events (all RNG-driven → deterministic)
            if r.chance(0.10) { doc = mutate(doc, &r); box = SnapshotBuilder.build(from: doc) }     // config change mid-pass
            if r.chance(0.08) { latchMask ^= UInt8(1 << r.int(4)) }                                 // LATCH toggle while notes sound
            let playing = r.chance(0.9)
            let sceneFlush = r.chance(0.05)
            let panic = r.chance(0.02)
            let solo: UInt8 = r.chance(0.1) ? UInt8(r.int(16)) : 0
            let lane: UInt8 = r.chance(0.1) ? UInt8(1 << r.int(8)) : 0
            let masterKill = r.chance(0.03)
            var pools = [NotePool](); if latchMask != 0 { pools = (0..<4).map { _ in let p = NotePool(); p.captureFiltered(from: pool, filter: 0, cableMask: 0b1111); return p } }

            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, laneMask: lane, soloReceiverMask: solo,
                           masterKill: masterKill, panic: panic, sceneFlush: sceneFlush,
                           latchMask: latchMask, latchedPools: pools, out: out, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }

        // FLUSH + SETTLE, then measure the emitted stream (shared helpers — see above).
        _ = (held, shorts)   // released by pool.reset() inside flushAndSettle
        flushAndSettle(router: router, pool: pool, box: box, out: out, beat: &beat, ts: &ts, sr: sr, tempo: tempo, frames: frames)
        return measure(out, router)
    }

    private func mutate(_ doc: PluginState, _ r: inout FuzzRNG) -> PluginState {
        var d = doc
        var scene = d.scenes.first ?? SceneState.empty()
        let col = r.int(8), row = r.int(8)
        switch r.int(4) {
        case 0: scene.cells[col][row] = nil                                                        // DELETE a cell
        case 1: if var c = scene.cells[col][row] { c.buses = randomBuses(&r); scene.cells[col][row] = c }   // reroute
        case 2: if var c = scene.cells[col][row] { c.processors = c.processors?.isEmpty == false ? Array(c.processors!.dropLast()) : nil; scene.cells[col][row] = c }   // DELETE chain-head/tail
        default: scene.masterKey = r.range(-12, 12)
        }
        d.scenes = [scene]
        if r.chance(0.3), var recs = d.receivers, !recs.isEmpty { let i = r.int(recs.count); recs[i].muted.toggle(); d.receivers = recs }
        return d
    }

    // MARK: shared flush + measurement (used by every runner so the invariants read identically)

    /// FLUSH + SETTLE: empty the pool, drain, then a hard PANIC (flushes bypass too), then settle stopped. After this
    /// the engine MUST be fully closed regardless of what the run did — panic is the unconditional hard flush.
    private func flushAndSettle(router: Router, pool: NotePool, box: SnapshotBox, out: FuzzEmitter,
                               beat: inout Double, ts: inout Double, sr: Double, tempo: Double, frames: UInt32) {
        var diag = KernelDiag()
        pool.reset(); pool.rebuildSorted()
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        for i in 0..<3 {
            router.process(box: box, pool: pool, playing: i < 2, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, panic: i == 2, latchMask: 0, out: out, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
    }

    /// I5 bounds + I1/I2 sounding, from the emitted stream. A key is SOUNDING iff its LAST event was an ON (the
    /// collision refcount folds several ons into one off, so on,on,off is legal — the last event is what matters).
    private func measure(_ out: FuzzEmitter, _ router: Router) -> FuzzResult {
        var boundsBad: String?
        var last: [Int: UInt8] = [:]
        for ev in out.events {
            // NOTE on/off · CC (0xB0 — panic CC120/123 + the MOD generator) · PITCH BEND (0xE0 — GLIDE). All valid MIDI;
            // data bytes stay in range. (Before 2026-08-15 the fuzz used non-canonical colour IDs the builder skipped,
            // so it emitted nothing — the id-based builder lookup made it real, surfacing glide's legitimate 0xE0.)
            if !(ev.status == 0x80 || ev.status == 0x90 || ev.status == 0xB0 || ev.status == 0xE0) { boundsBad = boundsBad ?? "status \(ev.status)" }
            if ev.note > 127 { boundsBad = boundsBad ?? "note \(ev.note)" }
            if ev.vel > 127 { boundsBad = boundsBad ?? "vel \(ev.vel)" }
            if ev.cable > 4 { boundsBad = boundsBad ?? "cable \(ev.cable)" }
            if ev.chan > 15 { boundsBad = boundsBad ?? "chan \(ev.chan)" }
            if ev.status == 0x80 || ev.status == 0x90 {   // stuck-note tracking is NOTES only — CC never "sounds"
                last[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)] = ev.status
            }
        }
        let sounding = last.values.filter { $0 == 0x90 }.count
        return FuzzResult(events: out.events, quiescent: router.quiescent, soundingKeys: sounding, boundsBad: boundsBad)
    }

    // MARK: TRANSPORT CHAOS — adversarial HOST (2026-08-07). Everything the engine emits is DERIVED from beatPos
    // (invariant 2), so no pathological host schedule may strand a voice or break quiescence after the flush.
    // The chaos lives in the SCHEDULE: seek-backward, loop-to-top, big forward jumps, tempo/sample-rate switches,
    // and pathological block sizes (1 sample … 4096 … a prime), all while a chord is held across the discontinuities.
    private func runTransportChaos(_ seed: UInt32, windows: Int = 80) -> FuzzResult {
        var r = FuzzRNG(seed)
        let doc = randomDoc(&r)
        let box = SnapshotBuilder.build(from: doc)
        let router = Router(); var diag = KernelDiag(); let out = FuzzEmitter()
        let pool = NotePool()
        var held: [UInt8] = []
        var spell = Spell.held, spellLeft = r.range(3, 8)
        let tempos = [30.0, 60.0, 120.0, 180.0, 240.0, 999.0]
        let rates = [44_100.0, 48_000.0, 88_200.0, 96_000.0]
        let blocks: [UInt32] = [1, 16, 32, 64, 256, 512, 2048, 4096, 337]   // incl. a single sample + a prime
        var beat = 0.0, ts = 0.0, tempo = 120.0, sr = 48_000.0
        var frames: UInt32 = 2048
        func noteOn(_ n: UInt8) { let v = r.vel(); if v == 0 { pool.noteOff(n) } else { pool.noteOn(n, velocity: v, channel: 0, cable: 1) } }

        for _ in 0..<windows {
            // a held chord across a transport jump is the stuck-note trap; cycle held ↔ silence
            if spellLeft == 0 {
                spell = Spell.allCases[(Spell.allCases.firstIndex(of: spell)! + 1) % Spell.allCases.count]
                spellLeft = r.range(3, 8)
                if spell != .held { held.forEach { pool.noteOff($0) }; held.removeAll() }
            }
            spellLeft -= 1
            if spell == .held, held.isEmpty || r.chance(0.3) { let n = r.note(); noteOn(n); held.append(n) }
            pool.rebuildSorted()

            // adversarial host params (all RNG-driven → replayable)
            if r.chance(0.20) { tempo = tempos[r.int(tempos.count)] }
            if r.chance(0.12) { sr = rates[r.int(rates.count)] }
            if r.chance(0.25) { frames = blocks[r.int(blocks.count)] }
            let windowBeats = Double(frames) * tempo / 60.0 / sr

            // adversarial beat MOTION: normal advance · seek-backward · loop-to-top · big forward jump
            switch r.int(6) {
            case 0: beat = max(0, beat - r.double() * 4)               // seek backward
            case 1: beat = 0                                           // loop to the top
            case 2: beat += windowBeats * Double(r.range(4, 32))       // big forward jump
            default: beat += windowBeats                               // normal forward advance
            }
            ts += Double(frames)                                       // host sample clock stays monotonic

            router.process(box: box, pool: pool, playing: r.chance(0.75), beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames,
                           masterKill: r.chance(0.02), panic: r.chance(0.03), sceneFlush: r.chance(0.05),
                           sceneRestart: r.chance(0.05), latchMask: 0, out: out, diag: &diag)
        }
        flushAndSettle(router: router, pool: pool, box: box, out: out, beat: &beat, ts: &ts, sr: sr, tempo: tempo, frames: 2048)
        return measure(out, router)
    }

    // MARK: SNAPSHOT-SWAP CHAOS — republish the box at HIGH frequency while a chord sounds, changing the routing
    // UNDER the live notes (channels · buses · emitter-enables · key). A generation change alone doesn't flush
    // (only transport/scene/latch/panic EDGES do), so the close/adoption machinery + the unconditional panic must
    // retire the old (cable,ch,note) wires and never leave one stranded once the run flushes.
    private func runSnapshotSwapChaos(_ seed: UInt32, windows: Int = 80) -> FuzzResult {
        var r = FuzzRNG(seed)
        var doc = randomDoc(&r)
        var box = SnapshotBuilder.build(from: doc)
        let router = Router(); var diag = KernelDiag(); let out = FuzzEmitter()
        let pool = NotePool()
        var held: [UInt8] = []
        let sr = 48_000.0, tempo = 120.0; let frames: UInt32 = 2048
        let windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        func noteOn(_ n: UInt8) { let v = r.vel(); if v == 0 { pool.noteOff(n) } else { pool.noteOn(n, velocity: v, channel: 0, cable: 1) } }

        for _ in 0..<windows {
            // keep a chord alive most of the time — the point is swapping routing under sounding notes
            if held.count < 3 || r.chance(0.4) { let n = r.note(); noteOn(n); held.append(n) }
            if r.chance(0.15), !held.isEmpty { pool.noteOff(held.remove(at: r.int(held.count))) }   // drop one
            pool.rebuildSorted()

            if r.chance(0.6) { doc = swapRouting(doc, &r); box = SnapshotBuilder.build(from: doc) }  // high-freq swap

            router.process(box: box, pool: pool, playing: r.chance(0.85), beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames,
                           panic: r.chance(0.02), sceneFlush: r.chance(0.04), latchMask: 0, out: out, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        flushAndSettle(router: router, pool: pool, box: box, out: out, beat: &beat, ts: &ts, sr: sr, tempo: tempo, frames: frames)
        return measure(out, router)
    }

    /// Mutate ONLY the routing that sits under a sounding note — the emission identity (channel/bus/enable/key).
    private func swapRouting(_ doc: PluginState, _ r: inout FuzzRNG) -> PluginState {
        var d = doc
        var scene = d.scenes.first ?? SceneState.empty()
        switch r.int(4) {
        case 0: d.busChannels = (0..<4).map { _ in r.range(1, 16) }                                 // restamp exit channels
        case 1: d.busEnabled = (0..<4).map { _ in r.chance(0.7) }                                    // toggle emitter enables (close-on-disable)
        case 2: let col = r.int(8), row = r.int(8)                                                   // reroute an occupied cell's buses
                if var c = scene.cells[col][row] { c.buses = randomBuses(&r); scene.cells[col][row] = c }
        default: scene.masterKey = r.range(-12, 12)                                                  // transpose the held chord
        }
        d.scenes = [scene]
        if r.chance(0.3), var recs = d.receivers, !recs.isEmpty { let i = r.int(recs.count); recs[i].channel = r.int(17); d.receivers = recs }
        return d
    }

    // MARK: TESTS

    /// I1/I2/I5/I8/I10 — thousands of seeded sequences; a failure prints the SEED to pin. (I3 dropped for now: the
    /// naive voice-identity check flags legitimate refcount collisions — two cells → one wire note — as phantoms; a
    /// true adoption-phantom detector needs an adoption-aware hook. `Router.quiescent` is the authoritative no-hang net.)
    func testFuzzEngineInvariants() {
        for i in 0..<500 {
            let seed = UInt32(0xF0_0000 + i)
            let res = runFuzz(seed)
            XCTAssertNil(res.boundsBad, "I5 out-of-range emitted value (\(res.boundsBad ?? "")) — seed 0x\(String(seed, radix: 16))")
            XCTAssertEqual(res.soundingKeys, 0, "I1/I2 note left sounding after flush — seed 0x\(String(seed, radix: 16))")
            XCTAssertTrue(res.quiescent, "I8/I10 engine not quiescent after flush (leaked voice / dangling refcount) — seed 0x\(String(seed, radix: 16))")
        }
    }

    /// I6 — same seed ⇒ byte-identical emitted stream (run twice, diff).
    func testFuzzDeterminism() {
        for i in 0..<200 {
            let seed = UInt32(0xD0_0000 + i)
            let a = runFuzz(seed).events, b = runFuzz(seed).events
            XCTAssertEqual(a, b, "I6 non-deterministic output — seed 0x\(String(seed, radix: 16))")
        }
    }

    /// I12 — SnapshotBuilder totality: any random document builds without trapping into a well-formed box.
    func testBuilderTotality() {
        for i in 0..<4000 {
            var r = FuzzRNG(UInt32(0xB0_0000 + i))
            let box = SnapshotBuilder.build(from: randomDoc(&r))
            XCTAssertEqual(box.cells.count, 64, "builder must always yield 8×8 cells — seed \(i)")
            XCTAssertEqual(box.receiverRangeLo.count, 4)
        }
    }

    /// I13 — NotePool robustness under pathological orderings + capture with random filters/ranges.
    func testNotePoolRobustness() {
        for i in 0..<3000 {
            var r = FuzzRNG(UInt32(0xA0_0000 + i))
            let p = NotePool()
            for _ in 0..<r.range(1, 60) {
                switch r.int(3) {
                case 0: p.noteOn(r.note(), velocity: r.vel(), channel: UInt8(r.int(16)), cable: UInt8(r.range(1, 4)))
                case 1: p.noteOff(r.note())
                default: p.rebuildSorted()
                }
            }
            p.rebuildSorted()
            let f = UInt8(r.int(17)), lo = UInt8(r.int(128)), hi = UInt8(r.range(Int(lo), 127))
            let frozen = NotePool(); frozen.captureFiltered(from: p, filter: f, cableMask: 0b1111, noteLo: lo, noteHi: hi)
            let n = p.srcCount(filter: f, cableMask: 0b1111)          // must be in-bounds, never trap
            for k in 0..<n { _ = p.srcAscending(k, filter: f, cableMask: 0b1111) }
            XCTAssertGreaterThanOrEqual(frozen.srcCount(filter: 0), 0)
        }
    }

    /// TRANSPORT CHAOS — seek-backward / loop / tempo+rate jumps / pathological block sizes never strand a voice
    /// or break quiescence after the flush. A failure prints the SEED to pin.
    func testTransportChaosInvariants() {
        for i in 0..<300 {
            let seed = UInt32(0x71_0000 + i)
            let res = runTransportChaos(seed)
            XCTAssertNil(res.boundsBad, "transport chaos out-of-range (\(res.boundsBad ?? "")) — seed 0x\(String(seed, radix: 16))")
            XCTAssertEqual(res.soundingKeys, 0, "transport chaos left a note sounding after flush — seed 0x\(String(seed, radix: 16))")
            XCTAssertTrue(res.quiescent, "transport chaos not quiescent after flush — seed 0x\(String(seed, radix: 16))")
        }
    }

    /// SNAPSHOT-SWAP CHAOS — rerouting channels/buses/enables/key UNDER sounding notes never leaves a stranded
    /// (cable,ch,note) once the run flushes. A failure prints the SEED to pin.
    func testSnapshotSwapChaosInvariants() {
        for i in 0..<300 {
            let seed = UInt32(0x72_0000 + i)
            let res = runSnapshotSwapChaos(seed)
            XCTAssertNil(res.boundsBad, "swap chaos out-of-range (\(res.boundsBad ?? "")) — seed 0x\(String(seed, radix: 16))")
            XCTAssertEqual(res.soundingKeys, 0, "swap chaos left a note sounding after flush — seed 0x\(String(seed, radix: 16))")
            XCTAssertTrue(res.quiescent, "swap chaos not quiescent after flush — seed 0x\(String(seed, radix: 16))")
        }
    }

    /// I6 for the chaos runners — same seed ⇒ byte-identical emitted stream (the SEED LAW makes every failure replayable).
    func testChaosDeterminism() {
        for i in 0..<80 {
            let ts = UInt32(0x73_0000 + i)
            XCTAssertEqual(runTransportChaos(ts).events, runTransportChaos(ts).events, "transport chaos non-deterministic — seed 0x\(String(ts, radix: 16))")
            let ss = UInt32(0x74_0000 + i)
            XCTAssertEqual(runSnapshotSwapChaos(ss).events, runSnapshotSwapChaos(ss).events, "swap chaos non-deterministic — seed 0x\(String(ss, radix: 16))")
        }
    }

    /// Pinned regression seeds — a fuzz/chaos failure gets its seed added to the matching list so the crash becomes
    /// a commissioned test (the LEGATO pattern). Each list replays through its own runner.
    func testPinnedRegressionSeeds() {
        func assertClean(_ res: FuzzResult, _ seed: UInt32, _ what: String) {
            let s = "pinned \(what) seed 0x\(String(seed, radix: 16))"
            XCTAssertNil(res.boundsBad, s); XCTAssertEqual(res.soundingKeys, 0, s); XCTAssertTrue(res.quiescent, s)
        }
        // NOTE: all three lists are empty, so this test is an intentional green no-op until a fuzz/chaos failure
        // commissions a seed here. Don't mistake its passing for "the pinned seeds are exercised". (Paul 2026-08-16)
        let pinnedFuzz: [UInt32] = []            // (none yet)
        let pinnedTransport: [UInt32] = []       // (none yet)
        let pinnedSwap: [UInt32] = []            // (none yet)
        for seed in pinnedFuzz { assertClean(runFuzz(seed), seed, "fuzz") }
        for seed in pinnedTransport { assertClean(runTransportChaos(seed), seed, "transport") }
        for seed in pinnedSwap { assertClean(runSnapshotSwapChaos(seed), seed, "swap") }
    }
}

private extension Array where Element == UInt8 {
    func randomPick(_ r: inout FuzzRNG) -> UInt8? { isEmpty ? nil : self[r.int(count)] }
}
