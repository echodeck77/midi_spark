//  StackGridLiveTests.swift — STACK GRID LIVE ferry (2026-11-10) §7.
//  The pure layer: true note names (the NOTES octave applied, via the engine's own riffResolve), which ranks sound (a per-frame query over the NoteRoll feed), each cell's look, and the shared riff-ghost rank.
//  Test 9 is the load-bearer: `euclideousStackCellNote` == the note the Router's NOTES layer actually emits, for 8 ranks × OCT −2…+2. The ring (test 8) is also fuzzed against the engine in LaneStripFuzzTests.

import XCTest

private final class SilentEmitter: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }

final class StackGridLiveTests: XCTestCase {

    // MARK: fixtures
    private func pool(_ notes: [UInt8]) -> EuclideousLanePoolNotes {
        var p = EuclideousLanePoolNotes(); p.notes = notes; p.count = notes.count
        let s = notes.sorted(); p.top = s.last ?? 0; p.top2 = s.count >= 2 ? s[s.count - 2] : 0
        return p
    }
    private func note(_ onBeat: Double, end: Double?, pitch: UInt8 = 60, outs: UInt8 = 1, rank: UInt8) -> NoteRollNote {
        NoteRollNote(onBeat: onBeat, endBeat: end, pitch: pitch, velocity: 100, outs: outs, rank: rank)
    }

    // 1 — held set: two note-ons on r3 then one note-off → r3 still sounding; the second note-off → gone. (The NoteRollModel's ingest IS the held set; the query reads it.)
    func testHeldSetKeepsARankLitUntilTheLastNoteOff() {
        var m = NoteRollModel()
        m.ingest([NoteRollRecord(onBeat: 0, length: .infinity, pitch: 60, velocity: 100, part: 1, flags: 0x20 | 1, rank: 3),
                  NoteRollRecord(onBeat: 1, length: .infinity, pitch: 62, velocity: 100, part: 1, flags: 0x20 | 1, rank: 3)])   // two overlapping notes on rank 3
        XCTAssertTrue(euclideousStackSounding(notesPart: m.parts[1], rank: 3, nowBeat: 2).sounding, "both held → rank 3 sounds")
        m.ingest([NoteRollRecord(onBeat: 0, length: 2, pitch: 60, velocity: 0, part: 1, flags: NoteRollRecord.endFlag | 1, rank: 3)])   // close the first (end beat 2)
        XCTAssertTrue(euclideousStackSounding(notesPart: m.parts[1], rank: 3, nowBeat: 2.5).sounding, "one still held → still sounds")
        m.ingest([NoteRollRecord(onBeat: 1, length: 2, pitch: 62, velocity: 0, part: 1, flags: NoteRollRecord.endFlag | 1, rank: 3)])   // close the second (end beat 3)
        XCTAssertFalse(euclideousStackSounding(notesPart: m.parts[1], rank: 3, nowBeat: 3.5).sounding, "both closed → rank 3 is silent")
    }

    // 2 — the gate: a note routed nowhere (outs 0) never lights the grid.
    func testANoteRoutedNowhereDoesNotLight() {
        let routed = [note(0, end: 4, outs: 1, rank: 2)], nowhere = [note(0, end: 4, outs: 0, rank: 2)]
        XCTAssertTrue(euclideousStackSounding(notesPart: routed, rank: 2, nowBeat: 1).sounding)
        XCTAssertFalse(euclideousStackSounding(notesPart: nowhere, rank: 2, nowBeat: 1).sounding, "outs 0 (routed nowhere / silenced) → not sounding")
    }

    // 3 — a CHORD on ranks 1,3,5: those three light (and carry a glow onset), the rest don't.
    func testAChordLightsItsThreeRanksEachWithAGlow() {
        let part = [note(0, end: 1, rank: 1), note(0, end: 1, rank: 3), note(0, end: 1, rank: 5)]
        for r in 1...8 {
            let s = euclideousStackSounding(notesPart: part, rank: r, nowBeat: 0.2)
            if [1, 3, 5].contains(r) { XCTAssertTrue(s.sounding, "rank \(r) sounds"); XCTAssertEqual(s.glowOnset, 0, "…and glows from its note-on") }
            else { XCTAssertFalse(s.sounding, "rank \(r) is silent"); XCTAssertNil(s.glowOnset) }
        }
    }

    // 4 — DRONE: one long held note on the lowest rank stays sounding across the whole gate.
    func testADroneStaysLitForItsWholeGate() {
        let part = [note(0, end: 8, rank: 1)]
        for b in stride(from: 0.0, through: 7.9, by: 1.0) { XCTAssertTrue(euclideousStackSounding(notesPart: part, rank: 1, nowBeat: b).sounding, "still sounding at beat \(b)") }
        XCTAssertFalse(euclideousStackSounding(notesPart: part, rank: 1, nowBeat: 8.1).sounding, "past its end")
    }

    // 5 — deselecting a sounding cell keeps it lit (the look is sounding, whatever the selection).
    func testDeselectingASoundingCellKeepsItLit() {
        let lit = euclideousStackCellLook(selected: false, sounding: true, glowAgeSeconds: nil, reduceMotion: false)
        XCTAssertEqual(lit.fillAlpha, 1, "a held note stays sounding after it is deselected (§2.3)")
        XCTAssertTrue(lit.labelInk)
    }

    // 6 — transport stop clears the model → nothing sounds.
    func testTransportStopClearsTheHeldSet() {
        var m = NoteRollModel(); m.ingest([NoteRollRecord(onBeat: 0, length: .infinity, pitch: 60, velocity: 100, part: 1, flags: 0x20 | 1, rank: 2)])
        XCTAssertTrue(euclideousStackSounding(notesPart: m.parts[1], rank: 2, nowBeat: 1).sounding)
        m.clear()
        XCTAssertFalse(euclideousStackSounding(notesPart: m.parts[1], rank: 2, nowBeat: 1).sounding, "a transport edge clears the feed → rest")
    }

    // 7 — only the NOTES part lights: a riff-part note on rank 4 is in a different part array and never reaches the grid.
    func testRiffPartNotesDoNotLight() {
        let riffPart = [note(0, end: 4, rank: 4)]
        // the grid queries the NOTES part only; the riff part's notes are simply never passed in
        XCTAssertFalse(euclideousStackSounding(notesPart: [], rank: 4, nowBeat: 1).sounding, "an empty notes part → rank 4 unlit even though the riff plays it")
        XCTAssertTrue(euclideousStackSounding(notesPart: riffPart, rank: 4, nowBeat: 1).sounding, "(control) the same notes, were they the NOTES part, would light")
    }

    // 8 (part) — the ghost rank is nil when nothing has landed (stopped / before the first hit); the running cases are fuzzed against the engine in LaneStripFuzzTests.
    func testGhostRankIsNilWhenStopped() {
        var l = EuclidLine(target: 0, pulses: 4, steps: 8, rate: .r1_8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.riffOnRest = .repeatLast
        guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { return XCTFail("no cfg") }
        XCTAssertNil(euclideousStripCurrentRank(cfg: cfg, landedTick: nil, passLapStartTick: 0, arrowStaysOnTiedNote: false, legs: []), "nothing landed (stopped) → no ghost")
    }

    // 10 — the looks: a selected cell at rest is a 50 % lane fill with a #F2F4F7 (non-ink) label; a sounding cell is 100 % with the ink label.
    func testRestAndSoundingLooks() {
        let rest = euclideousStackCellLook(selected: true, sounding: false, glowAgeSeconds: nil, reduceMotion: false)
        XCTAssertEqual(rest.fillAlpha, 0.5); XCTAssertFalse(rest.labelInk, "selected-at-rest: #F2F4F7 label")
        let sounding = euclideousStackCellLook(selected: true, sounding: true, glowAgeSeconds: nil, reduceMotion: false)
        XCTAssertEqual(sounding.fillAlpha, 1); XCTAssertTrue(sounding.labelInk, "sounding: today's on-cell ink label")
        let off = euclideousStackCellLook(selected: false, sounding: false, glowAgeSeconds: nil, reduceMotion: false)
        XCTAssertEqual(off.fillAlpha, 0, "an unselected rest cell draws the OFF look (fill 0)")
        // the glow envelope: full at the onset, gone by the fade; Reduce Motion is a step
        XCTAssertEqual(euclideousStackCellLook(selected: false, sounding: true, glowAgeSeconds: 0, reduceMotion: false).glowAlpha, 1, accuracy: 1e-9)
        XCTAssertEqual(euclideousStackCellLook(selected: false, sounding: true, glowAgeSeconds: EuclideousGlow.fadeSeconds + 0.01, reduceMotion: false).glowAlpha, 0, accuracy: 1e-9)
        XCTAssertEqual(euclideousStackCellLook(selected: false, sounding: true, glowAgeSeconds: EuclideousGlow.reduceMotionSeconds + 0.01, reduceMotion: true).glowAlpha, 0)
    }

    // 9a — names: a lane on NOTES OCT −1 shows each rank one octave below the same pool on OCT 0; the riff OCT is not an input.
    func testNamesFollowTheNotesOctave() {
        let p = pool([60, 64, 67])
        for r in 1...8 {
            let at0 = euclideousStackCellNote(row: .rank(r), pool: p, notesOct: 0)
            let atM1 = euclideousStackCellNote(row: .rank(r), pool: p, notesOct: -1)
            XCTAssertNotNil(at0); XCTAssertEqual(atM1, at0.map { $0 - 12 }, "rank \(r): OCT −1 is an octave below OCT 0")
        }
        // out of range → nil (the engine drops it; the cell shows "–")
        XCTAssertNil(euclideousStackCellNote(row: .rank(1), pool: pool([2]), notesOct: -2), "rank 1 at OCT −2 of a very low pool leaves 0…127 → dropped")
    }

    // MUTE notes-ghost prediction (2026-11-11): euclideousNotesHitPitches == the NOTES layer the Router actually emits, per hit, across PLAY AS modes × octaves.
    func testNotesHitPitchesEqualTheEngine() {
        let held: [UInt8] = [48, 50, 52, 53, 55, 57, 59]   // 7 received notes, so octave folds + TOP are exercised
        let pool = held.map { Int($0) }
        let riffRanks = [1, 2, 3, 4, 5, 6, 7, 8]            // the riff grid's ranks — all ≥ 1 ⇒ no rest hits, so WHEN(both) plays every hit
        for mode in [EuclidNotesPlayAs.chord, .cycle, .bounce, .build, .split, .reverse, .random, .alternate, .outline, .pairs, .drone] {
            for oct in [-1, 0, 1] {
                // the riff layer is OFF so the notes layer plays alone (no riff/notes same-pitch dedup) — this fuzzes euclideousNotesHitPitches in isolation; the dedup is handled + tested in muteGhosts separately
                var l = EuclidLine(target: 0, pulses: 5, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: true, riffOn: false, sourceMode: .midi)
                l.notesOn = true; l.litNotes = 0b1011_0110; l.notesPlayAs = mode; l.notesWhen = 0b11; l.notesGate = 0.4; l.octave = oct
                var c = Machine(machineID: "gold", type: .euclid)
                c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riffRanks)
                c.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
                var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
                var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
                st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
                let box = SnapshotBuilder.build(from: st)
                let router = Router(); var diag = KernelDiag(); let e = SilentEmitter()
                let np = NotePool(); for n in held { np.noteOn(n, velocity: 100, channel: 0) }
                let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
                let windowBeats = Double(frames) * tempo / 60.0 / sr
                var beat = 0.0, ts = 0.0, recs: [NoteRollRecord] = []
                while beat < 8.0 {
                    router.process(box: box, pool: np, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                    recs += router.rollRing.drain(); beat += windowBeats; ts += Double(frames)
                }
                guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { return XCTFail("no cfg") }
                // the notes layer strikes every picked pitch at the HIT onset (CHORD + single-note modes; ROLL/RUN would spread) — group the emitted notes-part records by onset
                let notesStarts = recs.filter { !$0.isEnd && $0.part == 1 && $0.onBeat < 7.0 }
                XCTAssertFalse(notesStarts.isEmpty, "\(mode) oct \(oct): the notes layer struck")
                let byBeat = Dictionary(grouping: notesStarts, by: { ($0.onBeat / cfg.sub).rounded() })
                for (_, group) in byBeat {
                    let tick = Int64((group[0].onBeat / cfg.sub).rounded())
                    let predicted = Set(euclideousNotesHitPitches(line: l, pool: pool, cfg: cfg, tick: tick, lane: 0, oct: max(-2, min(2, oct)), isRestHit: false, ranks: riffRanks))   // every riff rank ≥ 1 ⇒ no rest hit
                    XCTAssertEqual(predicted, Set(group.map { Int($0.pitch) }), "\(mode) oct \(oct) tick \(tick): the predicted notes-layer pitches match the engine")
                }
            }
        }
    }

    // MUTE ghost dedup (2026-11-11): euclideousGhostsForOutput splits a lane's prediction per output and drops a notes pitch the riff also plays on that output —
    // the engine's addPitch §2.5 rule (a notes pitch leaves only on outputs the riff does NOT reach / hold), restricted to one output.
    func testGhostsForOutputMatchTheEngineDedup() {
        // a struck hit: the riff plays 60 on outputs A+B, the notes play {60, 64} on outputs A+C
        let hit = EuclideousGhostHit(onset: 0, riffPitches: [60], riffLens: [0.4], riffBlind: false, riffBlindLen: 0,
                                     heldRiffPitch: nil, notesPitches: [60, 64], notesLen: 0.3)
        let plan = EuclideousLaneGhostPlan(lane: 0, riffOuts: 0b0011, notesOuts: 0b0101, hits: [hit])
        let a = euclideousGhostsForOutput(plan, output: 0)   // both parts reach A: riff 60, notes 64 (60 deduped — the riff plays it here)
        XCTAssertEqual(Set(a.filter { $0.riff }.compactMap { $0.pitch }), [60])
        XCTAssertEqual(Set(a.filter { !$0.riff }.compactMap { $0.pitch }), [64])
        let b = euclideousGhostsForOutput(plan, output: 1)   // riff only: riff 60, no notes
        XCTAssertEqual(Set(b.compactMap { $0.pitch }), [60]); XCTAssertTrue(b.allSatisfy { $0.riff })
        let cc = euclideousGhostsForOutput(plan, output: 2)  // notes only: both notes, no dedup (the riff does not reach C)
        XCTAssertEqual(Set(cc.compactMap { $0.pitch }), [60, 64]); XCTAssertTrue(cc.allSatisfy { !$0.riff })
        XCTAssertTrue(euclideousGhostsForOutput(plan, output: 3).isEmpty)   // neither part reaches D

        // a TIED rest: the riff HOLDS 62 (nothing struck), the notes play {62, 65} — 62 drops on an output the riff reaches (`heldByRiff`), no riff ghost
        let tied = EuclideousGhostHit(onset: 1, riffPitches: [], riffLens: [], riffBlind: false, riffBlindLen: 0,
                                      heldRiffPitch: 62, notesPitches: [62, 65], notesLen: 0.3)
        let tiedA = euclideousGhostsForOutput(EuclideousLaneGhostPlan(lane: 1, riffOuts: 0b0001, notesOuts: 0b0001, hits: [tied]), output: 0)
        XCTAssertEqual(Set(tiedA.compactMap { $0.pitch }), [65]); XCTAssertTrue(tiedA.allSatisfy { !$0.riff })

        // an empty-pool riff hit ⇒ ONE middle-line (nil-pitch) riff ghost at its own length
        let blind = EuclideousGhostHit(onset: 2, riffPitches: [], riffLens: [], riffBlind: true, riffBlindLen: 0.5,
                                       heldRiffPitch: nil, notesPitches: [], notesLen: 0)
        let bl = euclideousGhostsForOutput(EuclideousLaneGhostPlan(lane: 2, riffOuts: 0b0001, notesOuts: 0, hits: [blind]), output: 0)
        XCTAssertEqual(bl.count, 1); XCTAssertNil(bl[0].pitch); XCTAssertTrue(bl[0].riff); XCTAssertEqual(bl[0].length, 0.5)
    }

    // 9b — the load-bearer: stackCellNote == the note the Router's NOTES layer actually emits, for 8 ranks × OCT −2…+2 (and the riff OCT / TRANS don't move it).
    func testStackCellNoteEqualsTheEngineEmittedNote() {
        let held: [UInt8] = [60, 64, 67]
        let p = pool(held)
        for oct in -2...2 {
            var l = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: false, sourceMode: .midi)
            l.notesOn = true; l.litNotes = 0xFF; l.notesPlayAs = .chord; l.notesWhen = 0b11; l.notesGate = 0.5
            l.notesVoicesChain = [EuclideousVoicesChip(value: .all)]   // PLAY AS ROWS (2026-11-11): VOICES ALL strikes every lit rank a hit (the old CHORD), so all eight ranks are emitted for the per-rank prediction check
            l.octave = oct                 // the NOTES octave
            l.riffOctave = 1; l.melodyTranspose = 3   // the riff OCT + TRANS: must NOT move the notes-part pitch
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
            var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
            st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
            let box = SnapshotBuilder.build(from: st)
            let router = Router(); var diag = KernelDiag(); let e = SilentEmitter()
            let np = NotePool(); for n in held { np.noteOn(n, velocity: 100, channel: 0) }
            let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
            var ts = 0.0, recs: [NoteRollRecord] = []
            for _ in 0..<12 {
                router.process(box: box, pool: np, playing: true, beatPos: ts * tempo / 60.0 / sr, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
                recs += router.rollRing.drain(); ts += Double(frames)
            }
            let notesStarts = recs.filter { !$0.isEnd && $0.part == 1 && $0.rank >= 1 && $0.rank <= 8 }
            XCTAssertFalse(notesStarts.isEmpty, "OCT \(oct): the notes layer struck")
            for rec in notesStarts {
                XCTAssertEqual(Int(rec.pitch), euclideousStackCellNote(row: .rank(Int(rec.rank)), pool: p, notesOct: oct), "OCT \(oct), rank \(rec.rank): stackCellNote == the engine's emitted note")
            }
            XCTAssertEqual(Set(notesStarts.map { Int($0.rank) }), Set(1...8), "every lit rank struck (octave copies included)")
        }
    }
}
