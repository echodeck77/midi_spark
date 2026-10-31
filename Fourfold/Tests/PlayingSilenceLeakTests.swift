//  PlayingSilenceLeakTests.swift — §a8b regression (Paul 2026-10-31): the Kernel's PLAYING silence-leak watchdog used to
//  treat an Euclideous row that generates from KEY/CHORDS/PICK (with an EMPTY live MIDI pool) as a stuck note and
//  force-closed every voice via allNotesOff once per debounce (~2 bars), cutting real notes (the reel "long notes").
//  Euclideous is a GENERATOR, not only a live-input processor. The Router now publishes `euclideousSourcePresent` — the
//  row's own per-window source guard — which the Kernel folds into its empty-input clock so the net never false-fires.
//  Kernel.swift is out of the macOS test target, so this locks the SIGNAL the net reads; the end-to-end heal-count=0 is
//  proven by the sim (bugtape repro) and is device/sim-owed. See Docs/euclideous-device-verification-debt.md.

import XCTest

final class PlayingSilenceLeakTests: XCTestCase {

    /// Lane A running 8/8 1/8, riff on, the four sources set by the args; everything else default.
    private func doc(midi: Bool, chords: Bool, key: Bool, pick: Bool) -> PluginState {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        var lines = (0..<4).map { _ -> EuclidLine in var l = EuclidLine(); l.pulses = 0; l.riffOn = false; l.useRiff = false; return l }
        lines[0].pulses = 8; lines[0].steps = 8; lines[0].rate = .r1_8; lines[0].direction = .fwd
        lines[0].riffOn = true; lines[0].useRiff = true; lines[0].gate = 0.9
        st.euclideousLines = lines
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 5, 4, 3, 2, 1])   // Paul's default arch (C at both ends)
        var plan = st.sourcePlanResolved
        plan.midiOn = midi; plan.chordsOn = chords; plan.keyOn = key; plan.pickOn = pick
        if pick { plan.pickNotes = [60, 63, 67] }
        st.euclideousSourcePlan = plan
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .naturalMinor
        if chords {
            var cfg = MachineParams(); cfg.chordsSteps = 1; cfg.chordsDegrees = [0]; cfg.chordsRate = .r1_1
            st.setEuclideousChordSet(st.activeChordSetResolved, cfg)
        }
        let ls = st.euclideousLinesResolved; st.euclideousLines = ls
        var sc = FourfoldCompose.scene(FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                      activeRiff: st.activeRiffResolved, soloMask: st.euclideousSoloMaskResolved,
                                      locks: st.euclideousLocksResolved, lockRevs: 0))
        sc.swing = 50; st.scenes = [sc]
        return st
    }

    /// Run a few playing windows (empty live pool) and report the Router's final `euclideousSourcePresent`.
    private func sourcePresent(midi: Bool, chords: Bool, key: Bool, pick: Bool) -> Bool {
        let tempo = 120.0, sr = 48000.0, frames: UInt32 = 480
        let box = SnapshotBuilder.build(from: doc(midi: midi, chords: chords, key: key, pick: pick))
        let pool = NotePool()   // NOTHING held — the whole point
        let router = Router(); var diag = KernelDiag()
        final class Sink: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Sink()
        var beat = 0.0, ts = 0.0
        for _ in 0..<32 {   // ~2.5 bars, well past any single window
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
            beat += Double(frames) * tempo / 60.0 / sr; ts += Double(frames)
        }
        return router.euclideousSourcePresent
    }

    func testGenerativeSourcesCountAsPresentWithEmptyLivePool() {
        // KEY / CHORDS / PICK all generate algorithmically — they drive voices with NOTHING held, so the leak net must
        // not treat them as stuck. Each must report a live source present.
        XCTAssertTrue(sourcePresent(midi: false, chords: false, key: true,  pick: false), "KEY source with empty pool is a live source")
        XCTAssertTrue(sourcePresent(midi: false, chords: true,  key: false, pick: false), "CHORDS source with empty pool is a live source")
        XCTAssertTrue(sourcePresent(midi: false, chords: false, key: false, pick: true),  "PICK source with empty pool is a live source")
    }

    func testMidiOnlyWithNothingHeldHasNoSource() {
        // MIDI-only with nothing held genuinely has no source — the net's premise holds, so the signal is false (and a
        // truly stuck voice would still be caught). This is the case the fix must NOT over-suppress.
        XCTAssertFalse(sourcePresent(midi: true, chords: false, key: false, pick: false), "MIDI-only, nothing held ⇒ no live source")
    }
}
