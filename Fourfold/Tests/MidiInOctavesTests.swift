//  MidiInOctavesTests.swift — MIDI IN OCTAVES + ROOT (ferry 2026-11-01).
//  OCTAVES IGNORE (the default) folds the held notes to pitch classes voiced from KEY's base C; KEEP is today. MODE ROOT admits no played note: the lowest held note, less the reference C, moves the whole pool CHORDS / PICK / KEY
//  build — RAW semitones under both OCTAVES settings (Paul 2026-11-01), latched on release. The pure functions first, then the Router against the real engine (pool read from the status feed the page's POOL block uses).

import XCTest

private final class RigEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

/// The engine running window by window, with the held keys and the document under the test's control.
private final class Rig {
    let router = Router(), out = RigEmitter(), pool = NotePool()
    var box: SnapshotBox
    var diag = KernelDiag()
    var ts = 0.0
    let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * tempo / 60.0 / sr }
    func swap(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    func run(to b: Double) {
        while beat < b {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
            ts += Double(frames)
        }
    }
    /// `n` windows with the transport STOPPED (the engine keeps listening to the keys; nothing derives).
    func runStopped(_ n: Int) {
        for _ in 0..<n {
            router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: out, diag: &diag)
            ts += Double(frames)
        }
    }
    /// One playing window carrying a scene flush (what a session / preset load does).
    func flush() {
        router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, sceneFlush: true, out: out, diag: &diag)
        ts += Double(frames)
    }
    func press(_ n: [UInt8]) { for x in n { pool.noteOn(x, velocity: 100, channel: 0) } }
    func release(_ n: [UInt8]) { for x in n { pool.noteOff(x) } }
    func stop() { router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: out, diag: &diag) }
    var status: Router.EuclideousSourceStatus { router.euclideousSourceStatus() }
    var poolNotes: [Int] { status.poolNotes.map { Int($0) } }
    /// The note struck on each whole beat (0…) on one cable (-1 = nothing).
    func notes(cable: UInt8, beats: Int) -> [Int] {
        var r = [Int](repeating: -1, count: beats)
        for ev in out.ons where ev.cable == cable {
            let b = Int((Double(ev.sample) / 24_000.0).rounded())
            if b >= 0 && b < beats { r[b] = Int(ev.note) }
        }
        return r
    }
}

final class MidiInOctavesTests: XCTestCase {

    // MARK: fixtures

    private func plan(midi: Bool = true, chords: Bool = false, pick: Bool = false, key: Bool = false, mode: MidiMode = .add, pickNotes: [UInt8] = [], octaves: MidiOctaves? = nil) -> SourcePlan {
        SourcePlan(midiOn: midi, chordsOn: chords, pickOn: pick, keyOn: key, midiMode: mode, pickNotes: pickNotes, midiOctaves: octaves)
    }
    /// Lane 1 hits once a beat on `rank` of a flat riff (so each hit plays that rank of the pool); the others are silent. Output A = cable 1.
    private func state(_ plan: SourcePlan, rank: Int = 1, extra: [EuclidLine] = [], keyRoot: Int = 0, chordDegrees: [Int] = [0, 3, 4, 5], canonUnit: CanonUnit? = nil, lanePatch: ((inout EuclidLine) -> Void)? = nil) -> PluginState {
        func lane(pulses: Int) -> EuclidLine {
            var l = EuclidLine(target: 0, pulses: pulses, steps: 4)
            l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
            return l
        }
        var l0 = lane(pulses: 4)
        lanePatch?(&l0)
        var lines = [l0, lane(pulses: 0), lane(pulses: 0), lane(pulses: 0)]
        for (i, e) in extra.enumerated() where i + 1 < 4 { lines[i + 1] = e }
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [Int](repeating: rank, count: 8))
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = chordDegrees; cs.chordsSteps = chordDegrees.count; cs.chordsRate = .r1_1
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = plan
        st.euclideousKeyRoot = keyRoot
        st.euclideousKeyType = .major   // the page's default key is natural minor; the ferry's examples are C major
        st.euclideousCanonUnit = canonUnit
        return st
    }
    // MARK: the model (§1)

    func testAPlanWithoutTheFieldResolvesIgnoreAndOldValuesDecodeAsToday() throws {
        XCTAssertEqual(SourcePlan().midiOctavesR, .ignore)
        XCTAssertEqual(SourcePlan(midiOctaves: .keep).midiOctavesR, .keep)
        // an old stored plan (no field) decodes, resolves IGNORE, and ADD / REPLACE decode as before
        let old = #"{"chordsWithMidi":false,"chordsNoMidi":false,"keyWithMidi":false,"keyNoMidi":false,"midiOn":true,"chordsOn":false,"pickOn":false,"keyOn":true,"midiMode":"REPLACE","pickNotes":[]}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(SourcePlan.self, from: old)
        XCTAssertNil(p.midiOctaves); XCTAssertEqual(p.midiOctavesR, .ignore); XCTAssertEqual(p.midiModeR, .replace)
        // unknown values resolve to ADD / IGNORE instead of throwing
        let odd = #"{"chordsWithMidi":false,"chordsNoMidi":false,"keyWithMidi":false,"keyNoMidi":false,"midiMode":"SPLIT","midiOctaves":"HALF"}"#.data(using: .utf8)!
        let q = try JSONDecoder().decode(SourcePlan.self, from: odd)
        XCTAssertEqual(q.midiModeR, .add); XCTAssertEqual(q.midiOctavesR, .ignore)
        // ROOT and KEEP round-trip without loss
        let full = plan(key: true, mode: .root, octaves: .keep)
        let back = try JSONDecoder().decode(SourcePlan.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full); XCTAssertEqual(back.midiModeR, .root); XCTAssertEqual(back.midiOctavesR, .keep)
        // a plan that only carries the new field is a v2 plan, and the resolver keeps it
        XCTAssertTrue(SourcePlan(midiOctaves: .keep).hasV2)
        XCTAssertEqual(euclideousResolveSourcePlan(stored: SourcePlan(midiOctaves: .keep), legacySource: .key).midiOctavesR, .keep)
        XCTAssertEqual(euclideousResolveSourcePlan(stored: nil, legacySource: .key).midiOctavesR, .ignore, "every document, old ones included, defaults to IGNORE")
    }

    // MARK: the fold (§2.2)

    private func fold(_ notes: [Int], baseC: Int = 48) -> [Int] {
        let src = notes.map { (note: $0, vel: UInt8(100)) }
        var out = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 16)
        let n = euclideousFoldToBase(src[...], into: &out, baseC: baseC)
        return out[0..<n].map { $0.note }
    }
    func testTheFoldPutsTheLowestNoteInTheBaseOctaveAndTheRestCloseAbove() {
        // C3 = 48 here (C4 = 60, the page's naming)
        XCTAssertEqual(fold([72]), [48], "C5 → C3")
        XCTAssertEqual(fold([64, 67, 72]), [52, 55, 60], "E4 G4 C5 → E3 G3 C4")
        XCTAssertEqual(fold([48, 52, 55]), [48, 52, 55], "C3 E3 G3 → unchanged")
        XCTAssertEqual(fold([36, 60, 84]), [48], "C2 C4 C6 → C3 (one pitch class, one note)")
        XCTAssertEqual(fold([62, 65, 69, 72]), [50, 53, 57, 60], "D4 F4 A4 C5 → D3 F3 A3 C4")
        XCTAssertEqual(fold([71, 74, 77]), [59, 62, 65], "B4 D5 F5 → B3 D4 F4")
        XCTAssertEqual(fold([60, 61, 62, 63, 64, 65, 66, 67]), [48, 49, 50, 51, 52, 53, 54, 55], "eight distinct pitch classes → eight notes within one octave above the lowest")
        XCTAssertEqual(fold([]), [], "empty → empty")
        XCTAssertEqual(fold([67, 60, 64]), [48, 52, 55], "order of arrival does not matter (G4 C4 E4 → C3 E3 G3)")
        XCTAssertEqual(fold([43, 60, 64]), [55, 60, 64], "the lowest note sets the voicing: G2 C4 E4 → G3 C4 E4 (the G lands on its own pitch class in the base octave)")
        XCTAssertEqual(fold([43, 60, 64], baseC: 36), [43, 48, 52], "a different base C moves the whole voicing (base C2: G lands at G2)")
        let once = fold([64, 67, 72]); XCTAssertEqual(fold(once), once, "folding folded notes gives them back")
    }
    func testTheFoldCarriesTheVelocityOfTheLowestNoteOfAPitchClass() {
        let src: [(note: Int, vel: UInt8)] = [(76, 30), (64, 90), (67, 70)]   // E5 (30) and E4 (90): the lower one's velocity wins
        var out = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 16)
        let n = euclideousFoldToBase(src[...], into: &out, baseC: 48)
        XCTAssertEqual(out[0..<n].map { $0.note }, [52, 55]); XCTAssertEqual(out[0..<n].map { Int($0.vel) }, [90, 70])
    }

    // MARK: the root transpose (§2.5)

    func testTheRootTransposeIsTheRawDistanceFromTheBaseC() {
        // BASE C = C3 (48). Under BOTH octave settings (Paul 2026-11-01): no fold into −5…+6.
        let table: [(note: Int, t: Int)] = [(48, 0), (50, 2), (60, 12), (43, -5), (54, 6),   // C3 D3 C4 G2 F♯3
                                            (74, 26), (31, -17), (66, 18), (73, 25), (47, -1)]   // D5 G1 F♯4 C♯5 B2
        for (n, t) in table { XCTAssertEqual(euclideousRootTranspose(lowestHeld: n, baseC: euclideousKeyBaseC), t, "note \(n)") }
        XCTAssertEqual(euclideousKeyBaseC, 48)
        XCTAssertEqual(euclideousRootMoved(125, by: 6), 127, "pinned to the top")
        XCTAssertEqual(euclideousRootMoved(3, by: -17), 0, "pinned to the bottom")
        XCTAssertEqual([0, 2, -5, 26, -17, 79, -48].map { euclideousRootCountText($0) }, ["0", "+2", "\u{2212}5", "+26", "\u{2212}17", "+79", "\u{2212}48"])
    }
    func testPitchClassAndChipNames() {
        XCTAssertEqual(euclideousPitchClassName(64, flatKey: false), "E")
        XCTAssertEqual(euclideousPitchClassName(61, flatKey: false), "C\u{266F}")
        XCTAssertEqual(euclideousPitchClassName(61, flatKey: true), "D\u{266D}")
        XCTAssertEqual(euclideousMidiChipName(note: 52, octaves: .ignore, flatKey: false), "E")
        XCTAssertEqual(euclideousMidiChipName(note: 64, octaves: .keep, flatKey: false), "E4")
    }

    // MARK: the builder (§2.4, §2.6)

    private func build(midi: [Int] = [], playing: Bool = false, chords: [Int] = [], pick: [Int] = [], key: [Int] = [], plan: SourcePlan, t: Int = 0)
        -> (r: EuclideousStackResult, pool: [Int], chips: [UInt8]) {
        var dest = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
        var chips = [UInt8](repeating: 0, count: 8)
        let m = midi.map { (note: $0, vel: UInt8(100)) }
        let r = euclideousBuildSourceStack(into: &dest, cap: 128, midi: m[...], midiPlaying: playing, chords: chords[...], chordsIsRest: false, pick: pick[...], key: key[...],
                                           plan: plan, clash: .allow, midiStatusOut: &chips, rootTranspose: t)
        return (r, dest[0..<r.count].map { $0.note }, chips)
    }
    func testRootAdmitsNoPlayedNoteAndNeverStepsAside() {
        let cMaj = [48, 50, 52, 53, 55, 57, 59]
        let root = plan(chords: true, key: true, mode: .root)
        let b = build(midi: [41], playing: true, chords: [48, 52, 55], key: cMaj, plan: root)
        XCTAssertEqual(b.pool, build(chords: [48, 52, 55], key: cMaj, plan: root).pool, "CHORDS + KEY only: exactly the pool with nothing held; the played F2 enters nothing")
        XCTAssertEqual(b.r.midiAdded, 0); XCTAssertEqual(b.r.midiAdmitted, 0)
        XCTAssertTrue(b.r.chordsLit && b.r.keyLit, "CHORDS and KEY are allowed while MIDI plays — as if it weren't")
        XCTAssertTrue(b.r.midiPlaying, "MIDI IN still reads playing while a note is held")
        // the same document in REPLACE steps CHORDS and KEY aside while MIDI plays
        let rep = build(midi: [41], playing: true, chords: [48, 52, 55], key: cMaj, plan: plan(chords: true, key: true, mode: .replace))
        XCTAssertEqual(rep.pool, [41])
        let b2 = build(midi: [41], playing: true, chords: [48, 52, 55], plan: plan(chords: true, mode: .root))
        XCTAssertEqual(b2.pool, [48, 52, 55]); XCTAssertEqual(b2.chips, [UInt8](repeating: 0, count: 8), "no chip bytes written under ROOT")
        // ROOT alone: nothing contributes — an empty pool
        XCTAssertEqual(build(midi: [41], playing: true, plan: plan(mode: .root)).r.count, 0)
    }
    func testTheRootTransposeMovesEveryLayerAsTheLastStepAndClamps() {
        let p = plan(chords: true, pick: true, key: true, mode: .root, pickNotes: [72])
        let base = build(chords: [48, 52, 55], pick: [72], key: [48, 50, 52, 53, 55, 57, 59], plan: p)
        let moved = build(chords: [48, 52, 55], pick: [72], key: [48, 50, 52, 53, 55, 57, 59], plan: p, t: 2)
        XCTAssertEqual(moved.pool, base.pool.map { $0 + 2 }); XCTAssertEqual(moved.r.count, base.r.count)
        XCTAssertEqual(moved.r.chordsAdded, base.r.chordsAdded, "the per-source added counts are counted before the move")
        XCTAssertEqual(moved.r.keyAdded, base.r.keyAdded)
        XCTAssertEqual(build(plan: p, t: 5).r.count, 0, "an empty pool stays empty")
        let top = build(chords: [120, 124, 127], plan: plan(chords: true, mode: .root), t: 6)
        XCTAssertEqual(top.pool, [126, 127, 127], "clamped to 127 and still ascending (rank order kept)")
        XCTAssertEqual(build(chords: [3, 5], plan: plan(chords: true, mode: .root), t: -17).pool, [0, 0])
        // a single contributing layer is moved too (the short cut is not a way round it)
        XCTAssertEqual(build(chords: [60, 64, 67], plan: plan(midi: false, chords: true), t: 3).pool, [63, 67, 70])
    }

    // MARK: the Router — IGNORE (§2.2)

    func testIgnoreFoldsTheHeldChordIntoTheKeyBaseOctaveAndKeepDoesNot() {
        // E4 G4 C5 held, MIDI IN alone. The riff reads rank 1 (E3 / E4) and rank 4 (an octave copy above the three notes).
        let held: [UInt8] = [64, 67, 72]
        let ig = Rig(state(plan())); ig.press(held); ig.run(to: 2.5)
        XCTAssertEqual(ig.poolNotes, [52, 55, 60], "the pool is E3 G3 C4")
        XCTAssertEqual(ig.status.midiNotes, [52, 55, 60], "…and the chips are the folded notes")
        XCTAssertEqual(Array(ig.notes(cable: 1, beats: 3).suffix(1)), [52], "rank 1 plays E3")
        let ke = Rig(state(plan(octaves: .keep))); ke.press(held); ke.run(to: 2.5)
        XCTAssertEqual(ke.poolNotes, [64, 67, 72]); XCTAssertEqual(ke.status.midiNotes, [64, 67, 72])
        XCTAssertEqual(Array(ke.notes(cable: 1, beats: 3).suffix(1)), [64])
        // rank 4 = the lowest note an octave up
        let ig4 = Rig(state(plan(), rank: 4)); ig4.press(held); ig4.run(to: 2.5)
        XCTAssertEqual(Array(ig4.notes(cable: 1, beats: 3).suffix(1)), [64], "ranks beyond the folded notes are octave copies above: E4")
        let ke4 = Rig(state(plan(octaves: .keep), rank: 4)); ke4.press(held); ke4.run(to: 2.5)
        XCTAssertEqual(Array(ke4.notes(cable: 1, beats: 3).suffix(1)), [76])
        // the same chord two octaves lower folds to the same pool
        let low = Rig(state(plan())); low.press([40, 43, 48]); low.run(to: 2.5)
        XCTAssertEqual(low.poolNotes, ig.poolNotes, "wherever the hand sits, the pool is the same")
    }
    func testNothingHeldSoundsTheSameUnderEitherSetting() {
        // the default flip changes only what MIDI IN contributes: a KEY / CHORDS / PICK document with nothing held is the same stream, event for event, under IGNORE and KEEP
        for p in [plan(key: true), plan(chords: true), plan(chords: true, key: true), plan(pick: true, pickNotes: [60, 64, 67])] {
            var kp = p; kp.midiOctaves = .keep
            let a = Rig(state(p)), b = Rig(state(kp))
            a.run(to: 8.5); b.run(to: 8.5)
            XCTAssertEqual(a.out.events, b.out.events)
            XCTAssertFalse(a.out.ons.isEmpty)
            XCTAssertEqual(a.poolNotes, b.poolNotes)
        }
    }
    func testIgnoreWithKeyPlacesKeyAroundTheFoldedNotesNotAroundTheHand() {
        let held: [UInt8] = [64, 67, 72]
        let ig = Rig(state(plan(key: true))); ig.press(held); ig.run(to: 2.5)
        // E3 G3 C4 (mean 55) with C major around them: D3 F3 A3 B3 fill in nearest the mean
        XCTAssertEqual(ig.poolNotes, [50, 52, 53, 55, 57, 59, 60])
        let ke = Rig(state(plan(key: true, octaves: .keep))); ke.press(held); ke.run(to: 2.5)
        XCTAssertEqual(ke.poolNotes, [62, 64, 65, 67, 69, 71, 72], "KEEP: around E4, as today")
    }
    func testIgnoreWithReplaceStepsAsideWhileHeldAndReturnsAfterTheGrace() {
        let r = Rig(state(plan(chords: true, key: true, mode: .replace)))
        r.run(to: 1.5)
        XCTAssertFalse(r.poolNotes.isEmpty, "nothing held: CHORDS + KEY")
        let before = r.poolNotes
        r.press([72]); r.run(to: 2.5)
        XCTAssertEqual(r.poolNotes, [48], "a held C5 gives C3 only")
        r.release([72]); r.run(to: 3.5)
        XCTAssertEqual(r.poolNotes, before, "released: CHORDS and KEY return once RELEASE GRACE has passed")
    }

    // MARK: the Router — ROOT (§2.4, §2.5)

    private func rootState(octaves: MidiOctaves? = nil, key: Bool = true) -> PluginState { state(plan(chords: true, key: key, mode: .root, octaves: octaves), keyRoot: 0) }

    func testRootMovesTheWholeProgressionAndLatchesOnRelease() {
        let base = Rig(rootState()); base.run(to: 16.5)
        let baseline = base.notes(cable: 1, beats: 16)
        XCTAssertFalse(baseline.contains(-1), "the lane strikes every beat")
        let r = Rig(rootState())
        r.run(to: 0.5); r.press([50]); r.run(to: 8.5)       // D3 held through bars 1–2
        XCTAssertEqual(r.status.rootTranspose, 2); XCTAssertEqual(r.status.rootNote, 50)
        XCTAssertEqual(r.status.midiAdded, 0, "nothing played enters the pool")
        r.release([50]); r.run(to: 16.5)                    // …released: the latch carries it through bars 3–4
        XCTAssertEqual(r.status.rootTranspose, 2, "latched")
        let got = r.notes(cable: 1, beats: 16)
        for b in 1..<16 { XCTAssertEqual(got[b], baseline[b] + 2, "beat \(b): every pool note 2 higher, held or released") }
        XCTAssertEqual(got[0], baseline[0], "the hit before the first note is untransposed")
        XCTAssertEqual(r.status.midiNotes, [], "MIDI IN's chips hold no played notes in ROOT")
    }
    func testRootUsesTheLowestNoteOfAChordAndANoteAtTheBaseIsZero() {
        let r = Rig(rootState())
        r.run(to: 0.5); r.press([55, 59, 62]); r.run(to: 2.5)         // G3 B3 D4: the lowest, G3 (55) = +7
        XCTAssertEqual(r.status.rootTranspose, 7); XCTAssertEqual(r.status.rootNote, 55)
        r.release([55, 59, 62]); r.press([43, 47, 50]); r.run(to: 4.5)  // G2 B2 D3: the lowest, G2 (43) = −5
        XCTAssertEqual(r.status.rootTranspose, -5)
        r.release([43, 47, 50]); r.press([48]); r.run(to: 6.5)           // C3 → 0
        XCTAssertEqual(r.status.rootTranspose, 0); XCTAssertEqual(r.status.rootNote, 48)
        // the same under KEEP: the setting does not change the transpose
        let k = Rig(rootState(octaves: .keep)); k.run(to: 0.5); k.press([74]); k.run(to: 2.5)
        XCTAssertEqual(k.status.rootTranspose, 26, "D5 = +26 under KEEP …")
        let i = Rig(rootState(octaves: .ignore)); i.run(to: 0.5); i.press([74]); i.run(to: 2.5)
        XCTAssertEqual(i.status.rootTranspose, 26, "… and under IGNORE")
    }
    func testRootClearsWhenMidiGoesOffOrTheModeLeavesRoot() {
        let r = Rig(rootState())
        r.run(to: 0.5); r.press([50]); r.run(to: 2.5); r.release([50]); r.run(to: 4.5)
        XCTAssertEqual(r.status.rootTranspose, 2, "latched")
        // MIDI IN off mid-latch → 0 at once; back on → still 0 until a note
        r.swap(state(plan(midi: false, chords: true, key: true, mode: .root))); r.run(to: 5.5)
        XCTAssertEqual(r.status.rootTranspose, 0); XCTAssertEqual(r.status.rootNote, -1)
        r.swap(rootState()); r.run(to: 6.5)
        XCTAssertEqual(r.status.rootTranspose, 0, "back on: 0 until a note")
        r.press([50]); r.run(to: 7.5); XCTAssertEqual(r.status.rootTranspose, 2)
        // leaving ROOT for ADD → 0, and the held note enters the pool as IGNORE says
        r.swap(state(plan(chords: true, key: true, mode: .add)))
        r.run(to: 8.5)
        XCTAssertEqual(r.status.rootTranspose, 0)
        XCTAssertEqual(r.status.midiNotes, [50], "D3 folded is D3")
        r.press([51]); r.run(to: 9.5)   // D♯3 is NOT in the C major KEY, so only the admitted played note can put it in the pool
        XCTAssertEqual(r.status.midiNotes, [50, 51])
        XCTAssertTrue(r.poolNotes.contains(51), "leaving ROOT: the held note enters the pool as IGNORE says")
    }
    func testRootLeavesTheTransportAloneAndAReplaceDocumentSwitchedToRootContributes() {
        let r = Rig(rootState())
        r.run(to: 0.5); r.press([50]); r.run(to: 2.5); r.release([50])
        r.stop(); r.run(to: 4.5)   // a stop and a restart (§2.5e): t survives
        XCTAssertEqual(r.status.rootTranspose, 2)
        // a document in REPLACE switched to ROOT: CHORDS and KEY contribute while a note is held
        let q = Rig(state(plan(chords: true, key: true, mode: .replace)))
        q.press([60]); q.run(to: 2.5)
        XCTAssertEqual(q.poolNotes.count, 1, "REPLACE: only the played note")
        q.swap(rootState()); q.run(to: 3.5)
        XCTAssertGreaterThan(q.poolNotes.count, 1, "ROOT: CHORDS + KEY contribute while a note is held")
        XCTAssertEqual(q.status.midiAdded, 0)
    }

    // MARK: adversarial review 2026-11-01

    func testTheLatchFollowsWhatIsHeldEvenWhileTheTransportIsStopped() {
        let r = Rig(rootState())
        r.runStopped(4)
        r.press([50]); r.runStopped(4)                       // pressed with the transport stopped
        XCTAssertEqual(r.status.rootTranspose, 2); XCTAssertEqual(r.status.rootNote, 50)
        r.release([50]); r.runStopped(4)
        XCTAssertEqual(r.status.rootTranspose, 2, "latched while stopped, nothing held")
        r.run(to: r.beat + 1.5)                              // PLAY with nothing held: the pool is already moved
        let base = Rig(rootState()); base.run(to: r.beat)
        XCTAssertEqual(r.status.rootTranspose, 2)
        XCTAssertEqual(r.poolNotes, base.poolNotes.map { $0 + 2 })
        // MIDI IN switched off, then on, while STOPPED → cleared (§2.5c), and PLAY starts from 0
        r.runStopped(2); r.swap(state(plan(midi: false, chords: true, key: true, mode: .root))); r.runStopped(2)
        XCTAssertEqual(r.status.rootTranspose, 0); XCTAssertEqual(r.status.rootNote, -1)
        r.swap(rootState()); r.runStopped(2); r.run(to: r.beat + 1.5)
        XCTAssertEqual(r.status.rootTranspose, 0, "back on: 0 until a note")
        // leaving ROOT for ADD and returning while stopped clears too (§2.5d)
        r.press([50]); r.runStopped(2); XCTAssertEqual(r.status.rootTranspose, 2); r.release([50])
        r.swap(state(plan(chords: true, key: true, mode: .add))); r.runStopped(2); r.swap(rootState()); r.runStopped(2)
        XCTAssertEqual(r.status.rootTranspose, 0)
    }
    func testAHostResetDoesNotClearTheLatch() {
        // an AU reset() can arrive at a transport edge, a bypass or a sample-rate change; §2.5e says only a load (and MIDI off / leaving ROOT) clears t
        let r = Rig(rootState())
        r.run(to: 0.5); r.press([50]); r.run(to: 2.5); r.release([50]); r.run(to: 3.5)
        r.router.reset(); r.run(to: 4.5)
        XCTAssertEqual(r.status.rootTranspose, 2); XCTAssertEqual(r.status.rootNote, 50)
    }
    func testADelayedLaneMovesItsPoolByTheTOfItsOwnMoment() {
        // lane 1 is live, lane 2 hears the pool one BAR late. D3 is pressed at beat 8.5: the live lane moves at once, the delayed one a bar later (beat 13 reads beat 9)
        var delayed = EuclidLine(target: 0, pulses: 4, steps: 4)
        delayed.gate = 0.5; delayed.velocityAbsolute = 90; delayed.rate = .r1_4; delayed.useRiff = true; delayed.riffOn = true; delayed.sourceMode = .midi; delayed.notesOn = true; delayed.litNotes = 0
        delayed.chordDelay = 1
        let st = state(plan(chords: true, mode: .root), extra: [delayed], canonUnit: .bars)
        let base = Rig(st); base.run(to: 20.5)
        let r = Rig(st); r.run(to: 8.5); r.press([50]); r.run(to: 20.5)
        let b0 = base.notes(cable: 1, beats: 20), b1 = base.notes(cable: 2, beats: 20), a0 = r.notes(cable: 1, beats: 20), a1 = r.notes(cable: 2, beats: 20)
        XCTAssertFalse(b1.contains(-1)); XCTAssertNotEqual(b0, b1, "the delayed lane really is a bar behind")
        for b in 9..<20 { XCTAssertEqual(a0[b], b0[b] + 2, "live lane, beat \(b)") }
        for b in 9..<13 { XCTAssertEqual(a1[b], b1[b], "beat \(b): the delayed lane still hears the pool as it was a bar ago — unmoved") }
        for b in 13..<20 { XCTAssertEqual(a1[b], b1[b] + 2, "beat \(b): …and moved from the bar it was pressed in") }
    }
    func testAPoolMovedByTIsAChangedPoolToAFrozenLane() {
        // POOL HOLD (FREEZE, landed on main alongside this ferry): a pool moved by the root transpose is a changed pool like a chord change (§2.9) — the live lane follows at once, a lane frozen for one bar keeps what it took until its next take
        var frozen = EuclidLine(target: 0, pulses: 4, steps: 4)
        frozen.gate = 0.5; frozen.velocityAbsolute = 90; frozen.rate = .r1_4; frozen.useRiff = true; frozen.riffOn = true; frozen.sourceMode = .midi; frozen.notesOn = true; frozen.litNotes = 0
        frozen.poolHold = 1
        let st = state(plan(chords: true, mode: .root), extra: [frozen])
        let base = Rig(st); base.run(to: 24.5)
        let r = Rig(st); r.run(to: 8.5); r.press([50]); r.run(to: 24.5)
        let b0 = base.notes(cable: 1, beats: 24), b1 = base.notes(cable: 2, beats: 24), a0 = r.notes(cable: 1, beats: 24), a1 = r.notes(cable: 2, beats: 24)
        XCTAssertFalse(b1.contains(-1))
        for b in 9..<24 { XCTAssertEqual(a0[b], b0[b] + 2, "the live lane follows at once (beat \(b))") }
        XCTAssertEqual(a1[9], b1[9], "the frozen lane has not taken the moved pool yet")
        let diffs = (9..<24).map { a1[$0] - b1[$0] }
        XCTAssertTrue(diffs.allSatisfy { $0 == 0 || $0 == 2 }, "a frozen lane plays the old pool or the moved one, never anything else: \(diffs)")
        XCTAssertEqual(diffs.last, 2, "…and has taken the moved pool by the end")
        XCTAssertEqual(diffs, diffs.sorted(), "…once: it does not slip back")
    }
    func testTheHistoryRecordsAChangeOfTAsAChangeOfThePool() {
        var h = EuclideousCanonHistory()
        let layer: [(note: Int, vel: UInt8)] = [(50, 100)], none = [Int]()
        h.record(at: 0, midi: layer[...], midiPlaying: true, pick: none[...], keyRoot: 0, keyMask: 0xAB5, rootT: 2)
        h.record(at: 1, midi: layer[...], midiPlaying: true, pick: none[...], keyRoot: 0, keyMask: 0xAB5, rootT: 2)
        XCTAssertEqual(h.count, 1, "an identical window records nothing")
        h.record(at: 2, midi: layer[...], midiPlaying: true, pick: none[...], keyRoot: 0, keyMask: 0xAB5, rootT: 5)
        XCTAssertEqual(h.count, 2, "only t changed — still a new entry")
        XCTAssertEqual(h.rootTranspose(0), 2); XCTAssertEqual(h.rootTranspose(1), 5)
        h.record(at: 3, midi: layer[...], midiPlaying: true, pick: none[...], keyRoot: 0, keyMask: 0xAB5)   // the default: no ROOT
        XCTAssertEqual(h.count, 3); XCTAssertEqual(h.rootTranspose(2), 0)
    }

    // The survivors of the 2026-11-01 mutation review.

    func testADelayedLaneFoldsAtReadTimeUnderIgnoreAndNotUnderKeep() {
        var delayed = EuclidLine(target: 0, pulses: 4, steps: 4)
        delayed.gate = 0.5; delayed.velocityAbsolute = 90; delayed.rate = .r1_4; delayed.useRiff = true; delayed.riffOn = true; delayed.sourceMode = .midi; delayed.notesOn = true; delayed.litNotes = 0
        delayed.chordDelay = 1
        for (octaves, want) in [(MidiOctaves.ignore, 52), (.keep, 64)] {   // E4 G4 C5 held from beat 0.5: E3 folded, E4 kept
            let r = Rig(state(plan(octaves: octaves), extra: [delayed], canonUnit: .bars)); r.run(to: 0.5); r.press([64, 67, 72]); r.run(to: 12.5)
            let live = r.notes(cable: 1, beats: 12), late = r.notes(cable: 2, beats: 12)
            for b in 6..<12 { XCTAssertEqual(live[b], want, "\(octaves) live lane, beat \(b)"); XCTAssertEqual(late[b], want, "\(octaves) delayed lane, beat \(b): the history is raw, the lane folds at read time") }
        }
    }
    func testASceneFlushClearsTheLatch() {
        let r = Rig(rootState()); r.run(to: 0.5); r.press([50]); r.run(to: 2.5); r.release([50]); r.run(to: 3.5)
        XCTAssertEqual(r.status.rootTranspose, 2)
        r.flush()
        XCTAssertEqual(r.status.rootTranspose, 0, "a session / preset load starts at 0 (§1.4)"); XCTAssertEqual(r.status.rootNote, -1)
        r.run(to: r.beat + 1); XCTAssertEqual(r.status.rootTranspose, 0)
    }
    func testThePoolBlocksSourceTagsSurviveTheMove() {
        let base = Rig(rootState()); base.run(to: 2.5)
        let r = Rig(rootState()); r.run(to: 0.5); r.press([50]); r.run(to: 2.5)
        XCTAssertEqual(r.poolNotes, base.poolNotes.map { $0 + 2 })
        XCTAssertEqual(r.status.poolSources, base.status.poolSources, "CHORDS notes stay tagged CHORDS and KEY notes KEY once they are moved")
        XCTAssertTrue(r.status.poolSources.contains(1) && r.status.poolSources.contains(3))
        XCTAssertFalse(r.status.poolSources.contains(0), "ROOT admits no played note: nothing is tagged MIDI")
    }
    func testTheHoldPreviewShowsThePoolAsRootMovesIt() {
        let p = plan(chords: true, key: true, mode: .root)
        let a = euclideousColumnPreviewPool(midiNotes: [], chordTones: [48, 52, 55], pickNotes: [], keyTones: [48, 50, 52, 53, 55, 57, 59], midiPlaying: false, plan: p)
        let b = euclideousColumnPreviewPool(midiNotes: [], chordTones: [48, 52, 55], pickNotes: [], keyTones: [48, 50, 52, 53, 55, 57, 59], midiPlaying: false, plan: p, rootTranspose: 2)
        XCTAssertEqual(b.notes, a.notes.map { $0 + 2 }); XCTAssertEqual(b.sources, a.sources)
        XCTAssertTrue(a.sources.contains(1) && a.sources.contains(3))
    }
    func testChordsPlayThroughTheReleaseGraceUnderRoot() {
        // ROOT never steps CHORDS aside, not even in the 50 ms after the last key goes up: a hit ~30 ms after the release still sounds
        let r = Rig(state(plan(chords: true, mode: .root)))
        r.run(to: 0.5); r.press([50]); r.run(to: 5.94); r.release([50]); r.run(to: 6.5)
        let hit = r.out.ons.filter { $0.cable == 1 && abs(Double($0.sample) / 24_000.0 - 6.0) < 0.05 }
        XCTAssertEqual(hit.count, 1, "the hit at beat 6 sounds")
        // …ON the beat: if the row were skipped through the grace the engine would strike it a window late (6.02), not drop it
        XCTAssertEqual(Double(hit.first?.sample ?? 0) / 24_000.0, 6.0, accuracy: 0.002, "on the beat, not a window late")
    }
    func testReplaceKeepsChordsAsideThroughTheReleaseGraceAndThenReturns() {
        let r = Rig(state(plan(chords: true, key: true, mode: .replace)))
        r.run(to: 0.5); r.press([60]); r.run(to: 4.5)
        XCTAssertEqual(r.poolNotes, [48])
        let t0 = r.beat; r.release([60]); r.run(to: t0 + 0.04)    // two 10 ms windows after the release: still inside RELEASE GRACE
        XCTAssertEqual(r.poolNotes, [], "CHORDS and KEY are still aside 20 ms after the release")
        r.run(to: t0 + 0.2)                                       // 100 ms after
        XCTAssertGreaterThan(r.poolNotes.count, 1, "…and back once the grace has passed")
    }
    func testReleasingTheLowestOfSeveralNotesMovesTTowardTheNextLowest() {
        let r = Rig(rootState()); r.run(to: 0.5); r.press([50, 55]); r.run(to: 2.5)
        XCTAssertEqual(r.status.rootTranspose, 2); XCTAssertEqual(r.status.rootNote, 50)
        r.release([50]); r.run(to: 3.5)
        XCTAssertEqual(r.status.rootTranspose, 7, "G3 is now the lowest held note"); XCTAssertEqual(r.status.rootNote, 55)
    }
    func testTheSourceLightsUnderRoot() {
        let on = plan(chords: true, mode: .root), off = plan(midi: false, chords: true, mode: .root)
        func lights(_ p: SourcePlan, playing: Bool) -> EuclideousSourceLight { euclideousSourceStatuses(plan: p, midiPlaying: playing, chordsLit: true, pickLit: false, keyLit: false).midi }
        XCTAssertEqual(lights(on, playing: true), .playing); XCTAssertEqual(lights(on, playing: false), .waiting); XCTAssertEqual(lights(off, playing: true), .off)
    }

    // MARK: downstream (§2.6)

    func testEveryReaderOfThePoolSeesTheMovedPool() {
        // lane 1 plays rank 1; lane 2 is a unison SHADOW of it (cable 2); both read the moved pool.
        var shadow = EuclidLine(target: 0, pulses: 4, steps: 4)
        shadow.gate = 0.5; shadow.velocityAbsolute = 90; shadow.rate = .r1_4; shadow.useRiff = true; shadow.riffOn = true; shadow.sourceMode = .midi; shadow.notesOn = true; shadow.litNotes = 0
        shadow.setAnswerRhythm(.copy); shadow.listenSource = 0; shadow.setAnswerPitch(.shadow); shadow.listenInterval = 0; shadow.listenOctave = 0
        let st = state(plan(chords: true, mode: .root), extra: [shadow])
        let base = Rig(st); base.run(to: 8.5)
        let r = Rig(st); r.run(to: 0.5); r.press([50]); r.run(to: 8.5)
        let a0 = base.notes(cable: 1, beats: 8), a1 = r.notes(cable: 1, beats: 8), s1 = r.notes(cable: 2, beats: 8)
        XCTAssertFalse(a0.contains(-1))
        for b in 1..<8 { XCTAssertEqual(a1[b], a0[b] + 2, "the riff reads the moved pool (beat \(b))") }
        for b in 1..<8 { XCTAssertEqual(s1[b], a1[b], "a unison SHADOW follower doubles the moved note (beat \(b))") }
    }
    func testAnOutTransposeStepsThroughTheMovedPool() {
        // the part's out-transpose is a scale step of the KEY pill (unchanged): +1 step in C major on the moved pool
        let doc = state(plan(chords: true, mode: .root))
        let key = euclideousKeyPitchClassMask(root: doc.euclideousKeyRootResolved, intervals: doc.euclideousKeyTypeResolved.intervals)
        let st = state(plan(chords: true, mode: .root), lanePatch: { $0.riffOutTranspose = 1 })
        let plain = state(plan(chords: true, mode: .root))
        let base = Rig(plain); base.run(to: 8.5)
        let r = Rig(st); r.run(to: 0.5); r.press([50]); r.run(to: 8.5)
        let a0 = base.notes(cable: 1, beats: 8), a1 = r.notes(cable: 1, beats: 8)
        for b in 1..<8 { XCTAssertEqual(a1[b], euclideousScaleStepMove(note: a0[b] + 2, steps: 1, pcMask: key), "beat \(b)") }
    }
    func testANoteSoundingAcrossAFoldOrAChangeOfTEndsAtItsStartingPitch() {
        // a long gate crosses the mode / octaves / t changes; every note-on must be closed by a note-off of the SAME pitch
        func balanced(_ out: RigEmitter) -> Bool {
            var count: [Int: Int] = [:]
            for e in out.ons { count[Int(e.cable) * 256 + Int(e.note), default: 0] += 1 }
            for e in out.offs { count[Int(e.cable) * 256 + Int(e.note), default: 0] -= 1 }
            return count.values.allSatisfy { $0 == 0 }
        }
        let long: (inout EuclidLine) -> Void = { $0.gate = 0.95; $0.rate = .r1_4 }
        let r = Rig(state(plan(chords: true, key: true), lanePatch: long))
        r.run(to: 0.5); r.press([64, 67, 72]); r.run(to: 2.2)
        r.swap(state(plan(chords: true, key: true, octaves: .keep), lanePatch: long)); r.run(to: 4.2)      // OCTAVES change mid-note
        r.swap(state(plan(chords: true, key: true, mode: .root), lanePatch: long)); r.run(to: 6.2)         // mode change mid-note (t becomes +16)
        r.release([64, 67, 72]); r.press([55]); r.run(to: 8.2)                                              // t changes mid-note
        r.stop()
        XCTAssertFalse(r.out.ons.isEmpty)
        XCTAssertTrue(balanced(r.out), "every note ends at the pitch it started on")
    }

    // MARK: geometry (§3.1, §4.5)

    func testTheThreeSegmentModeAndTheMidiRowAtEveryLayout() {
        for cw in [CGFloat(1158), 868, 600, 343] {
            let L = euclideousSourcesPanelLayout(containerW: cw)
            XCTAssertEqual(L.modeAddW, 37); XCTAssertEqual(L.modeReplaceW, 60); XCTAssertEqual(L.modeRootW, 43, "ROOT = 4 chars × 5.76 + 20")
            XCTAssertEqual(L.modeW, 148, "the container widens by the ROOT segment and its 2 pt gap (45)")
            XCTAssertEqual(L.contentMidiW, L.contentW - 148 - 8)
            XCTAssertEqual(L.midiChipRoom, max(0, L.contentMidiW - 36), "CONTENT less 10 + 10 padding and the chevron with its sp6")
        }
        // the panel is 448 wide at 1158, 868 and 600: CONTENT 136, 100 pt for chips
        for cw in [CGFloat(1158), 868, 600] {
            let L = euclideousSourcesPanelLayout(containerW: cw)
            XCTAssertEqual(L.contentW, 292); XCTAssertEqual(L.contentMidiW, 136); XCTAssertEqual(L.midiChipRoom, 100)
        }
        // at 343 the MIDI row's CONTENT is 31 pt: no room for a chip (nor three), only the chevron
        let n = euclideousSourcesPanelLayout(containerW: 343)
        XCTAssertEqual(n.contentW, 187); XCTAssertEqual(n.contentMidiW, 31); XCTAssertEqual(n.midiChipRoom, 0)
    }
    func testTheMidiChipsFitTheRoomTheyAreGiven() {
        XCTAssertEqual(euclideousMidiChipFit(room: 100, count: 0).shown, 0)
        XCTAssertTrue(euclideousMidiChipFit(room: 100, count: 3) == (3, false), "E G C fit the 100 pt at the 448 pt panel")
        XCTAssertTrue(euclideousMidiChipFit(room: 100, count: 4) == (2, true), "a 4th note: two chips and a +n slot")
        XCTAssertTrue(euclideousMidiChipFit(room: 40, count: 2) == (1, false), "room for one chip: that chip alone")
        XCTAssertTrue(euclideousMidiChipFit(room: 29, count: 3) == (0, false), "less than a chip: none")
        XCTAssertTrue(euclideousMidiChipFit(room: 0, count: 3) == (0, false), "the 343 layout")
        XCTAssertEqual(euclideousMidiChipW, 30)
    }
    func testThePanelHeightWithTheMidiEditorOpen() {
        for cw in [CGFloat(1158), 868, 600, 343] {
            let none = euclideousSourcesPanelLayout(containerW: cw), midi = euclideousSourcesPanelLayout(containerW: cw, editor: .midi)
            let pick = euclideousSourcesPanelLayout(containerW: cw, editor: .pick), key = euclideousSourcesPanelLayout(containerW: cw, editor: .key)
            XCTAssertEqual(none.sourcesBlockH, 204); XCTAssertEqual(none.contentH, 312)
            XCTAssertEqual(midi.midiEditorH, 40)
            XCTAssertEqual(midi.sourcesBlockH, 248, "204 + the editor's sp4 slot + 40"); XCTAssertEqual(midi.contentH, 356)
            XCTAssertEqual(pick.sourcesBlockH, 268, "(+4 for the editor slot the layout used to leave out)")
            XCTAssertLessThan(midi.sourcesBlockH, pick.sourcesBlockH); XCTAssertLessThan(pick.sourcesBlockH, key.sourcesBlockH)
        }
    }

    // MARK: undo (§1.5)

    private func fourfoldSource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()   // …/Fourfold
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    func testAnOctavesChangeAndAModeChangeToRootAreOneUndoStepEachAndTheEditorIsNone() throws {
        // the plan travels whole in the undo snapshot, so each of these is a different snapshot …
        let a = plan()
        var o = a; o.midiOctaves = .keep; XCTAssertNotEqual(a, o)
        var r = a; r.midiMode = .root; XCTAssertNotEqual(a, r)
        var b = a; b.midiMode = .add; XCTAssertEqual(a, b, "a repeated tap on the same MODE value changes nothing in the snapshot")
        // … written through the one plan funnel, which records exactly one step per write …
        let funnel = try fourfoldSource("Shared/FourfoldRootView.swift")
        let from = funnel.range(of: "onSetSourcePlan:")!, to = funnel.range(of: "onSetNoteSource:", range: from.upperBound..<funnel.endIndex)!
        let tail = String(funnel[from.lowerBound..<to.lowerBound])
        XCTAssertEqual(tail.components(separatedBy: "euclideousRecordUndo(").count - 1, 1, "the plan funnel records one undo step per write")
        // … the OCTAVES segments write only a changed value, and opening / closing the editor writes nothing
        let page = try fourfoldSource("UI/EuclideousPage.swift")
        XCTAssertTrue(page.contains("if sourcePlan.midiOctavesR != value { writeSourcePlan { $0.midiOctaves = value } }"))
        XCTAssertTrue(page.contains(".onTapGesture { sourcesEditor = open ? .none : .midi }"), "the content button only toggles the (unsaved) editor state")
    }

    // MARK: the status (§2.8)

    func testStatusLightsUnderRoot() {
        let r = Rig(rootState()); r.run(to: 1.5)
        XCTAssertEqual(r.status.rootNote, -1); XCTAssertFalse(r.status.midiPlaying)
        r.press([50]); r.run(to: 2.5)
        XCTAssertTrue(r.status.midiPlaying); XCTAssertEqual(r.status.midiAdded, 0)
        let lights = euclideousSourceStatuses(plan: plan(chords: true, key: true, mode: .root), midiPlaying: r.status.midiPlaying,
                                              chordsLit: r.status.chordsLit, pickLit: r.status.pickLit, keyLit: r.status.keyLit)
        XCTAssertEqual(lights.midi, .playing)
    }
}
