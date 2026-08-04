#if DEBUG
import Foundation

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
    var speed: Double = 1.0                 // chaos-speed multiplier (overnight-soak vs quick shake)
    private var lines: [String] = []
    private var dumpURL: URL?

    // SIMULATED MIDI: a spell-driven generator — HELD notes → SHORT notes → SILENCE (same shape as the fuzz harness).
    private var held: [UInt8] = []
    private var shorts: [UInt8] = []
    private enum Spell { case held, short, silence }
    private var spell = Spell.held
    private var spellLeft = 0

    // THE OUTPUT ORACLE: watches whether output MATCHES the state, and flags a mismatch on screen.
    private(set) var oracleFlag = "OK"
    private var stuckStreak = 0, silentStreak = 0

    func start(au: MidiSparkAudioUnit, seed: UInt32, source: Source = .live) {
        guard !running else { return }
        self.au = au; self.seed = seed; self.source = source; rng = ChaosRNG(seed)
        running = true; eventCount = 0; lines = []; held = []; shorts = []; spell = .held; spellLeft = rng.range(3, 8)
        stuckStreak = 0; silentStreak = 0; oracleFlag = "OK"
        write("CHAOS START · seed=0x\(String(seed, radix: 16)) · MIDI=\(source == .simulated ? "SIMULATED" : "LIVE") · speed=\(speed)")
        schedule()
    }
    func stop() {
        guard running else { return }
        if source == .simulated { held.forEach { au?.chaosInjectMIDI(0x80, $0, 0) }; shorts.forEach { au?.chaosInjectMIDI(0x80, $0, 0) } }   // release our notes
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
        checkOracle()
        if source == .simulated, rng.chance(0.45) { midiTick(au); eventCount += 1; return }   // some fires PLAY (spell MIDI)
        let i = rng.int(4), pct = rng.int(101), on = rng.chance(0.5)
        switch rng.int(24) {
        case 0:  au.setClaim(i)
        case 1:  au.setClaimLeak(i, pct)
        case 2:  au.setFlatten(i, on)
        case 3:  au.setFlattenAmount(i, pct)
        case 4:  au.setAlt(i, on)
        case 5:  au.setAltCount(i, rng.range(1, 8))
        case 6:  au.toggleReceiverMute(i)
        case 7:  au.toggleReceiverEnabled(i)
        case 8:  au.toggleReceiverBypass(i)
        case 9:  au.setReceiverChannel(i, rng.int(17))
        case 10: let lo = rng.int(128); au.setReceiverRange(i, lo: lo, hi: rng.range(lo, 127))
        case 11: au.setReceiverLatchAdd(i, on)
        case 12: au.setLatchArm(UInt8(rng.int(16)))                 // LATCH toggles while notes are held
        case 13: au.setInputVelOverride(i, on ? rng.range(1, 127) : nil)
        case 14: au.setInputOctave(i, rng.range(-2, 2))
        case 15: au.setEmitterOctave(i, rng.range(-2, 2))
        case 16: au.setBusEnabled(i, on)
        case 17: au.nudgeMasterKey(rng.chance(0.5) ? 1 : -1)         // KEY± during held chords
        case 18: au.setMasterMute(on)
        case 19: au.setMasterVelOverride(on ? rng.range(1, 127) : nil)
        case 20: au.setLadderMode(on)
        case 21: au.setActiveRow(rng.int(8), rng.int(8))
        case 22: au.setStepRateIndex(rng.int(6))
        default: rng.chance(0.15) ? au.masterPanic() : au.setSwing(rng.range(50, 75))   // PANIC rarely
        }
        eventCount += 1
        if eventCount % 50 == 0 { write("… \(eventCount) events · oracle=\(oracleFlag)") }
    }

    // SIMULATED MIDI — advance the HELD → SHORT → SILENCE spell and inject via the AU's debug MIDI path.
    private func midiTick(_ au: MidiSparkAudioUnit) {
        func on(_ n: UInt8) { au.chaosInjectMIDI(0x90, n, UInt8(rng.range(1, 127))) }
        func off(_ n: UInt8) { au.chaosInjectMIDI(0x80, n, 0) }
        if spellLeft <= 0 {
            spell = spell == .held ? .short : (spell == .short ? .silence : .held)
            spellLeft = rng.range(3, 8)
            if spell != .held { held.forEach(off); held.removeAll() }
            if spell == .silence { shorts.forEach(off); shorts.removeAll() }
        }
        spellLeft -= 1
        switch spell {
        case .held:    if held.isEmpty || rng.chance(0.4) { let n = UInt8(rng.int(128)); on(n); held.append(n) }
        case .short:   shorts.forEach(off); shorts.removeAll(); for _ in 0..<rng.range(1, 3) { let n = UInt8(rng.int(128)); on(n); shorts.append(n) }
        case .silence: break
        }
    }

    // THE ORACLE — does the OUTPUT match the STATE? Reads the live diag and flags a mismatch on screen + in the log.
    //  • STUCK (precise): transport stopped + NO notes held, yet notes still SOUNDING → a hung note.
    //  • SILENT (heuristic): playing + notes HELD, yet NOTHING out for a while → maybe silent-when-it-should-sound
    //    (soft "?" — legitimately silent if every routed cell is currently gated, e.g. a closed passgate).
    private func checkOracle() {
        guard let d = au?.kernelDiagnostics() else { return }
        stuckStreak  = (!d.playing && d.poolCount == 0 && d.distinctSounding > 0) ? stuckStreak + 1 : 0
        silentStreak = ( d.playing && d.poolCount > 0 && d.distinctSounding == 0) ? silentStreak + 1 : 0
        let flag = stuckStreak >= 4 ? "⚠ STUCK: \(d.distinctSounding) sounding, none held"
                 : silentStreak >= 10 ? "⚠ SILENT?: \(d.poolCount) held, none out"
                 : "OK"
        if flag != oracleFlag { oracleFlag = flag; if flag != "OK" { write("ORACLE \(flag) (seed 0x\(String(seed, radix: 16)))") } }
    }

    private func write(_ s: String) {
        lines.append(s)
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
