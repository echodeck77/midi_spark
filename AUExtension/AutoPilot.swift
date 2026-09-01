#if DEBUG
import Foundation
import os

/// ON-DEVICE AUTO-RUN — a CALM self-player (Paul 2026-09-01). The instrument plays ITSELF so it can be left running on
/// the iPad to hear + soak for stability WITHOUT a controller. This is NOT a test and NOT ChaosDriver: ChaosDriver is an
/// adversarial control-surface FUZZER (it panics, mutes, type-swaps, revives); AUTO-RUN only HOLDS/RELEASES a musical
/// chord loop and drives the free-run clock so the current grid sounds while the host transport is stopped. It never
/// fuzzes controls, never edits the document, never panics — it just plays. `#if DEBUG` so it can't ship enabled.
///
/// Reuses ChaosDriver's proven seams: `chaosInjectMIDI` (the main-thread→render SPSC note queue) + `setFreeRunEnabled`
/// (the internal clock) + `kernelDiagnostics` (a light stuck-note oracle on screen). Deterministic — a fixed modal loop,
/// so successive runs are identical and a report is reproducible.
final class AutoPilot {
    private weak var au: MidiSparkAudioUnit?
    private(set) var running = false
    private(set) var chordCount = 0
    private(set) var status = "OK"
    private var held = Set<UInt8>()
    private var index = 0
    private var stuckStreak = 0

    // A gentle modal loop (D-dorian family) — clean 4-note voicings across C3–C5 so the grid's processors have material
    // without mud. Exactly ONE chord is held at a time (each dwell releases the last, strikes the next) → never silent,
    // never a pile-up.
    private static let progression: [[UInt8]] = [
        [57, 60, 64, 67],   // Am7   · A C E G
        [50, 57, 60, 65],   // Dm7   · D A C F
        [55, 59, 62, 65],   // G7    · G B D F
        [48, 55, 60, 64],   // Cmaj7 · C G C E
        [53, 57, 60, 64],   // Fmaj7 · F A C E
        [52, 55, 59, 62],   // Em7   · E G B D
    ]
    private static let dwellSeconds = 2.2

    func start(au: MidiSparkAudioUnit) {
        guard !running else { return }
        self.au = au; running = true; index = 0; chordCount = 0; held = []; stuckStreak = 0; status = "OK"
        au.setFreeRunEnabled(true)                     // sound while the host transport is stopped
        write("AUTO-RUN START — calm self-player")
        tick()                                         // strike the first chord + schedule the loop
    }
    func stop() {
        guard running else { return }
        running = false
        release()                                      // note-off everything we hold
        au?.setFreeRunEnabled(false)                   // hand the clock back to the host
        write("AUTO-RUN STOP — \(chordCount) chords")
        au = nil
    }

    private func release() { held.forEach { au?.chaosInjectMIDI(0x80, $0, 0) }; held.removeAll() }

    private func tick() {
        guard running, let au = au else { return }
        release()                                                          // drop the previous chord (exactly one sounds)
        let chord = Self.progression[index % Self.progression.count]
        index += 1; chordCount += 1
        let vel = UInt8(78 + (index % 3) * 12)                             // a touch of deterministic dynamics (78/90/102)
        for n in chord { au.chaosInjectMIDI(0x90, n, vel); held.insert(n) }
        checkOracle()
        if chordCount % 8 == 1 { write("… \(chordCount) chords · \(status)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwellSeconds) { [weak self] in self?.tick() }
    }
    // A light stuck-note readout (reuses the kernel oracle): host stopped + our pool drained yet notes still SOUNDING
    // means a hung note — surfaced on screen + in the log for an unattended soak. Silence is not flagged (an empty grid
    // is legitimately silent).
    private func checkOracle() {
        guard let d = au?.kernelDiagnostics() else { return }
        stuckStreak = (!d.playing && d.poolCount == 0 && d.distinctSounding > 0) ? stuckStreak + 1 : 0
        status = stuckStreak >= 3 ? "⚠ STUCK \(d.distinctSounding)" : "OK"
    }

    // The unified log (os_log) is the only channel an AUv3 extension reliably surfaces — read it live in Console.app
    // (subsystem com.paulbarrett.MidiSpark, category autorun).
    private static let logger = Logger(subsystem: "com.paulbarrett.MidiSpark", category: "autorun")
    private func write(_ s: String) { Self.logger.notice("\(s, privacy: .public)") }
}
#endif
