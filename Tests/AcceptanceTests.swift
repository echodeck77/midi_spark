//  AcceptanceTests.swift
//  ACCEPTANCE tests — the expected output is computed FROM THE CONCEPT (spec / music theory), never derived from the
//  engine's code, then checked against the REAL Router's output over a representative + boundary parameter matrix.
//  These are independent oracles: if the engine and the oracle disagree, ONE of them is wrong — and the oracle was
//  written without reading the implementation.
//
//  Substrate: the same fixed offline probe Dice.runRecorder uses (120 BPM · 48 kHz · column frozen · 3 beats), but
//  the HELD CHORD is a parameter, so a test can vary pitches AND velocities. See `Accept`.

import XCTest

/// One emitted note-on on emitter A, reduced to what an oracle reasons about: pitch, velocity, and onset bucket
/// (1/16-beat grid). Sample-exact timing is deliberately NOT asserted — the conceptual output is note/vel/order.
struct AcceptEvent: Equatable, Comparable {
    let note: Int, vel: Int, onset: Int
    static func < (a: AcceptEvent, b: AcceptEvent) -> Bool { a.onset != b.onset ? a.onset < b.onset : a.note < b.note }
}

enum Accept {
    static let chordCEG: [(UInt8, UInt8)] = [(60, 100), (64, 100), (67, 100)]   // C-E-G, uniform velocity

    /// Emitter-A note-ONs for `chain` holding `chord`, as (note, vel, onset-bucket), sorted by (onset, note).
    static func onsA(_ chain: [ProcessorSlot], chord: [(UInt8, UInt8)] = chordCEG) -> [AcceptEvent] {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .passgate)], scenes: [SceneState.empty()])
        st.colours[0].templateChain = chain.isEmpty ? [{ var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }()] : chain
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 0
        s.cells[0][0] = cell
        st.scenes = [s]; st.busChannels = [1, 2, 3, 4]
        st.synthesizeReceiversIfNeeded()
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = DiceRecorder()
        let pool = NotePool(); for (n, v) in chord { pool.noteOn(n, velocity: v, channel: 0) }; pool.rebuildSorted()
        let frames: UInt32 = 4096
        let wb = Double(frames) * Dice.evalTempo / 60.0 / Dice.evalSR; var beat = 0.0, ts = 0.0
        while beat < 3.0 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: Dice.evalTempo, sampleRate: Dice.evalSR,
                           timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        return e.ons.filter { $0.cable == 1 }
            .map { AcceptEvent(note: Int($0.note), vel: Int($0.vel), onset: Int((Double($0.sample) / Dice.evalPerBucket).rounded())) }
            .sorted()
    }

    /// The DISTINCT pitches emitter A sounds for `chain` holding `chord`.
    static func notesA(_ chain: [ProcessorSlot], chord: [(UInt8, UInt8)] = chordCEG) -> Set<Int> { Set(onsA(chain, chord: chord).map { $0.note }) }
}

// MARK: - HARMONIZE — an exact SET oracle

final class AcceptanceHarmonizeTests: XCTestCase {
    /// CONCEPT: HARMONIZE adds, to EVERY held note, each non-zero interval (0 = a voice OFF); the root stays. So the
    /// sounding pitch set is { b } ∪ { b+iv : iv≠0 } over every held note b, dropping anything outside 0…127.
    private func expected(chord: [Int], intervals: [Int]) -> Set<Int> {
        var out = Set(chord)
        for b in chord { for iv in intervals where iv != 0 { let n = b + iv; if (0...127).contains(n) { out.insert(n) } } }
        return out
    }
    func testHarmonizeAcrossIntervalCombos() {
        let chord = [60, 64, 67]
        let combos: [[Int]] = [[0, 0, 0], [4, 0, 0], [7, 0, 0], [4, 7, 0], [3, 7, -12], [12, 0, 0], [-12, 0, 0],
                               [4, 7, 12], [-5, 0, 0], [24, 0, 0], [1, 2, 3]]   // unisons/off, thirds, fifths, octaves, clusters
        for ivs in combos {
            var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = ivs
            XCTAssertEqual(Accept.notesA([h], chord: chord.map { (UInt8($0), UInt8(100)) }),
                           expected(chord: chord, intervals: ivs), "HARMONIZE intervals \(ivs)")
        }
    }
    // §2 POOL-STEP UNITS: with harmUnits = .pool, an interval is a DEGREE step up the pool (the held set), not semitones —
    // the diatonic third when the pool is a scale. Oracle uses the same poolStep the engine does (degree arithmetic).
    func testHarmonizePoolUnitsWalksScaleDegrees() {
        let scale = [60, 62, 64, 65, 67, 69, 71]   // C major realized (C D E F G A B) — the source pool
        var h = ProcessorSlot(type: .harmonize); h.params.harmIntervals = [2, 0, 0]; h.params.harmUnits = .pool
        var expect = Set(scale)
        for b in scale { expect.insert(poolStep(b, steps: 2, pool: scale)) }   // +2 degrees = the diatonic third of each note
        XCTAssertEqual(Accept.notesA([h], chord: scale.map { (UInt8($0), UInt8(100)) }), expect)
        // The SAME +2 in SEMITONES is a different (chromatic) set — proves the mode actually changes the output.
        var hs = ProcessorSlot(type: .harmonize); hs.params.harmIntervals = [2, 0, 0]   // default = semitones
        XCTAssertNotEqual(Accept.notesA([hs], chord: scale.map { (UInt8($0), UInt8(100)) }),
                          Accept.notesA([h], chord: scale.map { (UInt8($0), UInt8(100)) }))
    }
    func testTransposePoolUnitsStepsDegrees() {
        let scale = [60, 62, 64, 65, 67, 69, 71]
        var t = ProcessorSlot(type: .transpose); t.params.utilTranspose = 2; t.params.utilTransposeUnits = .pool
        let expect = Set(scale.map { poolStep($0, steps: 2, pool: scale) })   // every note up two scale degrees
        XCTAssertEqual(Accept.notesA([t], chord: scale.map { (UInt8($0), UInt8(100)) }), expect)
    }
}

// MARK: - SPLIT — an exact SUBSET × VELOCITY-WINDOW oracle (varies pitches AND velocities)

final class AcceptanceSplitTests: XCTestCase {
    /// CONCEPT: SPLIT keeps a subset of the chord — ALL, the TOP n or BOTTOM n by pitch, or the RANGE side of a split
    /// note — then a per-note velocity window [floor, ceil] filters what remains.
    private func expected(chord: [(Int, Int)], set: ChordSplit, vel: VelWindow) -> Set<Int> {
        let asc = chord.sorted { $0.0 < $1.0 }
        let keep: [(Int, Int)]
        switch set.mode {
        case .all:    keep = asc
        case .top:    keep = Array(asc.suffix(set.n))
        case .bottom: keep = Array(asc.prefix(set.n))
        case .range:  keep = asc.filter { set.high ? $0.0 >= set.note : $0.0 < set.note }
        }
        return Set(keep.filter { $0.1 >= vel.floor && $0.1 <= vel.ceil }.map { $0.0 })
    }
    func testSplitStandaloneAcrossModesAndVel() {
        let chord = [(60, 100), (64, 80), (67, 120)]   // varied velocities so the window bites mid-chord
        let sets: [ChordSplit] = [.init(mode: .all), .init(mode: .top, n: 1), .init(mode: .top, n: 2), .init(mode: .top, n: 3),
                                  .init(mode: .bottom, n: 1), .init(mode: .bottom, n: 2),
                                  .init(mode: .range, note: 64, high: true), .init(mode: .range, note: 64, high: false),
                                  .init(mode: .range, note: 66, high: true), .init(mode: .range, note: 100, high: true)]   // last: window above the whole chord → empty
        let vels: [VelWindow] = [.init(floor: 1, ceil: 127), .init(floor: 90, ceil: 127), .init(floor: 1, ceil: 90), .init(floor: 101, ceil: 110)]
        for set in sets { for vel in vels {
            var sp = ProcessorSlot(type: .split); sp.params.splitSet = set; sp.params.splitVel = vel
            XCTAssertEqual(Accept.notesA([sp], chord: chord.map { (UInt8($0.0), UInt8($0.1)) }),
                           expected(chord: chord, set: set, vel: vel), "SPLIT \(set.mode) n\(set.n) note\(set.note) vel[\(vel.floor),\(vel.ceil)]")
        } }
    }
}
