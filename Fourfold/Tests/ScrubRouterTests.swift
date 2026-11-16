//  ScrubRouterTests.swift — Scrub ferry (2026-11-16) §11: the engine override through a real Router. A column/rank/stack
//  hold substitutes the note at every lane's hit; with no hold the path is today's (golden proves byte-identity separately).

import XCTest

private struct SEv: Equatable { let sample: Int64; let cable: UInt8; let note: UInt8; let on: Bool }
private final class STap: MIDIEmitter {
    private(set) var evs: [SEv] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        guard st == 0x90 || st == 0x80 else { return }
        evs.append(SEv(sample: sampleTime, cable: cable, note: b1, on: st == 0x90 && b2 > 0))
    }
    func ons(_ cable: UInt8) -> [SEv] { evs.filter { $0.cable == cable && $0.on } }
}

private let scrubPool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]   // rank 1…8

final class ScrubRouterTests: XCTestCase {

    private func line8(riffOnRest: EuclidRiffOnRest = .skip, oct: Int = 0, notes: Bool = false) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8)   // a hit every step
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.sourceMode = .midi; l.riffLength = 8
        l.useRiff = !notes; l.riffOn = !notes                 // riff tests: riff only; stack test: notes only
        l.notesOn = notes; l.litNotes = notes ? 0b1111_1111 : 0
        l.riffOnRest = riffOnRest
        l.riffOctave = oct == 0 ? nil : oct   // the RIFF octave (altRiffOct) — the notes octave is `octave`
        return l
    }
    private func box(_ lines: [EuclidLine], ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]) -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        return SnapshotBuilder.build(from: st)
    }
    /// Run `beats` of playing windows; `holds(beat)` → (riffColumn, riffRank, stackRank), 0 = none, read each window.
    private func play(_ box: SnapshotBox, beats: Double, pool: [UInt8] = scrubPool, frames: UInt32 = 2048, tempo: Double = 120,
                      holds: (Double) -> (Int, Int, Int) = { _ in (0, 0, 0) }) -> STap {
        let tap = STap(); let router = Router(); var diag = KernelDiag(); let sr = 48_000.0
        let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            let h = holds(beatNow())
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousRiffColumnHold: UInt8(h.0), euclideousRiffRankHold: UInt8(h.1), euclideousStackRankHold: UInt8(h.2), out: tap, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
        return tap
    }

    // §11.3 (adapted) — a column hold substitutes the held column's note on EVERY hit; with no hold, the walk's own columns.
    func testColumnHoldSubstitutesEveryHit() {
        let b = box([line8()])
        let plain = play(b, beats: 8).ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertEqual(Array(plain.prefix(8)), scrubPool, "no hold ⇒ rank k at hit k (ascending pool)")
        let held = play(b, beats: 8) { _ in (5, 0, 0) }.ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertEqual(Set(held.prefix(8)), [scrubPool[4]], "column 5 held ⇒ every hit plays rank 5")
    }

    // §3.5 slip — release returns to the natural note (the walk advanced underneath).
    func testColumnHoldReleaseReturnsNatural() {
        let b = box([line8()])
        let notes = play(b, beats: 7.5) { beat in beat < 3.5 ? (5, 0, 0) : (0, 0, 0) }.ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertEqual(notes.first, scrubPool[4], "first hit held ⇒ rank 5")
        XCTAssertTrue(notes.contains(scrubPool[6]), "after release the walk is at its natural position (rank 7 plays its own note) — slip")   // §3.5
        XCTAssertNotEqual(Set(notes), [scrubPool[4]], "not every hit is the held note — release returned to natural")
    }

    // §11.5 — a rank hold plays that rank on every hit, through each lane's own pool / OCT / FLIP.
    func testRankHoldThroughOwnPoolOctFlip() {
        let plain = play(box([line8()]), beats: 8) { _ in (0, 8, 0) }.ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertEqual(Set(plain.prefix(8)), [scrubPool[7]], "rank 8 held ⇒ pool rank 8 every hit")
        let octLow = play(box([line8(oct: -1)]), beats: 8) { _ in (0, 8, 0) }.ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertEqual(Set(octLow.prefix(8)), [scrubPool[7] - 12], "OCT −1 ⇒ an octave lower")
    }

    // §11.7 (adapted) — a stack rank hold makes the notes layer play only that one rank.
    func testStackHoldPlaysOneRank() {
        let b = box([line8(notes: true)])   // notes layer on, riff off ⇒ only the stack is on cable 1
        let notes = play(b, beats: 8) { _ in (0, 0, 3) }.ons(1).sorted { $0.sample < $1.sample }.map { $0.note }
        XCTAssertFalse(notes.isEmpty, "the stack sounds under a hold")
        XCTAssertEqual(Set(notes.prefix(8)), [scrubPool[2]], "stack rank 3 held ⇒ only pool rank 3")
    }
}
