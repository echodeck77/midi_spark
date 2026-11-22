//  GridChanceRouterTests.swift — GRID CHANCE ferry (2026-11-22): the ENGINE behaviour (§2), on the REAL Fourfold
//  euclideous-row path (useRiff + riffOn, the cell at Snap.euclideousRow — NOT the legacy 8x8 useRiff fork). Proves a
//  chance-silenced note never sounds while the walk / stack sequence advances unchanged (§2.5). The pure decision is in
//  GridChanceTests; the golden harness proves the default (all 100) is byte-identical across every preset.

import XCTest

private final class GCEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2))
    }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    /// A lane's note-ons on its own output (cable lane+1), in time order.
    func laneOnNotes(_ lane: Int) -> [Int] { ons.filter { Int($0.cable) == lane + 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) } }
}

final class GridChanceRouterTests: XCTestCase {

    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]   // rank r → pool[r-1]

    private func riffLane(pulses: Int = 8, steps: Int = 8) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps, velocityAbsolute: 100, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = 0.5
        return l
    }
    private func stackLane(litNotes: UInt8) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: true, riffOn: false, sourceMode: .midi)
        l.gate = 0.5; l.notesOn = true; l.setLitOrder(.derived(litNotes: litNotes, top: false, top2: false)); l.notesGate = 0.3
        return l
    }

    /// A euclideous-row document with the given lanes, an 8-rank riff and page-level grid chance.
    private func state(_ lines: [EuclidLine], gridChance: EuclideousGridChance?) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousGridChance = gridChance
        return st
    }

    private func held() -> NotePool { let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }; return p }

    private func run(_ st: PluginState, beats: Double) -> GCEmitter {
        var d = st; var pl = d.sourcePlanResolved; pl.midiOctaves = .keep; d.euclideousSourcePlan = pl   // hold the chord where it is played (MIDI OCTAVES KEEP)
        let box = SnapshotBuilder.build(from: d)
        let e = GCEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let p = held()
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    // §2.1 / §10.2 — riff RANK silence; the walk reads the same columns (the surviving note sequence is the default minus rank 8).
    func testRiffRank8SilencedWalkUnchanged() {
        let base = run(state([riffLane()], gridChance: nil), beats: 24).laneOnNotes(0)
        var gc = EuclideousGridChance(); gc.riffRank[7] = 0   // rank 8 → pool[7] = 60
        let thin = run(state([riffLane()], gridChance: gc), beats: 24).laneOnNotes(0)
        XCTAssertTrue(base.contains(60), "sanity: rank 8 (60) appears in the default run")
        XCTAssertFalse(thin.contains(60), "rank 8 must never sound at chance 0")
        XCTAssertEqual(thin, base.filter { $0 != 60 }, "the surviving notes are the default sequence with rank 8 removed — the walk did not shift")
    }

    // §2.1 / §10.3 — riff COLUMN silence; other columns sound, the walk unchanged.
    func testRiffColumn0SilencedWalkUnchanged() {
        let base = run(state([riffLane()], gridChance: nil), beats: 24).laneOnNotes(0)
        var gc = EuclideousGridChance(); gc.riffColumn[0] = 0   // position 0 → rank 1 → pool[0] = 48
        let thin = run(state([riffLane()], gridChance: gc), beats: 24).laneOnNotes(0)
        XCTAssertTrue(base.contains(48), "sanity: column 0 (48) appears in the default run")
        XCTAssertFalse(thin.contains(48), "column 0 must be silent")
        XCTAssertEqual(thin, base.filter { $0 != 48 }, "other columns unchanged — the walk did not shift")
    }

    // §2.2 / §10.4 — stack by RANK thins one voice; the other voices of each chord still play.
    func testStackRankPerVoice() {
        var gc = EuclideousGridChance(); gc.stackRank[2] = 0   // rank 3 → pool[2] = 52
        let thin = run(state([stackLane(litNotes: 0b0001_0101)], gridChance: gc), beats: 16).laneOnNotes(0)   // lit ranks 1, 3, 5
        XCTAssertFalse(thin.isEmpty)
        XCTAssertFalse(thin.contains(52), "stack rank 3 silenced")
        XCTAssertTrue(thin.contains(48) && thin.contains(55), "ranks 1 (48) and 5 (55) still play")
    }

    // §2.3 / §10.5 — stack by LANE silences the chosen lane's whole stack; another lane's stack sounds.
    func testStackLaneWholeHit() {
        var gc = EuclideousGridChance(); gc.stackLane[1] = 0   // lane 2 (index 1) silent
        let e = run(state([stackLane(litNotes: 0b0000_0101), stackLane(litNotes: 0b0000_0101)], gridChance: gc), beats: 16)
        XCTAssertTrue(e.laneOnNotes(1).isEmpty, "lane 2's whole stack is silenced")
        XCTAssertFalse(e.laneOnNotes(0).isEmpty, "lane 1's stack still sounds")
    }

    // §10.1 — an explicit all-100 grid chance is byte-for-byte the same stream as nil (no gate effect).
    func testAll100EqualsNil() {
        let a = run(state([riffLane(pulses: 5)], gridChance: nil), beats: 24).events
        let b = run(state([riffLane(pulses: 5)], gridChance: EuclideousGridChance()), beats: 24).events
        XCTAssertEqual(a, b, "all 100 must be byte-identical to nothing stored")
    }
}
