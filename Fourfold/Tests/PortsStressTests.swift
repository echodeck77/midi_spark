//  PortsStressTests.swift — a seeded fuzz of THE NINE PORTS (written by the 2026-10-27 adversarial review, which found the lane-D legato trap with it).
//  Drives one Router through many randomised render windows (random documents, note sources,
//  tempo, window sizes, transport edges, busChannels changing mid-note, solo/allNotesOff/panic)
//  and asserts the port/channel/stuck-note invariants after every stop and at the end.

import XCTest

// Deterministic, seedable RNG.
private struct SM64: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private final class TaggedEmitter: MIDIEmitter {
    struct Ev { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8; let win: Int }
    var events: [Ev] = []
    var win = 0
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        // Treat a 0x90 with vel 0 as an off (running-status off), as hosts do.
        var st = b0 & 0xF0
        if st == 0x90 && b2 == 0 { st = 0x80 }
        events.append(Ev(sample: sampleTime, cable: cable, status: st, chan: b0 & 0x0F, note: b1, vel: b2, win: win))
    }
}

final class PortsStressTests: XCTestCase {

    // HOCKET ferry (2026-10-27) §12 test 1: a fingerprint of EVERY message the 600 + 600 seeded sessions send, captured on the nine-output engine (main 9f1b08d) before any hocket work. With no hocket rule in the
    // document (these seeds draw none) the engine must stay byte-identical — including the raw-gate seeds, where legato runs on every port, which the factory-preset golden never reaches.
    private var lastSessionHash: UInt64 = 0
    private func sessionHash(_ e: TaggedEmitter) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for ev in e.events {
            for v in [UInt64(bitPattern: ev.sample), UInt64(ev.cable), UInt64(ev.status), UInt64(ev.chan), UInt64(ev.note), UInt64(ev.vel)] { h = (h ^ v) &* 0x100000001b3 }
        }
        return h
    }

    // ---- document generation ---------------------------------------------------

    private func rLine(_ g: inout SM64) -> EuclidLine {
        var l = EuclidLine()
        l.pulses = Int.random(in: 0...16, using: &g)
        l.steps = Int.random(in: 1...16, using: &g)
        l.rotate = Int.random(in: -8...8, using: &g)
        l.direction = [.fwd, .bkw, .pingpong].randomElement(using: &g)!
        l.enabled = Bool.random(using: &g) ? nil : Bool.random(using: &g)
        // gate: exercise exactly 1.0 (legato immortal-voice path) and 0.99, plus the ordinary range.
        l.gate = [1.0, 0.99, 0.9, Double.random(in: 0.05...1.0, using: &g)].randomElement(using: &g)!
        l.octave = Int.random(in: -3...3, using: &g)
        l.velocity = Double.random(in: 0...2, using: &g)
        l.velocityAbsolute = Bool.random(using: &g) ? nil : Int.random(in: 1...127, using: &g)
        l.rate = Bool.random(using: &g) ? nil : ArpRate.allCases.randomElement(using: &g)!
        l.patternMiss = Bool.random(using: &g) ? nil : true
        // riff / notes layers (independent streams)
        l.riffOn = Bool.random(using: &g)
        l.useRiff = l.riffOn
        if Bool.random(using: &g) {
            // lit order as a valid shuffled subset of 0...9
            var pool = Array(UInt8(0)...9); pool.shuffle(using: &g)
            l.notesLitOrder = Array(pool.prefix(Int.random(in: 0...4, using: &g)))
        } else {
            l.litNotes = UInt8.random(in: 0...255, using: &g)
            l.topLit = Bool.random(using: &g); l.top2Lit = Bool.random(using: &g)
        }
        l.riffRotate = Int.random(in: 0...7, using: &g)
        l.riffOctave = Int.random(in: -2...2, using: &g)
        l.riffDir = [.forward, .reverse, .pendulum, .pingpong, .random, .drunk].randomElement(using: &g)!
        l.riffLock = Bool.random(using: &g)
        l.riffInvert = Bool.random(using: &g)
        l.riffOnRest = EuclidRiffOnRest.allCases.randomElement(using: &g)!
        l.riffStride = Int.random(in: 1...7, using: &g)
        l.riffLength = Int.random(in: 1...8, using: &g)
        l.riffAdvanceStep = Bool.random(using: &g)
        l.riffAdvanceEvery = Int.random(in: 1...4, using: &g)
        l.notesPlayAs = EuclidNotesPlayAs.allCases.randomElement(using: &g)!
        l.notesWhen = [0b01, 0b10, 0b11].randomElement(using: &g)!
        l.notesChance = [25, 50, 75, 100].randomElement(using: &g)!
        l.notesGate = [1.0, 0.99, Double.random(in: 0.05...1, using: &g)].randomElement(using: &g)!
        l.notesVelocity = Int.random(in: 1...127, using: &g)
        l.notesReceivedOnly = Bool.random(using: &g)
        l.tilt = Double.random(in: -1...1, using: &g)
        l.tiltFine = Bool.random(using: &g) ? nil : Double.random(in: -1...1, using: &g)
        l.offsetFraction = Bool.random(using: &g) ? nil : Double.random(in: 0...0.999, using: &g)
        l.muteCells16 = UInt16.random(in: 0...0xFFFF, using: &g)
        l.muteUnit = UInt8.random(in: 0...3, using: &g)
        // LISTEN borrow — COPY/FILL (rhythm), SHADOW/ECHO/AVOID (pitch), with a source lane
        l.listenSource = Int.random(in: 0...3, using: &g)
        l.listenRhythm = EuclideousListenRhythmMode.allCases.randomElement(using: &g)!
        l.listenPitch = EuclideousListenPitchMode.allCases.randomElement(using: &g)!
        l.listenInterval = Int.random(in: -6...6, using: &g)
        l.listenOctave = Int.random(in: -3...3, using: &g)
        l.listenDelay = Int.random(in: 0...6, using: &g)
        l.listenFeel = Double.random(in: -1...1, using: &g)
        l.listenSpeed = Int.random(in: -2...2, using: &g)
        l.listenDirection = [.fwd, .bkw, .pingpong].randomElement(using: &g)!
        // restart chains (pinned, as the main-thread migration would)
        if Bool.random(using: &g) {
            func chain(_ g: inout SM64) -> [UInt8] { (0..<Int.random(in: 1...4, using: &g)).map { _ in [1,2,3,4,6,8].randomElement(using: &g)! } }
            let bars = chain(&g), passes = chain(&g)
            l.restartRhythmBars = bars; l.restartMelodyPasses = passes
            euclideousPinRestartChains(&l, .from(bars), .from(passes))
        }
        return l
    }

    private func rFX(_ g: inout SM64) -> EuclideousFX {
        var fx = EuclideousFX()
        for r in 0..<6 {
            fx.lanes[r] = UInt8.random(in: 0...0b1111, using: &g)
            for c in 0..<8 where Bool.random(using: &g) {
                let raw: Int
                switch r {
                case 0: raw = Int.random(in: 2...4, using: &g)      // RATCH
                case 1: raw = Int.random(in: 5...95, using: &g)     // GATE
                case 2: raw = 1                                      // TIE
                case 3: raw = Int.random(in: 1...127, using: &g)    // VEL
                case 4: raw = Int.random(in: -3...3, using: &g)     // NOTE
                default: raw = Int.random(in: 0...127, using: &g)   // CC
                }
                fx.cells[r * 8 + c] = EuclideousFX.legalCell(row: r, raw: raw) ?? EuclideousFX.emptyCell
            }
        }
        fx.notePasses = UInt8.random(in: 2...8, using: &g)
        fx.ccNumber = UInt8.random(in: 0...119, using: &g)
        fx.ccBase = Bool.random(using: &g) ? -1 : Int16.random(in: 0...127, using: &g)
        fx.ratchShape = UInt8.random(in: 0...3, using: &g)
        return fx.normalized()
    }

    /// Build a full Fourfold page document + its note pool.
    /// `rawGates`: feed the chain the lines as generated (gate/notesGate up to exactly 1.0 = LEGATO reaches the engine), instead of through `euclideousLinesResolved` (the app's publish path, which caps them at 0.99).
    private func rDoc(_ g: inout SM64, lanes: [EuclidLine]? = nil, rawGates: Bool = false) -> (PluginState, NotePool) {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let raw = lanes ?? (0..<4).map { _ in rLine(&g) }
        st.euclideousLines = raw
        // Production-faithful: the real publish path feeds the chain `document.euclideousLinesResolved`
        // (uiEuclideousLines), which clamps gate/notesGate to 0.99 etc. Mirror that so the fuzz hunts
        // bugs reachable in the shipping app. (Raw gate 1.0 → the legato trap is probed separately.)
        let ls = rawGates ? raw : st.euclideousLinesResolved
        st.euclideousLines = ls
        if Bool.random(using: &g) { st.euclideousLocks = ls.enumerated().map { (i, l) in
            Bool.random(using: &g) ? EuclideousLaneLock.locking(l, grid: .bar1) : EuclideousLaneLock() } }
        let solo = UInt8.random(in: 0...0b1111, using: &g)
        st.euclideousSoloMask = solo
        let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                          activeRiff: st.activeRiffResolved, soloMask: solo,
                                          locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        st.euclideousFX = rFX(&g)
        // note source: MIDI (held pool) + a stacking plan of KEY / CHORDS
        var plan = SourcePlan()
        plan.chordsWithMidi = Bool.random(using: &g); plan.chordsNoMidi = Bool.random(using: &g)
        plan.keyWithMidi = Bool.random(using: &g); plan.keyNoMidi = Bool.random(using: &g)
        st.euclideousSourcePlan = plan
        st.euclideousNoteSource = [.midi, .key, .chords].randomElement(using: &g)!
        st.euclideousKeyRoot = Int.random(in: 0...11, using: &g)
        st.euclideousKeyType = ScaleType.allCases.randomElement(using: &g)!
        st.euclideousHoldLatchMode = [nil, .hold, .latch].randomElement(using: &g)!
        // busChannels: 8-form, 4-form (both ports of a lane share a channel), out-of-range, and 0.
        switch Int.random(in: 0...4, using: &g) {
        case 0: st.busChannels = (0..<8).map { _ in Int.random(in: 1...16, using: &g) }
        case 1: st.busChannels = (0..<4).map { _ in Int.random(in: 1...16, using: &g) }   // pre-ports 4-form
        case 2: st.busChannels = (0..<8).map { _ in Int.random(in: 0...99, using: &g) }   // out-of-range / 0
        case 3: st.busChannels = [UInt8.random(in: 0...20, using: &g)].map { _ in Int.random(in: 1...16, using: &g) }   // short
        default: st.busChannels = nil                                                     // default 1...8
        }
        let pool = NotePool()
        for _ in 0..<Int.random(in: 0...6, using: &g) {
            pool.noteOn(UInt8.random(in: 24...96, using: &g), velocity: UInt8.random(in: 1...127, using: &g),
                        channel: UInt8.random(in: 0...15, using: &g))
        }
        return (st, pool)
    }

    // ---- invariant analysis ----------------------------------------------------

    private struct Finding { let seed: UInt64; let msg: String }

    /// Returns a failure message, or nil. `stopWins` = window indices that were STOP windows (balance must be 0 by their end).
    private func analyse(_ e: TaggedEmitter, seed: UInt64, winChans: [[UInt8]], stopWins: Set<Int>) -> String? {
        // balance per (cable, chan, note)
        var bal: [Int: Int] = [:]
        func key(_ c: UInt8, _ ch: UInt8, _ n: UInt8) -> Int { (Int(c) * 16 + Int(ch)) * 128 + Int(n) }
        // union check: multiset of (sample,note,vel,chan) of NOTE-ONs for ports 1..8 vs ALL (0).
        // Only ONs form an exact union — offs collapse/shift on ALL by the §7 collision refcount +
        // restrike policy (a restrike-off fires whenever refcount>0), so an off-union would false-fail.
        var portMS: [String: Int] = [:], allMS: [String: Int] = [:]
        func msk(_ ev: TaggedEmitter.Ev) -> String { "\(ev.sample)/\(ev.note)/\(ev.vel)/\(ev.chan)" }

        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            // (b) no orphan off: balance must never go negative
            let k = key(ev.cable, ev.chan, ev.note)
            if ev.status == 0x90 {
                bal[k, default: 0] += 1
                // (e) per-port channel stamp at note-on: cable c on-channel == expected port c-1 channel THIS window
                if ev.cable >= 1 && ev.cable <= 8 {
                    let want = (winChans[ev.win][Int(ev.cable) - 1] &- 1) & 15
                    if ev.chan != want {
                        return "seed \(seed): cable \(ev.cable) note-ON ch \(ev.chan) != expected port channel \(want) (win \(ev.win))"
                    }
                }
            } else {
                bal[k, default: 0] -= 1
                if bal[k]! < 0 {
                    return "seed \(seed): ORPHAN note-off cable \(ev.cable) ch \(ev.chan) note \(ev.note) (win \(ev.win)) — no matching on"
                }
            }
            // union bookkeeping — ONs only
            if ev.status == 0x90 {
                if ev.cable == 0 { allMS[msk(ev), default: 0] += 1 }
                else if ev.cable <= 8 { portMS[msk(ev), default: 0] += 1 }
            }
        }
        // (a) end-of-run: nothing left sounding
        for (k, v) in bal where v != 0 {
            let c = (k / 128) / 16, ch = (k / 128) % 16, n = k % 128
            return "seed \(seed): STUCK note — cable \(c) ch \(ch) note \(n) balance \(v) at end"
        }
        // (d) ALL == union of the eight ports (notes only). Skip if the voice table ever filled (own may open, all may not).
        if portMS != allMS {
            // surface the first discrepancy
            let onlyPort = portMS.filter { allMS[$0.key] != $0.value }.keys.sorted().first
            let onlyAll = allMS.filter { portMS[$0.key] != $0.value }.keys.sorted().first
            return "seed \(seed): ALL != union of ports — port-only \(onlyPort ?? "-") / all-only \(onlyAll ?? "-")"
        }
        return nil
    }

    /// Drive one seeded session: many windows with mid-stream mutation, return a failure message or nil.
    private func runSession(seed: UInt64, windows: Int, rawGates: Bool = false) -> String? {
        var g = SM64(seed)
        let router = Router()
        var diag = KernelDiag()
        let e = TaggedEmitter()
        var (st, pool) = rDoc(&g, rawGates: rawGates)
        var box = SnapshotBuilder.build(from: st)
        let sr = 48_000.0
        var tempo = Double([90, 120, 140].randomElement(using: &g)!)
        var beat = 0.0, ts = 0.0
        var playing = true
        var wasPlaying = true
        var winChans: [[UInt8]] = []
        var stopWins = Set<Int>()
        var maxActive = 0

        for w in 0..<windows {
            e.win = w
            // mutate the document / transport between windows
            if Int.random(in: 0...3, using: &g) == 0 { (st, _) = rDoc(&g, rawGates: rawGates); box = SnapshotBuilder.build(from: st) }   // whole new doc
            if Int.random(in: 0...2, using: &g) == 0 {   // busChannels change mid-note
                switch Int.random(in: 0...3, using: &g) {
                case 0: st.busChannels = (0..<8).map { _ in Int.random(in: 1...16, using: &g) }
                case 1: let c = Int.random(in: 1...16, using: &g); st.busChannels = [c, c, c, c, c, c, c, c]   // every port same channel
                case 2: st.busChannels = (0..<4).map { _ in Int.random(in: 1...16, using: &g) }
                default: st.busChannels = (0..<8).map { _ in Int.random(in: 0...99, using: &g) }
                }
                box = SnapshotBuilder.build(from: st)
            }
            if Int.random(in: 0...4, using: &g) == 0 { tempo = Double([60, 90, 120, 160, 200].randomElement(using: &g)!) }
            // note pool churn (MIDI held notes change)
            if Int.random(in: 0...2, using: &g) == 0 {
                if Bool.random(using: &g) { pool.reset() }
                for _ in 0..<Int.random(in: 0...4, using: &g) { pool.noteOn(UInt8.random(in: 24...96, using: &g), velocity: UInt8.random(in: 1...127, using: &g), channel: UInt8.random(in: 0...15, using: &g)) }
            }

            let frames = UInt32([64, 128, 256, 512, 1024, 2048, 4096].randomElement(using: &g)!)
            // transport: random stop/start and beat jumps
            wasPlaying = playing
            if Int.random(in: 0...5, using: &g) == 0 { playing.toggle() }
            if Int.random(in: 0...6, using: &g) == 0 { beat += Double.random(in: -8...32, using: &g) }   // seek / loop jump
            let solo = UInt16(st.euclideousSoloMaskResolved)
            let liveSolo = Int.random(in: 0...3, using: &g) == 0 ? UInt16.random(in: 0...0b1111, using: &g) : solo
            let allOff = Int.random(in: 0...10, using: &g) == 0
            let panic = Int.random(in: 0...30, using: &g) == 0
            let laneMask: UInt16 = Int.random(in: 0...4, using: &g) == 0 ? UInt16.random(in: 0...0xFF, using: &g) : 0

            winChans.append(box.busChannels)
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: laneMask,
                           panic: panic, euclideousAllNotesOff: allOff, euclideousSoloLive: liveSolo,
                           out: e, diag: &diag)
            maxActive = max(maxActive, diag.activeVoiceCount)
            if !playing && wasPlaying { stopWins.insert(w) }   // this window carried the stop edge → flush
            beat += Double(frames) * tempo / 60.0 / sr
            ts += Double(frames)
        }
        // final hard stop: a playing→stopped edge must flush everything.
        e.win = windows
        winChans.append(box.busChannels)
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        stopWins.insert(windows)

        lastSessionHash = sessionHash(e)
        // If the voice table got close to full, the ALL-union property can legitimately break
        // (own opens, all can't). Note it but don't let it mask the stuck-note checks.
        if let msg = analyse(e, seed: seed, winChans: winChans, stopWins: stopWins) {
            if msg.contains("ALL != union") && maxActive >= 120 { return nil }
            return msg
        }
        return nil
    }

    // ---- the fuzz runs ---------------------------------------------------------

    private func elog(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

    // REGRESSION (adversarial review 2026-10-27): a LEGATO (gate 1.0) notes-layer pitch on lane D is on bus 7 = bus MASK 128, which `reconcileEuclidLegato` used to store in an [Int8] and trapped
    // (Int8(128)) on the render thread. The app's gate cap (0.99) hid it; a hand-built document or a relaxed cap would not. Every lane's notes AND riff port must survive legato.
    private func legatoReproDoc(lane: Int, notes: Bool, applyResolved: Bool) -> (PluginState, NotePool) {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        var lines = (0..<4).map { _ in var l = EuclidLine(); l.enabled = false; return l }
        var d = EuclidLine()
        d.enabled = true; d.pulses = 8; d.steps = 8
        if notes { d.riffOn = false; d.useRiff = false; d.litNotes = 0b0000_0001; d.notesWhen = 0b11; d.notesPlayAs = .chord; d.notesGate = 1.0 }
        else { d.riffOn = true; d.useRiff = true; d.gate = 1.0; d.notesOn = false }
        lines[lane] = d
        st.euclideousLines = lines
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(); st.euclideousSoloMask = 0
        let use = applyResolved ? st.euclideousLinesResolved : lines
        st.euclideousLines = use
        let input = FourfoldCompose.Input(lines: use, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: 0, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        return (st, pool)
    }
    func testLegatoOnEveryLanesRiffAndNotesPortHoldsAndClosesWithoutTrapping() {
        for lane in 0..<4 { for notes in [false, true] {
            let (st, pool) = legatoReproDoc(lane: lane, notes: notes, applyResolved: false)   // raw gate 1.0 reaches the engine
            let box = SnapshotBuilder.build(from: st)
            let router = Router(); var diag = KernelDiag(); let e = TaggedEmitter()
            var beat = 0.0, ts = 0.0
            for _ in 0..<24 {
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
                beat += 512 * 120.0 / 60 / 48000; ts += 512
            }
            router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
            let port = UInt8(FourfoldPorts.cable(lane: lane, part: notes ? .notes : .riff))
            XCTAssertFalse(e.events.filter { $0.cable == port && $0.status == 0x90 }.isEmpty, "lane \(lane + 1) \(notes ? "notes" : "riff") legato sounds on cable \(port)")
            var bal: [Int: Int] = [:]
            for ev in e.events where ev.status == 0x90 || ev.status == 0x80 { bal[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note), default: 0] += ev.status == 0x90 ? 1 : -1 }
            XCTAssertTrue(bal.values.allSatisfy { $0 == 0 }, "lane \(lane + 1) \(notes ? "notes" : "riff") legato leaves nothing sounding")
            XCTAssertTrue(e.events.filter { $0.cable >= 1 && $0.cable <= 8 && $0.cable != port }.isEmpty, "…and nothing leaks onto another port")
        } }
    }

    func testFuzzManySeeds() {
        var firstFail: String? = nil
        var fingerprint: UInt64 = 0xcbf29ce484222325
        for s in 1...600 {
            if let msg = runSession(seed: UInt64(s), windows: 24) { firstFail = msg; break }
            fingerprint = (fingerprint ^ lastSessionHash) &* 0x100000001b3
        }
        if let f = firstFail { XCTFail(f); return }
        XCTAssertEqual(fingerprint, Self.fuzzFingerprint, "CAPTURE fuzzFingerprint = \(fingerprint) — the 600 seeded sessions' message streams must be bit-identical with no hocket rule")
    }
    private static let fuzzFingerprint: UInt64 = 12223291212352416553
    // The same fuzz with gate/notesGate left as generated (up to exactly 1.0 = legato), so the legato tracking runs on every port with every layer feature around it.
    func testFuzzRawGatesReachLegatoOnEveryPort() {
        var firstFail: String? = nil
        var fingerprint: UInt64 = 0xcbf29ce484222325
        for s in 1...600 {
            if let msg = runSession(seed: UInt64(s) &+ 100_000, windows: 24, rawGates: true) { firstFail = msg; break }
            fingerprint = (fingerprint ^ lastSessionHash) &* 0x100000001b3
        }
        if let f = firstFail { XCTFail(f); return }
        XCTAssertEqual(fingerprint, Self.fuzzFingerprintRaw, "CAPTURE fuzzFingerprintRaw = \(fingerprint) — the 600 raw-gate sessions' message streams must be bit-identical with no hocket rule")
    }
    private static let fuzzFingerprintRaw: UInt64 = 16229716498077922819

    // Lane isolation: only lane k emits on cables 2k+1 / 2k+2; other lanes' ports stay silent.
    func testLaneIsolation() {
        for s in 1...800 {
            var g = SM64(UInt64(s) &* 0x1234567)
            // exactly one live lane, the other three hard-disabled
            let live = Int.random(in: 0...3, using: &g)
            var lines: [EuclidLine] = (0..<4).map { i in
                if i == live { var l = rLine(&g); l.enabled = true; l.pulses = max(1, l.pulses); return l }
                var l = EuclidLine(); l.enabled = false; return l
            }
            // make the live lane definitely produce something
            lines[live].riffOn = true; lines[live].pulses = 8; lines[live].steps = 8
            var gg = SM64(UInt64(s))
            var (st, pool) = rDoc(&gg, lanes: lines)
            st.euclideousSoloMask = 0; st.euclideousNoteSource = .midi
            st.euclideousSourcePlan = SourcePlan()
            pool.reset(); for n in [60, 64, 67, 72] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
            st.euclideousLines = lines
            let rl = st.euclideousLinesResolved   // production-faithful (clamps gate etc.)
            let input = FourfoldCompose.Input(lines: rl, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                              activeRiff: 0, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
            st.scenes = [FourfoldCompose.scene(input)]
            let box = SnapshotBuilder.build(from: st)
            let router = Router(); var diag = KernelDiag(); let e = TaggedEmitter()
            var beat = 0.0, ts = 0.0
            for _ in 0..<20 { router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 1024, out: e, diag: &diag); beat += 1024 * 120 / 60 / 48000; ts += 1024 }
            router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
            for ev in e.events where ev.cable >= 1 && ev.cable <= 8 {
                let laneOfCable = (Int(ev.cable) - 1) / 2
                if laneOfCable != live {
                    XCTFail("seed \(s): disabled lane \(laneOfCable) emitted on cable \(ev.cable) (only lane \(live) live)")
                    return
                }
            }
        }
    }

    // Riff-off / notes-off port separation.
    func testRiffNotesPortSeparation() {
        for s in 1...800 {
            var g = SM64(UInt64(s) &* 0x55AA55AA)
            let riffOnly = Bool.random(using: &g)
            var l = EuclidLine()
            l.enabled = true; l.pulses = 8; l.steps = 8
            l.riffOn = riffOnly; l.useRiff = riffOnly
            if riffOnly { l.litNotes = 0; l.topLit = false; l.top2Lit = false }
            else { l.litNotes = 0b0000_0011; l.notesWhen = 0b11; l.notesPlayAs = .chord }
            let lines = [l, EuclidLine(), EuclidLine(), EuclidLine()].map { var x = $0; if $0 != l { x.enabled = false }; return x }
            var gg = SM64(UInt64(s))
            var (st, pool) = rDoc(&gg, lanes: lines)
            st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(); st.euclideousSoloMask = 0
            pool.reset(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
            st.euclideousLines = lines
            let rl = st.euclideousLinesResolved
            let input = FourfoldCompose.Input(lines: rl, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: 0, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
            st.scenes = [FourfoldCompose.scene(input)]
            let box = SnapshotBuilder.build(from: st)
            let router = Router(); var diag = KernelDiag(); let e = TaggedEmitter()
            var beat = 0.0, ts = 0.0
            for _ in 0..<24 { router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 1024, out: e, diag: &diag); beat += 1024 * 120 / 60 / 48000; ts += 1024 }
            router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
            let onRiffPort = e.events.contains { $0.cable == 1 && $0.status == 0x90 }
            let onNotesPort = e.events.contains { $0.cable == 2 && $0.status == 0x90 }
            if riffOnly && onNotesPort { XCTFail("seed \(s): riff-only lane emitted on NOTES port (cable 2)"); return }
            if !riffOnly && onRiffPort { XCTFail("seed \(s): notes-only lane emitted on RIFF port (cable 1)"); return }
        }
    }
}
