//  PolyRiffRouterTests.swift — POLY RIFF ferry (2026-10-29), slice 1: the Router's POLY layer against the real engine. One lane, 4-of-4 at 1/4 (one hit a beat; a beat is 24 000 samples at 120 BPM / 48 kHz), a held 8-note pool
//  (rank r = pool[r − 1]), the riff walked over 16 columns.

import XCTest

private final class PolyEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

final class PolyRiffRouterTests: XCTestCase {
    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
    private let beat: Int64 = 24_000

    private func lane(gate: Double = 0.5, every: Int = 1, dir: RiffDir = .forward, length: Int? = nil, stride: Int = 1, step: Bool = false, invert: Bool = false, transpose: Int = 0, shift: Int = 0) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = gate; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        l.riffAdvanceEvery = every; l.riffDir = dir; l.riffLength = length; l.riffStride = stride; l.riffAdvanceStep = step; l.riffInvert = invert; l.melodyTranspose = transpose; l.riffRotate = shift
        return l
    }
    private func box(_ lines: [EuclidLine], poly: EuclideousPolyRiff?, on: Bool = true, mono: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], fx: EuclideousFX = EuclideousFX()) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: mono)
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousFX = fx
        if on { st.riffPoly = true }
        st.polyRiff = poly
        return SnapshotBuilder.build(from: st)
    }
    private func run(_ box: SnapshotBox, beats: Double, frames: UInt32 = 2048) -> PolyEmitter {
        let e = PolyEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    private func n(_ c: Int, _ r: Int, _ l: Int = 1) -> EuclideousPolyNote { EuclideousPolyNote(col: c, rank: r, len: l) }
    /// (on, off) pairs of one pitch on the lane's own output (cable 1), in order.
    private func soundings(_ e: PolyEmitter, _ note: UInt8) -> [(on: Int64, off: Int64)] {
        var out: [(on: Int64, off: Int64)] = []; var open: Int64?
        for ev in e.events where ev.cable == 1 && ev.note == note {
            if ev.status == 0x90 { open = ev.sample } else if ev.status == 0x80, let o = open { out.append((o, ev.sample)); open = nil }
        }
        XCTAssertNil(open, "note \(note) was left sounding")
        return out
    }
    private func near(_ a: Int64, _ b: Int64, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(Double(a), Double(b), accuracy: 2, msg, file: file, line: line) }

    // MARK: what sounds

    func testNotesStartOnTheirColumnAndRingForTheirLength() {
        // beat k reads column k (FWD, LEN 16). Rank 1 = 48 (length 1), rank 3 = 52 (length 2), column 2 is empty, rank 5 = 55 on column 3 (length 4).
        let poly = EuclideousPolyRiff(notes: [n(0, 1), n(1, 3, 2), n(3, 5, 4)])
        let e = run(box([lane()], poly: poly), beats: 16)
        let a = soundings(e, 48), b = soundings(e, 52), c = soundings(e, 55)
        near(a[0].on, 0); near(a[0].off, beat / 2, "length 1: gate 0.5 × one gap")
        near(b[0].on, beat); near(b[0].off, beat + beat + beat / 2, "length 2: the gap to the next hit in full, then gate × the one after")
        near(c[0].on, 3 * beat); near(c[0].off, 3 * beat + 3 * beat + beat / 2, "length 4: three full gaps, then gate × one")
        XCTAssertEqual(e.ons.filter { $0.cable == 1 && $0.sample < 15 * beat }.map { Int(($0.sample + 100) / beat) }, [0, 1, 3], "column 2 is a rest hit: nothing sounds there, and columns 4…15 are empty")
    }
    func testSeveralNotesInOneColumnSoundTogether() {
        let poly = EuclideousPolyRiff(notes: [n(0, 1), n(0, 3), n(0, 5, 3)])
        let e = run(box([lane()], poly: poly), beats: 8)
        let ons = e.ons.filter { $0.cable == 1 }
        XCTAssertEqual(Set(ons.prefix(3).map { $0.note }), [48, 52, 55]); XCTAssertEqual(Set(ons.prefix(3).map { $0.sample }), [0], "a chord: three note-ons at one sample")
        XCTAssertEqual(ons.filter { $0.sample == 0 }.count, 3)
        near(soundings(e, 48)[0].off, beat / 2); near(soundings(e, 52)[0].off, beat / 2); near(soundings(e, 55)[0].off, 2 * beat + beat / 2, "the lengths are each note's own")
    }
    func testANoteOutlivesTheNextColumnsStart() {
        // a long low note (48, 4 steps) with a short one starting under it on the second column: both are sounding at beat 1.2
        let poly = EuclideousPolyRiff(notes: [n(0, 1, 4), n(1, 5, 1)])
        let e = run(box([lane()], poly: poly), beats: 8)
        let long = soundings(e, 48)[0], short = soundings(e, 55)[0]
        XCTAssertLessThan(long.on, short.on); XCTAssertGreaterThan(long.off, short.off); XCTAssertGreaterThan(short.on, long.on)
        let at = beat + beat / 10
        XCTAssertTrue(long.on <= at && at < long.off && short.on <= at && at < short.off, "two different pitches sounding at once")
    }
    func testInvertAndTransposeActOnEachNote() {
        let poly = EuclideousPolyRiff(notes: [n(0, 1), n(0, 3)])
        // INVERT: 9 − r → ranks 8 and 6 = 60 and 57
        XCTAssertEqual(Set(run(box([lane(invert: true)], poly: poly), beats: 2).ons.filter { $0.cable == 1 && $0.sample == 0 }.map { $0.note }), [60, 57])
        // TRANS +2: ranks 3 and 5 = 52 and 55
        XCTAssertEqual(Set(run(box([lane(transpose: 2)], poly: poly), beats: 2).ons.filter { $0.cable == 1 && $0.sample == 0 }.map { $0.note }), [52, 55])
        // TRANS −1: rank 1 would be rank 0 — that note is dropped, the other (rank 2 = 50) sounds
        XCTAssertEqual(Set(run(box([lane(transpose: -1)], poly: poly), beats: 2).ons.filter { $0.cable == 1 && $0.sample == 0 }.map { $0.note }), [50])
    }
    func testAnEmptyPolyRiffIsSilent() {
        XCTAssertTrue(run(box([lane()], poly: EuclideousPolyRiff()), beats: 8).ons.isEmpty)
        XCTAssertTrue(run(box([lane()], poly: nil), beats: 8).ons.isEmpty, "POLY on with nothing written: silent, not the MONO riff")
    }

    // MARK: MONO is untouched and POLY matches it where it should

    func testPolyOffPlaysTheMonoRiffWhateverIsStored() {
        let stored = EuclideousPolyRiff(notes: [n(0, 8), n(1, 8)])
        let off = run(box([lane()], poly: stored, on: false), beats: 16), none = run(box([lane()], poly: nil, on: false), beats: 16)
        XCTAssertEqual(off.events, none.events); XCTAssertEqual(off.ons.filter { $0.cable == 1 && $0.sample < 14 * beat + beat / 2 }.count, 15)
        XCTAssertEqual(off.ons.filter { $0.cable == 1 }.prefix(8).map { $0.note }, pool, "MONO walks its eight ranks")
    }
    func testASeededPolyRiffSoundsExactlyLikeTheMonoRiff() {
        // the seed is the MONO riff twice over and a lane's LEN defaults to the grid's width, so the two modes play the same stream (FWD, REV, any EVERY, any gate)
        let mono = [1, 0, 3, 5, 0, 2, 8, 4]
        let seeded = EuclideousPolyRiff.seeded(from: EuclideousRiff(steps: 8, ranks: mono))
        for dir in [RiffDir.forward, .reverse] { for every in [1, 2, 3] { for gate in [0.3, 0.9] {
            let m = run(box([lane(gate: gate, every: every, dir: dir)], poly: nil, on: false, mono: mono), beats: 32)
            let p = run(box([lane(gate: gate, every: every, dir: dir)], poly: seeded, on: true, mono: mono), beats: 32)
            XCTAssertEqual(p.events, m.events, "\(dir) every \(every) gate \(gate)")
            XCTAssertFalse(m.events.isEmpty)
        } } }
    }

    // MARK: lengths under the walk's options

    func testLengthIsCountedInWalkStepsWhateverTheDirectionOrStride() {
        // one note of length L at rank 1, repeated on every column so every hit strikes it: the ring depends only on L and EVERY, never the walk order
        for dir in [RiffDir.forward, .reverse, .pendulum, .pingpong] { for stride in [1, 3] { for every in [1, 2, 3] { for len in [1, 2, 4] { for gate in [0.25, 0.9] {
            // notes at rank 1 every `len` columns, each `len` long (never touching the next); the walk of length 16 reaches them all
            let spaced = EuclideousPolyRiff(notes: stride2(len))
            let e = run(box([lane(gate: gate, every: every, dir: dir, stride: stride)], poly: spaced), beats: 24)
            let expected = Double((len - 1) * every) + gate
            let ss = soundings(e, 48)
            XCTAssertFalse(ss.isEmpty, "\(dir) stride \(stride) every \(every) len \(len)")
            // a strike that is followed by a re-strike of the same pitch is cut by it; the LAST strike of each run of consecutive hits rings its full length
            let rings = ss.map { Double($0.off - $0.on) / Double(beat) }
            XCTAssertTrue(rings.contains { abs($0 - expected) < 0.01 }, "\(dir) stride \(stride) every \(every) len \(len) gate \(gate): rings \(rings), expected \(expected)")
            for r in rings { XCTAssertLessThanOrEqual(r, expected + 0.01, "no strike rings longer than its length") }
        } } } } }
    }
    /// Notes at rank 1 every `len` columns, each `len` long (never touching the next).
    private func stride2(_ len: Int) -> [EuclideousPolyNote] { stride(from: 0, to: 16, by: max(1, len)).map { n($0, 1, len) } }

    func testALongNoteEndsAtAMelodyRestart() {
        // melody restart every pass (4 hits): a length-8 note struck on the first hit of a pass is cut at the next pass's first hit — 4 beats on
        var l = lane(length: 16)
        l.restartMelodyPasses = [1]
        let e = run(box([l], poly: EuclideousPolyRiff(notes: [n(0, 1, 8)])), beats: 12)
        let ss = soundings(e, 48)
        XCTAssertGreaterThanOrEqual(ss.count, 2)
        for s in ss { XCTAssertLessThanOrEqual(Double(s.off - s.on) / Double(beat), 4.0 + 0.01, "ended at (or before) the walk's restart") }
    }

    // MARK: things POLY switches off

    func testTheFXTabIsOffInPoly() {
        var fx = EuclideousFX(); fx.cells[0 * 8 + 0] = 3          // a RATCH ×3 on column 0
        fx.cells[1 * 8 + 0] = 40                                    // GATE 40 % on column 0
        let poly = EuclideousPolyRiff(notes: [n(0, 1)])
        let withFX = run(box([lane()], poly: poly, fx: fx), beats: 8), without = run(box([lane()], poly: poly), beats: 8)
        XCTAssertEqual(withFX.events, without.events, "the FX rows do nothing in POLY")
        let mono = run(box([lane()], poly: poly, on: false, fx: fx), beats: 8)
        XCTAssertNotEqual(mono.events, run(box([lane()], poly: poly, on: false), beats: 8).events, "…while they still act in MONO (the control)")
    }
    func testOnRestIsSkipInPoly() {
        let poly = EuclideousPolyRiff(notes: [n(0, 1), n(4, 3)])
        for rest in [EuclidRiffOnRest.skip, .tie, .repeatLast] {
            var l = lane(); l.riffOnRest = rest
            let e = run(box([l], poly: poly), beats: 16)
            XCTAssertEqual(e.ons.filter { $0.cable == 1 && $0.sample < 15 * beat }.map { [($0.sample + 100) / beat, Int64($0.note)] }, [[0, 48], [4, 52]], "ON REST \(rest): empty columns stay silent")
        }
    }
    func testBufferSizeNeverChangesAPolyStream() {
        let poly = EuclideousPolyRiff(notes: [n(0, 1, 3), n(0, 4), n(2, 6, 5), n(5, 2, 2), n(9, 8, 7), n(9, 3)])
        // the engine's beat → sample rounding depends on where a window starts (a sample either way, MONO too): compare note by note, a sample's tolerance on the time
        func sorted(_ e: PolyEmitter) -> [PolyEmitter.Ev] { e.events.sorted { ($0.cable, $0.note, $0.sample, $0.status) < ($1.cable, $1.note, $1.sample, $1.status) } }
        let ref = sorted(run(box([lane(every: 2)], poly: poly), beats: 24, frames: 512))
        for f: UInt32 in [64, 1024, 4096] {
            let got = sorted(run(box([lane(every: 2)], poly: poly), beats: 24, frames: f))
            XCTAssertEqual(got.count, ref.count, "frames \(f)")
            for (g, r) in zip(got, ref) {
                XCTAssertTrue(g.cable == r.cable && g.status == r.status && g.note == r.note && g.vel == r.vel && abs(g.sample - r.sample) <= 2, "frames \(f): \(g) vs \(r)")
            }
        }
    }

    // MARK: the LANES roll draws what the engine plays

    /// The roll's bars (`euclideousLaneRollHits`, the LANES panel's picture) against the notes the Router really sounds: the same hits at the same beats, the same pitches, and each bar as long as the note rings until the next
    /// strike of the same pitch cuts it — for random POLY riffs and every direction / EVERY / stride / length / shift / gate.
    func testTheRollMatchesTheEnginesNotesForRandomPolyLanes() {
        var rng = PolyRiffRNG(0x2011)
        let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]
        for seed in 0..<40 {
            var notes: [EuclideousPolyNote] = []
            for _ in 0..<(Int(rng.next() % 12) + 2) { notes.append(n(Int(rng.next() % 16), Int(rng.next() % 8) + 1, Int(rng.next() % 6) + 1)) }
            let poly = EuclideousPolyRiff(notes: notes)
            let l = lane(gate: [0.3, 0.6, 0.95][Int(rng.next() % 3)], every: Int(rng.next() % 3) + 1, dir: dirs[Int(rng.next() % 4)], length: rng.next() % 3 == 0 ? nil : Int(rng.next() % 16) + 1,
                         stride: Int(rng.next() % 5) + 1, shift: Int(rng.next() % 16))
            let e = run(box([l], poly: poly), beats: 40)
            let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, riffColumns: 16)!
            let hits = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: 30, minGateBeats: 0.01, polyStarts: { poly.startingNotes(at: $0) }) { c, _ in poly.topRanks[c] }
            let sounded = hits.filter { $0.rank >= 1 }
            // the engine's strikes in the window, keyed by (sample, pitch)
            let ons = e.ons.filter { $0.cable == 1 && $0.sample < 30 * beat - 100 }
            XCTAssertEqual(ons.count, sounded.count, "seed \(seed): the roll draws one bar per struck note")
            // a pitch struck again while it still rings stays on until the LAST holder ends (the engine's per-key reference count), so the wire's off for a run of overlapping strikes is the latest end among them
            for pitch in Set(sounded.map { pool[$0.rank - 1] }) {
                let bars = sounded.filter { pool[$0.rank - 1] == pitch }.sorted { $0.beat < $1.beat }
                var clusterEnds: [Double] = []
                var end = -1.0
                for bar in bars {
                    let start = bar.beat * Double(beat), stop = start + bar.gateBeats * Double(beat)
                    if end >= 0 && start < end - 2 { end = max(end, stop) } else { if end >= 0 { clusterEnds.append(end) }; end = stop }
                }
                if end >= 0 { clusterEnds.append(end) }
                let offs = e.offs.filter { $0.cable == 1 && $0.note == pitch && $0.sample > 0 }.map { Double($0.sample) }
                for ce in clusterEnds where ce < 30 * Double(beat) - 5 {
                    XCTAssertTrue(offs.contains { abs($0 - ce) <= 3 }, "seed \(seed): pitch \(pitch) should go off at \(ce / Double(beat)) beats (the roll's last bar of a run); the engine's offs: \(offs.map { $0 / Double(beat) })")
                }
            }
        }
    }

    // MARK: nothing sticks

    func testSeededPolyFuzzLeavesNothingSoundingAndNoOrphanOffs() {
        var rng = PolyRiffRNG(0xC0FFEE)
        for seed in 0..<60 {
            var notes: [EuclideousPolyNote] = []
            for _ in 0..<(Int(rng.next() % 14) + 1) { notes.append(n(Int(rng.next() % 16), Int(rng.next() % 8) + 1, Int(rng.next() % 16) + 1)) }
            let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]
            var l = lane(gate: [0.2, 0.5, 0.99][Int(rng.next() % 3)], every: Int(rng.next() % 4) + 1, dir: dirs[Int(rng.next() % 4)], length: Int(rng.next() % 16) + 1,
                         stride: Int(rng.next() % 7) + 1, step: rng.next() % 4 == 0, invert: rng.next() % 3 == 0, transpose: Int(rng.next() % 5) - 2, shift: Int(rng.next() % 16))
            l.pulses = Int(rng.next() % 4) + 1; l.steps = Int(rng.next() % 5) + 4
            if rng.next() % 3 == 0 { l.restartMelodyPasses = [UInt8(rng.next() % 3) + 1] }
            let frames = [256, 1024, 4096][Int(rng.next() % 3)]
            let e = run(box([l], poly: EuclideousPolyRiff(notes: notes)), beats: 40, frames: UInt32(frames))
            var open: [UInt16: Int] = [:]
            for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
                let k = UInt16(ev.cable) << 8 | UInt16(ev.note)
                if ev.status == 0x90 { open[k, default: 0] += 1 } else { open[k, default: 0] -= 1; XCTAssertGreaterThanOrEqual(open[k] ?? 0, 0, "seed \(seed): an off with no on") }
            }
            XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "seed \(seed): left sounding \(open.filter { $0.value != 0 })")
        }
    }
}
