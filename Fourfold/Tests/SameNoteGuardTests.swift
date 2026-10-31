//  SameNoteGuardTests.swift — the 2026-10-31 same-note gap guard: a riff note whose next hit repeats the same pitch is
//  shortened (adaptively, ~1.5 render buffers) so a host delivering MIDI at buffer granularity can't merge the off with
//  the identical next on. Shorten-only → never a stuck note. Arch riff [3,5,4,3,2,1,1,2] has one adjacent C-C pair.

import XCTest

private final class DurEmitter: MIDIEmitter {
    struct Ev { let seq: Int; let sample: Int64; let on: Bool; let note: UInt8; let cable: UInt8 }
    var evs: [Ev] = []; private var seq = 0
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0, on = st == 0x90 && b2 > 0, off = st == 0x80 || (st == 0x90 && b2 == 0)
        if on || off { evs.append(Ev(seq: seq, sample: sampleTime, on: on, note: b1, cable: cable)); seq += 1 }
    }
}

final class SameNoteGuardTests: XCTestCase {

    private func doc(guardOn: Bool) -> PluginState {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        var lines = (0..<4).map { _ -> EuclidLine in var l = EuclidLine(); l.pulses = 0; l.riffOn = false; l.useRiff = false; return l }
        lines[0].pulses = 8; lines[0].steps = 8; lines[0].rate = .r1_8; lines[0].direction = .fwd
        lines[0].riffOn = true; lines[0].useRiff = true; lines[0].gate = 0.9
        st.euclideousLines = lines
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: [3, 5, 4, 3, 2, 1, 1, 2])
        st.euclideousSameNoteGuard = guardOn ? nil : false   // nil ⇒ default ON
        var plan = st.sourcePlanResolved
        plan.midiOn = false; plan.chordsOn = true; plan.keyOn = false; plan.pickOn = false
        st.euclideousSourcePlan = plan
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .naturalMinor
        var cfg = MachineParams(); cfg.chordsSteps = 1; cfg.chordsDegrees = [0]; cfg.chordsRate = .r1_1
        st.setEuclideousChordSet(st.activeChordSetResolved, cfg)
        let ls = st.euclideousLinesResolved; st.euclideousLines = ls
        var sc = FourfoldCompose.scene(FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                      activeRiff: st.activeRiffResolved, soloMask: st.euclideousSoloMaskResolved,
                                      locks: st.euclideousLocksResolved, lockRevs: 0))
        sc.swing = 50; st.scenes = [sc]
        return st
    }

    /// (durations in ticks on cable 0, notes still open at the end)
    private func notes(guardOn: Bool, frames: UInt32) -> (durs: [Double], stuck: Int) {
        let tempo = 115.0, sr = 48000.0
        let box = SnapshotBuilder.build(from: doc(guardOn: guardOn))
        let pool = NotePool(); let router = Router(); let e = DurEmitter(); var diag = KernelDiag()
        var beat = 0.0, ts = 0.0
        let windows = Int((6.0 * 4.0 * 60.0 / tempo * sr / Double(frames)).rounded(.up))
        for _ in 0..<windows {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += Double(frames) * tempo / 60.0 / sr; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        func tick(_ s: Int64) -> Double { Double(s) * tempo * 480.0 / (60.0 * sr) }
        var open: [UInt16: Int64] = [:]; var durs: [Double] = []
        for ev in e.evs.filter({ $0.cable == 0 }).sorted(by: { $0.seq < $1.seq }) {
            let k = UInt16(ev.note)
            if ev.on { open[k] = ev.sample } else if let s = open[k] { durs.append(tick(ev.sample) - tick(s)); open[k] = nil }
        }
        // drop the final stop-flush off (closed at renderSampleImmediate, so its paired duration is a harness artifact, not a real note length)
        return (durs.filter { $0 > 0 && $0 < 2000 }, open.count)
    }

    func testPureGapHelper() {
        // ~1.5 render windows, capped at half the gap; 30 ms fallback; 0 when inputs invalid.
        XCTAssertEqual(euclideousSameNoteGuardGapBeats(windowBeats: 0.08, nextHitGapBeats: 0.5, tempo: 115), 0.12, accuracy: 1e-9)
        XCTAssertEqual(euclideousSameNoteGuardGapBeats(windowBeats: 0.5, nextHitGapBeats: 0.5, tempo: 115), 0.25, accuracy: 1e-9)   // capped at half
        XCTAssertEqual(euclideousSameNoteGuardGapBeats(windowBeats: 0, nextHitGapBeats: 0.5, tempo: 120), 0.060, accuracy: 1e-9)    // fallback 30 ms @120 = 0.06 beat
        XCTAssertEqual(euclideousSameNoteGuardGapBeats(windowBeats: 0.08, nextHitGapBeats: 0, tempo: 115), 0)
    }

    func testGuardShortensOnlyTheFirstOfAnAdjacentPair_largeBuffer() {
        let on = notes(guardOn: true, frames: 2048)
        let off = notes(guardOn: false, frames: 2048)
        XCTAssertEqual(on.stuck, 0, "guard on must never strand a note")
        XCTAssertEqual(off.stuck, 0)
        // guard OFF: every note full (gate 0.9 of a 1/8 = 216 ticks)
        XCTAssertTrue(off.durs.allSatisfy { abs($0 - 216) < 2 }, "guard off: all notes full, got \(Set(off.durs.map { Int($0.rounded()) }).sorted())")
        // guard ON: exactly the first-of-pair C per bar is shortened; everything else stays 216.
        let shortened = on.durs.filter { $0 < 200 }
        let full = on.durs.filter { $0 >= 200 }
        XCTAssertFalse(shortened.isEmpty, "guard on, large buffer: the adjacent-C note must be shortened")
        XCTAssertTrue(full.allSatisfy { abs($0 - 216) < 2 }, "guard on: non-repeat notes untouched")
        // one shortened note per 8-note bar (~6 bars)
        XCTAssertEqual(Double(shortened.count), Double(on.durs.count) / 8.0, accuracy: 1.5, "about one shortened note per bar")
        // shortened note still musical (≥ ~40% of the step) and shorter than full
        XCTAssertTrue(shortened.allSatisfy { $0 > 90 && $0 < 200 }, "shortened to a musical length, got \(shortened.map { Int($0.rounded()) })")
    }

    func testTypicalBufferDoesNotShorten() {
        // At 512 frames the existing gate-0.9 gap already exceeds ~1.5 buffers, so the guard binds on nothing.
        let on = notes(guardOn: true, frames: 512)
        XCTAssertEqual(on.stuck, 0)
        XCTAssertTrue(on.durs.allSatisfy { abs($0 - 216) < 2 }, "small buffer: nothing to shorten, got \(Set(on.durs.map { Int($0.rounded()) }).sorted())")
    }
}
