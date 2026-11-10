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

    // 9b — the load-bearer: stackCellNote == the note the Router's NOTES layer actually emits, for 8 ranks × OCT −2…+2 (and the riff OCT / TRANS don't move it).
    func testStackCellNoteEqualsTheEngineEmittedNote() {
        let held: [UInt8] = [60, 64, 67]
        let p = pool(held)
        for oct in -2...2 {
            var l = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: false, sourceMode: .midi)
            l.notesOn = true; l.litNotes = 0xFF; l.notesPlayAs = .chord; l.notesWhen = 0b11; l.notesGate = 0.5
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
