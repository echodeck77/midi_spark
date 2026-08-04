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
        let types: [ProcessorType] = [.arp, .ratchet, .passgate, .strum, .chance, .harmonize]
        let ids = (0..<6).map { "c\($0)" }
        let colours = ids.map { Colour(colourID: $0, type: types[r.int(types.count)]) }
        var scene = SceneState.empty()
        let occupied = r.range(1, 40)
        for _ in 0..<occupied {
            let col = r.int(8), row = r.int(8)
            var cell = Cell(colourID: ids[r.int(ids.count)], buses: randomBuses(&r))
            if r.chance(0.7) { cell.inputReceiver = r.int(4) }        // most cells subscribe to a receiver
            if r.chance(0.4) {                                        // some carry a short chain
                let n = r.range(1, 3)
                cell.processors = (0..<n).map { _ in ProcessorSlot(type: types[r.int(types.count)]) }
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

        // FLUSH + SETTLE: release everything, drain, then a hard PANIC (flushes bypass too), then settle stopped.
        held.forEach { pool.noteOff($0) }; shorts.forEach { pool.noteOff($0) }; pool.reset(); pool.rebuildSorted()
        for i in 0..<3 {
            router.process(box: box, pool: pool, playing: i < 2, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, panic: i == 2, latchMask: 0, out: out, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }

        // I5 bounds + I1/I2 sounding, from the emitted stream. A key is SOUNDING iff its LAST event was an ON (the
        // collision refcount folds several ons into one off, so on,on,off is legal — the last event is what matters).
        var boundsBad: String?
        var last: [Int: UInt8] = [:]
        for ev in out.events {
            if !(ev.status == 0x80 || ev.status == 0x90) { boundsBad = boundsBad ?? "status \(ev.status)" }
            if ev.note > 127 { boundsBad = boundsBad ?? "note \(ev.note)" }
            if ev.vel > 127 { boundsBad = boundsBad ?? "vel \(ev.vel)" }
            if ev.cable > 4 { boundsBad = boundsBad ?? "cable \(ev.cable)" }
            if ev.chan > 15 { boundsBad = boundsBad ?? "chan \(ev.chan)" }
            last[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)] = ev.status
        }
        let sounding = last.values.filter { $0 == 0x90 }.count
        return FuzzResult(events: out.events, quiescent: router.quiescent, soundingKeys: sounding, boundsBad: boundsBad)
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

    /// Pinned regression seeds — a fuzz failure gets its seed added here so the crash becomes a commissioned test.
    func testPinnedRegressionSeeds() {
        let pinned: [UInt32] = []   // (none yet)
        for seed in pinned {
            let res = runFuzz(seed)
            XCTAssertNil(res.boundsBad, "pinned seed 0x\(String(seed, radix: 16))")
            XCTAssertEqual(res.soundingKeys, 0, "pinned seed 0x\(String(seed, radix: 16))")
            XCTAssertTrue(res.quiescent, "pinned seed 0x\(String(seed, radix: 16))")
        }
    }
}

private extension Array where Element == UInt8 {
    func randomPick(_ r: inout FuzzRNG) -> UInt8? { isEmpty ? nil : self[r.int(count)] }
}
