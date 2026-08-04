#if DEBUG
import Foundation
import os

/// ON-DEVICE CHAOS MODE — v1 (Layer 2 of the fuzz+chaos plan, 2026-08-04). This WHOLE FILE is `#if DEBUG`, so it is
/// impossible to ship enabled (compile-flag gated, not a hidden runtime toggle). It drives the SAME action handlers
/// real touches call — the AU's public methods — on a SEEDED loop with jittered timing, on the MAIN thread, WHILE the
/// engine renders live. That is what catches render↔main races + config-under-fire that the pure fuzz harness can't
/// (e.g. the header-dot render↔main crash class). MIDI itself comes from the host (AUM with a latched chord), per the
/// plan — chaos drives the CONTROL surface.
///
/// THE SEED LAW: the start seed is logged + written to a per-session dump (chaos v1 = minimal event dump in the app's
/// container; the ring-buffer logger is a fast-follow). Any `.ips` crash pairs with its input history via the seed +
/// build number. Replay = re-run from the same seed.
final class ChaosDriver {
    /// MIDI source: SIMULATED = chaos injects its OWN seeded spell-MIDI (self-contained soak, no controller); LIVE =
    /// MIDI comes from the host (AUM + a real latched chord) and chaos only fuzzes controls.
    enum Source { case simulated, live }
    private weak var au: MidiSparkAudioUnit?
    private var rng = ChaosRNG(0)
    private(set) var seed: UInt32 = 0
    private(set) var running = false
    private(set) var eventCount = 0
    private(set) var source: Source = .live
    var receiverMask: UInt8 = 0b0001        // which receivers are SELECTED for the test (bit i; default R1); others are disabled at start
    var speed: Double = 1.0                 // chaos-speed multiplier (overnight-soak vs quick shake)
    private var lines: [String] = []
    private var dumpURL: URL?

    // SIMULATED MIDI (user 2026-08-04): ALWAYS PLAYING — alternates sustained CHORDS with random BURSTS of notes
    // across ALL 16 channels; never silent. (The prefer-non-silent revert keeps the OUTPUT live too.)
    private enum Play { case chord, burst }
    private var play = Play.burst
    private var playLeft = 0
    private var heldSet = Set<UInt8>()

    // THE OUTPUT ORACLE: watches whether output MATCHES the state, and flags a mismatch on screen.
    private(set) var oracleFlag = "OK"
    private var stuckStreak = 0, silentStreak = 0

    // PREFER NON-SILENT (user 2026-08-04): if a held chord isn't sounding for a few steps, REVIVE — reset EVERY gate
    // that can silence output (mutes, disables, bypass, master mute/kill, off-channel/narrow-range receivers), since
    // silence usually accrues from several actions at once. Keeps the soak live rather than parking in a silent corner.
    private var reviveStreak = 0

    func start(au: MidiSparkAudioUnit, seed: UInt32, source: Source = .live) {
        guard !running else { return }
        self.au = au; self.seed = seed; self.source = source; rng = ChaosRNG(seed)
        running = true; eventCount = 0; lines = []; heldSet = []; play = .burst; playLeft = 0   // first tick seeds a chord
        stuckStreak = 0; silentStreak = 0; oracleFlag = "OK"
        au.chaosSetActive(true)   // gate the render-side chain-dump to this session
        setupReceivers(au)        // FIRST: disable non-selected receivers, make the selected ones receptive — then never touch receivers again
        write("CHAOS START · seed=0x\(String(seed, radix: 16)) · MIDI=\(source == .simulated ? "SIMULATED" : "LIVE") · recv=0b\(String(receiverMask, radix: 2)) · speed=\(speed)")
        schedule()
    }
    func stop() {
        guard running else { return }
        if source == .simulated { heldSet.forEach { au?.chaosInjectMIDI(0x80, $0, 0) }; heldSet.removeAll() }   // release our notes
        au?.chaosSetActive(false)
        running = false; write("CHAOS STOP · \(eventCount) events")
    }

    // Jittered gap: mostly short ms, occasional near-0 burst, occasional multi-second idle — both extremes find bugs.
    private func schedule() {
        guard running else { return }
        let roll = rng.double()
        let gapMs = roll < 0.15 ? 0.0 : (roll > 0.95 ? Double(rng.range(1500, 4000)) : Double(rng.range(8, 120)))
        DispatchQueue.main.asyncAfter(deadline: .now() + gapMs / 1000.0 / max(0.1, speed)) { [weak self] in
            self?.fire(); self?.schedule()
        }
    }

    private func fire() {
        guard running, let au = au else { return }
        let d = au.kernelDiagnostics()
        // PREFER NON-SILENT: a held chord that hasn't sounded for a few steps → REVIVE (reset every silencing gate).
        reviveStreak = (d.poolCount > 0 && d.distinctSounding == 0) ? reviveStreak + 1 : 0
        if reviveStreak >= 2 {   // 2 steps of silence-under-a-held-chord (enough for the injected notes to render)
            revive(au); reviveStreak = 0; eventCount += 1; return   // not logged (user 2026-08-04)
        }
        checkOracle()
        if source == .simulated, rng.chance(0.45) { midiTick(au); eventCount += 1; return }   // some fires PLAY (spell MIDI)
        // Receivers are configured once at start and never touched again (user 2026-08-04) — chaos fuzzes the
        // processing + output surface: roles, emitter octave/enable, master, ladder, clock.
        let i = rng.int(4), pct = rng.int(101), on = rng.chance(0.5)
        switch rng.int(15) {
        case 0:  au.setClaim(i)
        case 1:  au.setClaimLeak(i, pct)
        case 2:  au.setFlatten(i, on)
        case 3:  au.setFlattenAmount(i, pct)
        case 4:  au.setAlt(i, on)
        case 5:  au.setAltCount(i, rng.range(1, 8))
        case 6:  au.setEmitterOctave(i, rng.range(-2, 2))
        case 7:  au.setBusEnabled(i, on)
        case 8:  au.nudgeMasterKey(rng.chance(0.5) ? 1 : -1)         // KEY± during held chords
        case 9:  au.setMasterMute(on)
        case 10: au.setMasterVelOverride(on ? rng.range(1, 127) : nil)
        case 11: au.setLadderMode(on)
        case 12: au.setActiveRow(rng.int(8), rng.int(8))
        case 13: au.setStepRateIndex(rng.int(6))
        default: rng.chance(0.15) ? au.masterPanic() : au.setSwing(rng.range(50, 75))   // PANIC rarely
        }
        eventCount += 1
        if eventCount % 50 == 0 { write("… \(eventCount) events · oracle=\(oracleFlag)") }
    }
    // REVIVE — open every gate that can silence output, so a held chord sounds again: master mute/kill/vel-override
    // off, ladder off, all emitters enabled (no vel-kill), all receivers un-muted / listening / un-bypassed / OMNI /
    // full-range. The one control the soak treats as sacred-to-keep-live.
    // REVIVE resets only the OUTPUT gates — receivers are fixed by setupReceivers and chaos never touches them.
    private func revive(_ au: MidiSparkAudioUnit) {
        au.setMasterMute(false); au.setMasterKill(false); au.setMasterVelOverride(nil); au.setLadderMode(false)
        for i in 0..<4 { au.setBusEnabled(i, true); au.setEmitterVelKill(i, false) }
    }
    // ONE-TIME at start: DISABLE every receiver that isn't selected for the test; make the SELECTED ones receptive
    // (listening · un-muted · un-bypassed · OMNI · full-range) so they hear the G-minor MIDI. Chaos never touches
    // receivers after this.
    private func setupReceivers(_ au: MidiSparkAudioUnit) {
        let recs = au.uiReceivers()
        for i in 0..<4 where i < recs.count {
            let r = recs[i], selected = receiverMask & (1 << UInt8(i)) != 0
            if selected {
                if !r.inputEnabledResolved { au.toggleReceiverEnabled(i) }
                if r.muted { au.toggleReceiverMute(i) }
                if r.bypassResolved { au.toggleReceiverBypass(i) }
                au.setReceiverChannel(i, 0); au.setReceiverRange(i, lo: 0, hi: 127)
            } else if r.inputEnabledResolved {
                au.toggleReceiverEnabled(i)   // disable the non-selected door
            }
        }
    }

    // SIMULATED MIDI — ALWAYS PLAYING, all notes in G MINOR: alternate a sustained Gm7 CHORD with a BURST of random
    // in-scale notes across all channels.
    private func midiTick(_ au: MidiSparkAudioUnit) {
        func on(_ n: UInt8, _ ch: Int) { au.chaosInjectMIDI(0x90 | UInt8(ch & 15), n, UInt8(rng.range(1, 127))); heldSet.insert(n) }
        func off(_ n: UInt8) { au.chaosInjectMIDI(0x80, n, 0); heldSet.remove(n) }
        if playLeft <= 0 {                                                          // switch phase: release the old, seed the new
            play = play == .chord ? .burst : .chord
            playLeft = rng.range(3, 8)
            Array(heldSet).forEach(off)
            if play == .chord { let ch = rng.int(16), g = 12 * rng.range(3, 5) + 7; for iv in [0, 3, 7, 10] where g + iv <= 127 { on(UInt8(g + iv), ch) } }   // Gm7: G Bb D F
        }
        playLeft -= 1
        switch play {
        case .chord: if rng.chance(0.25) { on(gMinor(rng.range(36, 96)), rng.int(16)) }                                       // sustain; occasionally thicken (in scale)
        case .burst: Array(heldSet).forEach(off); for _ in 0..<rng.range(2, 6) { on(gMinor(rng.int(128)), rng.int(16)) }      // fresh scatter, in-scale notes on ALL channels
        }
        if heldSet.isEmpty { on(gMinor(rng.range(48, 72)), 0) }                      // guarantee: at least one note is always sounding
    }
    // G MINOR (natural): semitone offsets from G — G · A · Bb · C · D · Eb · F. Every simulated note snaps into it.
    private static let gMinorScale: Set<Int> = [0, 2, 3, 5, 7, 8, 10]
    private func gMinor(_ note: Int) -> UInt8 {
        let n = max(0, min(127, note))
        let rel = ((n % 12) - 7 + 12) % 12                                           // pitch class relative to G
        var off = rel; while off > 0 && !Self.gMinorScale.contains(off) { off -= 1 } // snap DOWN to the nearest scale tone
        return UInt8(n - (rel - off))
    }

    // THE ORACLE — does the OUTPUT match the STATE? Reads the live diag and flags a mismatch on screen + in the log.
    //  • STUCK (precise): transport stopped + NO notes held, yet notes still SOUNDING → a hung note.
    //  • SILENT (heuristic): playing + notes HELD, yet NOTHING out for a while → maybe silent-when-it-should-sound
    //    (soft "?" — legitimately silent if every routed cell is currently gated, e.g. a closed passgate).
    private func checkOracle() {
        guard let au = au else { return }
        let d = au.kernelDiagnostics()
        stuckStreak  = (!d.playing && d.poolCount == 0 && d.distinctSounding > 0) ? stuckStreak + 1 : 0
        // SILENT is only SUSPICIOUS when a ROUTED PATH exists (the engine's structural verdict). No path ⇒ the silence
        // is EXPECTED (nothing routes a held note to an enabled emitter) — not flagged.
        silentStreak = (d.playing && d.poolCount > 0 && d.distinctSounding == 0 && d.routedPath) ? silentStreak + 1 : 0
        let flag = stuckStreak >= 4  ? "⚠ STUCK \(d.distinctSounding) sounding, none held"
                 : silentStreak >= 12 ? "⚠ SILENT (routed path, none out)"
                 : "OK"
        if flag != oracleFlag {
            oracleFlag = flag
            if flag.hasPrefix("⚠") {
                write("ORACLE \(flag) · seed 0x\(String(seed, radix: 16))")
                write(au.chaosRoutingDump())   // the full MIDI-chain dump (built render-side at the streak threshold)
            }
        }
    }

    // PRIMARY channel = the UNIFIED LOG (os_log), the only log an AUv3 extension can reliably surface: read it LIVE in
    // Console.app on a Mac (filter subsystem `com.paulbarrett.MidiSpark`, category `chaos`). The extension's Documents
    // container is NOT reachable from the iPad's Files app / Spotlight, so the file is a best-effort Xcode-container
    // fallback only. (Multi-line dumps come through as one entry.)
    private static let logger = Logger(subsystem: "com.paulbarrett.MidiSpark", category: "chaos")
    private func write(_ s: String) {
        lines.append(s)
        Self.logger.notice("\(s, privacy: .public)")   // ← Console.app, subsystem com.paulbarrett.MidiSpark
        if dumpURL == nil, let dir = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            dumpURL = dir.appendingPathComponent("chaos-0x\(String(seed, radix: 16)).log")
        }
        if let url = dumpURL { try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// mulberry32 — reproducible from a UInt32 seed (the SEED LAW), matching the fuzz harness's RNG family.
private struct ChaosRNG {
    private var s: UInt32
    init(_ seed: UInt32) { s = seed &+ 0x9E3779B9 }
    mutating func u32() -> UInt32 {
        s &+= 0x6D2B79F5; var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ (t ^ (t >> 7)) &* (t | 61)
        return t ^ (t >> 14)
    }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(u32() % UInt32(n)) }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + int(max(1, hi - lo + 1)) }
    mutating func double() -> Double { Double(u32()) / Double(UInt32.max) }
    mutating func chance(_ p: Double) -> Bool { double() < p }
}
#endif
