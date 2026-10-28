//  PortsStressTests.swift — a seeded fuzz of the OUTPUTS (first written for THE NINE PORTS by the 2026-10-27 adversarial review, which found the lane-D legato trap with it; CARD BACKS 2026-10-28 moved it to the
//  five outputs and added the per-part routing masks to what it randomises).
//  Drives one Router through many randomised render windows (random documents, random part→output masks, note sources,
//  tempo, window sizes, transport edges, busChannels and the masks changing mid-note, solo/allNotesOff/panic)
//  and asserts the output/channel/stuck-note invariants after every stop and at the end.

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
    struct Ev { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8; let win: Int; var lane = -1 }
    var events: [Ev] = []
    var win = 0
    private var pendingLane = -1
    func markLane(_ lane: Int) { pendingLane = lane }                  // HOCKET: which lane struck the note-on that follows (lane isolation, §12 test 16)
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        // Treat a 0x90 with vel 0 as an off (running-status off), as hosts do.
        var st = b0 & 0xF0
        if st == 0x90 && b2 == 0 { st = 0x80 }
        events.append(Ev(sample: sampleTime, cable: cable, status: st, chan: b0 & 0x0F, note: b1, vel: b2, win: win, lane: st == 0x90 ? pendingLane : -1))
    }
}

final class PortsStressTests: XCTestCase {

    // HOCKET ferry (2026-10-27) §12 test 1 → re-baselined for CARD BACKS (2026-10-28): a fingerprint of EVERY message the 600 + 600 seeded sessions send (the draws now include random part→output masks, so the old nine-output
    // fingerprints are not comparable). With no hocket rule in the document (these seeds draw none) the engine must stay byte-identical from here on — including the raw-gate seeds, where legato runs on every part, which the factory-preset golden never reaches.
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
    /// CARD BACKS: each part's routing mask drawn at random — mostly its lane's own output (nil), sometimes any subset of A–D, sometimes none (a part that sounds nowhere).
    private func rRouting(_ g: inout SM64, _ l: EuclidLine) -> EuclidLine {
        var m = l
        func mask(_ g: inout SM64) -> UInt8? { [nil, nil, UInt8.random(in: 0...15, using: &g), UInt8.random(in: 1...15, using: &g), 0].randomElement(using: &g)! }
        m.riffOutMask = mask(&g); m.notesOutMask = mask(&g)
        return m
    }
    /// CARD BACKS v2: each part's out-transpose drawn at random from its own stream — mostly 0 / nil, often a few steps either way, sometimes the extremes — and the scene rebuilt the way an edit publishes it.
    /// `zeroed`: draw the very same values from the stream but store none of them — the control run the pitch-sensitivity test compares against.
    private func retranspose(_ st: inout PluginState, _ h: inout SM64, zeroed: Bool = false) {
        func t(_ h: inout SM64) -> Int? { let v = [nil, 0, Int.random(in: -7...7, using: &h), Int.random(in: -3...3, using: &h), 7, -7].randomElement(using: &h)!; return zeroed ? nil : v }
        let ls = (st.euclideousLines ?? []).map { l -> EuclidLine in var m = l; m.riffOutTranspose = t(&h); m.notesOutTranspose = t(&h); return m }
        st.euclideousLines = ls
        let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                          soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
    }
    private func rDoc(_ g: inout SM64, lanes: [EuclidLine]? = nil, rawGates: Bool = false, randomRouting: Bool = true) -> (PluginState, NotePool) {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        var raw = lanes ?? (0..<4).map { _ in rLine(&g) }
        if lanes == nil && randomRouting { raw = raw.map { rRouting(&g, $0) } }
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
        // busChannels: the 4-form (one per output), a nine-ports 8-form, out-of-range, 0, short, and the default.
        switch Int.random(in: 0...4, using: &g) {
        case 0: st.busChannels = (0..<8).map { _ in Int.random(in: 1...16, using: &g) }   // a nine-ports document
        case 1: st.busChannels = (0..<4).map { _ in Int.random(in: 1...16, using: &g) }
        case 2: st.busChannels = (0..<4).map { _ in Int.random(in: 0...99, using: &g) }   // out-of-range / 0
        case 3: st.busChannels = [UInt8.random(in: 0...20, using: &g)].map { _ in Int.random(in: 1...16, using: &g) }   // short
        default: st.busChannels = nil                                                     // default 1...4
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
        // union check: multiset of (sample,note,vel,chan) of NOTE-ONs for outputs 1..4 vs ALL (0).
        // Only ONs form an exact union — offs collapse/shift on ALL by the §7 collision refcount +
        // restrike policy (a restrike-off fires whenever refcount>0), so an off-union would false-fail.
        var portMS: [String: Int] = [:], allMS: [String: Int] = [:]
        func msk(_ ev: TaggedEmitter.Ev) -> String { "\(ev.sample)/\(ev.note)/\(ev.vel)/\(ev.chan)" }

        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            // (b) no orphan off: balance must never go negative
            let k = key(ev.cable, ev.chan, ev.note)
            if ev.status == 0x90 {
                bal[k, default: 0] += 1
                // (e) per-output channel stamp at note-on: cable c on-channel == expected output c-1 channel THIS window
                if ev.cable >= 1 && ev.cable <= 4 {
                    let want = (winChans[ev.win][Int(ev.cable) - 1] &- 1) & 15
                    if ev.chan != want {
                        return "seed \(seed): cable \(ev.cable) note-ON ch \(ev.chan) != expected output channel \(want) (win \(ev.win))"
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
                else if ev.cable <= 4 { portMS[msk(ev), default: 0] += 1 }
            }
        }
        // (a) end-of-run: nothing left sounding
        for (k, v) in bal where v != 0 {
            let c = (k / 128) / 16, ch = (k / 128) % 16, n = k % 128
            return "seed \(seed): STUCK note — cable \(c) ch \(ch) note \(n) balance \(v) at end"
        }
        // (d) ALL == union of the four outputs (notes only). Skip if the voice table ever filled (own may open, all may not).
        if portMS != allMS {
            // surface the first discrepancy
            let onlyPort = portMS.filter { allMS[$0.key] != $0.value }.keys.sorted().first
            let onlyAll = allMS.filter { portMS[$0.key] != $0.value }.keys.sorted().first
            return "seed \(seed): ALL != union of outputs — output-only \(onlyPort ?? "-") / all-only \(onlyAll ?? "-")"
        }
        return nil
    }

    /// CARD BACKS §13 test 9 — the roll feed against the wire, over a whole random session. Every note-on on an output has a record naming that output at the same beat and pitch (the wire may carry FEWER than the records — the flood
    /// governor and a full voice table drop strikes, a part routed nowhere has none — never more), every record is well-formed, and after the stop nothing is left open in the model.
    private func rollAnalysis(_ e: TaggedEmitter, _ rolls: [NoteRollRecord], _ params: [(beat: Double, ts: Double)], _ tempos: [Double], sr: Double, seed: UInt64) -> String? {
        var fed: [String: Int] = [:]
        for r in rolls {
            if r.part > 7 || r.pitch > 127 || r.flags & 0xC0 != 0 { return "seed \(seed): a malformed roll record \(r)" }
            rollRecordsSeen += 1
            if r.isEnd { continue }
            if r.isSilent { rollSilentSeen += 1 }
            for o in 0..<4 where r.outs & (1 << UInt8(o)) != 0 { fed["\(o)/\(r.pitch)/\(Int((r.onBeat * 1e6).rounded()))", default: 0] += 1 }
        }
        var wire: [String: Int] = [:]
        for ev in e.events where ev.status == 0x90 && ev.cable >= 1 && ev.cable <= 4 {
            let w = params[ev.win]
            let beat = w.beat + Double(ev.sample - Int64(w.ts)) * tempos[ev.win] / 60.0 / sr
            wire["\(Int(ev.cable) - 1)/\(ev.note)/\(Int((beat * 1e6).rounded()))", default: 0] += 1
            rollWireChecked += 1
        }
        for (k, n) in wire where (fed[k] ?? 0) < n {
            // an event within a rounding step of the key (the beat is a Double sum): accept a neighbour
            let parts = k.split(separator: "/"); let o = parts[0], p = parts[1], b = Int(parts[2])!
            if (fed["\(o)/\(p)/\(b - 1)", default: 0] + fed["\(o)/\(p)/\(b + 1)", default: 0]) >= n - (fed[k] ?? 0) { continue }
            return "seed \(seed): \(n) note-on(s) on output \(Int(o)! + 1) for note \(p) at beat \(Double(b) / 1e6) but only \(fed[k] ?? 0) roll record(s)"
        }
        var m = NoteRollModel(); m.ingest(rolls)
        if m.openCount != 0 {
            var detail = ""
            for (pi, part) in m.parts.enumerated() { for n in part where n.endBeat == nil {
                detail += " [part \(pi) pitch \(n.pitch) on \(n.onBeat) outs \(n.outs) vel \(n.velocity)]"
                for r in rolls where r.part == UInt8(pi) && r.pitch == n.pitch && abs(r.onBeat - n.onBeat) < 1e-3 { detail += " rec(flags \(r.flags) len \(r.length) onBeat \(r.onBeat))" }
            } }
            return "seed \(seed): \(m.openCount) note(s) left open in the roll after the stop:\(detail)"
        }
        return nil
    }

    /// Drive one seeded session: many windows with mid-stream mutation, return a failure message or nil.
    /// Coverage for the roll-feed check (CARD BACKS §13 test 9): records seen, of them routed nowhere, and the notes the wire carried that the feed named.
    private var rollRecordsSeen = 0, rollSilentSeen = 0, rollWireChecked = 0
    private func runSession(seed: UInt64, windows: Int, rawGates: Bool = false, outTranspose: Bool = false, zeroedTranspose: Bool = false) -> String? {
        var g = SM64(seed)
        var h = SM64(seed ^ 0x0A7C_0FFE_E000)      // CARD BACKS v2: the out-transposes draw from their OWN stream, so the pinned fingerprints (no out-transpose) stay exactly what they were
        let router = Router()
        var rolls: [NoteRollRecord] = [], winParams: [(beat: Double, ts: Double)] = []
        var diag = KernelDiag()
        let e = TaggedEmitter()
        var (st, pool) = rDoc(&g, rawGates: rawGates)
        if outTranspose { retranspose(&st, &h, zeroed: zeroedTranspose) }
        var box = SnapshotBuilder.build(from: st)
        let sr = 48_000.0
        var tempo = Double([90, 120, 140].randomElement(using: &g)!)
        var beat = 0.0, ts = 0.0
        var playing = true
        var wasPlaying = true
        var winChans: [[UInt8]] = []
        var winTempos: [Double] = []
        var stopWins = Set<Int>()
        var maxActive = 0

        for w in 0..<windows {
            e.win = w
            // mutate the document / transport between windows
            if Int.random(in: 0...3, using: &g) == 0 { (st, _) = rDoc(&g, rawGates: rawGates); if outTranspose { retranspose(&st, &h, zeroed: zeroedTranspose) }; box = SnapshotBuilder.build(from: st) }   // whole new doc
            if outTranspose, h.next() % 3 == 0 { retranspose(&st, &h, zeroed: zeroedTranspose); box = SnapshotBuilder.build(from: st) }   // CARD BACKS v2: a PITCH pad dragged while notes sound
            if Int.random(in: 0...2, using: &g) == 0 {   // busChannels change mid-note
                switch Int.random(in: 0...3, using: &g) {
                case 0: st.busChannels = (0..<8).map { _ in Int.random(in: 1...16, using: &g) }
                case 1: let c = Int.random(in: 1...16, using: &g); st.busChannels = [c, c, c, c]   // every output the same channel
                case 2: st.busChannels = (0..<4).map { _ in Int.random(in: 1...16, using: &g) }
                default: st.busChannels = (0..<4).map { _ in Int.random(in: 0...99, using: &g) }
                }
                box = SnapshotBuilder.build(from: st)
            }
            if Int.random(in: 0...2, using: &g) == 0 {   // CARD BACKS: the part→output masks change mid-note (a jack tapped while notes sound): nothing may strand, move or double
                let ls = (st.euclideousLines ?? []).map { rRouting(&g, $0) }
                st.euclideousLines = ls
                let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                                  soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
                st.scenes = [FourfoldCompose.scene(input)]
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
            winParams.append((beat, ts)); winTempos.append(tempo)
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo,
                           sampleRate: sr, timestampSample: ts, frameCount: frames, laneMask: laneMask,
                           panic: panic, euclideousAllNotesOff: allOff, euclideousSoloLive: liveSolo,
                           out: e, diag: &diag)
            rolls += router.rollRing.drain()
            maxActive = max(maxActive, diag.activeVoiceCount)
            if !playing && wasPlaying { stopWins.insert(w) }   // this window carried the stop edge → flush
            beat += Double(frames) * tempo / 60.0 / sr
            ts += Double(frames)
        }
        // final hard stop: a playing→stopped edge must flush everything.
        e.win = windows
        winChans.append(box.busChannels)
        winParams.append((beat, ts)); winTempos.append(tempo)
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo,
                       sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        rolls += router.rollRing.drain()
        stopWins.insert(windows)
        if let msg = rollAnalysis(e, rolls, winParams, winTempos, sr: sr, seed: seed) { return msg }

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
            let port = UInt8(lane + 1)   // CARD BACKS: both of a lane's parts leave on its own output by default
            XCTAssertFalse(e.events.filter { $0.cable == port && $0.status == 0x90 }.isEmpty, "lane \(lane + 1) \(notes ? "notes" : "riff") legato sounds on cable \(port)")
            var bal: [Int: Int] = [:]
            for ev in e.events where ev.status == 0x90 || ev.status == 0x80 { bal[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note), default: 0] += ev.status == 0x90 ? 1 : -1 }
            XCTAssertTrue(bal.values.allSatisfy { $0 == 0 }, "lane \(lane + 1) \(notes ? "notes" : "riff") legato leaves nothing sounding")
            XCTAssertTrue(e.events.filter { $0.cable >= 1 && $0.cable <= 4 && $0.cable != port }.isEmpty, "…and nothing leaks onto another output")
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
        XCTAssertGreaterThan(rollRecordsSeen, 800, "the roll check must actually see notes (\(rollRecordsSeen) records)")
        XCTAssertGreaterThan(rollSilentSeen, 150, "…including parts routed nowhere (\(rollSilentSeen))")
        XCTAssertGreaterThan(rollWireChecked, 600, "…and match the wire (\(rollWireChecked) note-ons)")
        XCTAssertEqual(fingerprint, Self.fuzzFingerprint, "CAPTURE fuzzFingerprint = \(fingerprint) — the 600 seeded sessions' message streams must be bit-identical with no hocket rule")
    }
    private static let fuzzFingerprint: UInt64 = 5971859914748538723
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
    private static let fuzzFingerprintRaw: UInt64 = 10435385204888038160

    // CARD BACKS v2 (2026-10-28): out-transposes drawn at random AND changing mid-note — nothing strands, no orphan off, each message on its output's channel, ALL = the union of the outputs, the roll equals the wire.
    func testOutTransposeSessionsHoldEveryInvariant() {
        for s in 1...300 { if let msg = runSession(seed: UInt64(s) &+ 200_000, windows: 24, outTranspose: true) { XCTFail(msg); return } }
    }
    /// The invariant fuzzes above pass whether or not a shift ever reaches the wire (mutation-tested by the 2026-10-28 review: with `outShift` disabled they stayed green). This one compares each session with the SAME session whose
    /// out-transposes were drawn but not stored: the two must differ on the wire in most seeds, or the shifts never arrive.
    func testOutTransposeSessionsReallyChangeTheNotesOnTheWire() {
        var differing = 0, total = 0
        for s in 1...120 {
            let seed = UInt64(s) &+ 400_000
            XCTAssertNil(runSession(seed: seed, windows: 24, outTranspose: true)); let shifted = lastSessionHash
            XCTAssertNil(runSession(seed: seed, windows: 24, outTranspose: true, zeroedTranspose: true)); let control = lastSessionHash
            total += 1; if shifted != control { differing += 1 }
        }
        XCTAssertGreaterThan(differing, total / 6, "only \(differing) of \(total) sessions sounded different with out-transposes on — the shifts are not reaching the wire")
    }
    func testOutTransposeSessionsAtGate100() {
        for s in 1...300 { if let msg = runSession(seed: UInt64(s) &+ 300_000, windows: 24, rawGates: true, outTranspose: true) { XCTFail(msg); return } }
    }

    // Lane isolation: with every part on its lane's own output, only lane k emits on cable k+1; the other outputs stay silent.
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
            var (st, pool) = rDoc(&gg, lanes: lines, randomRouting: false)
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
            for ev in e.events where ev.cable >= 1 && ev.cable <= 4 {
                let laneOfCable = Int(ev.cable) - 1
                if laneOfCable != live {
                    XCTFail("seed \(s): disabled lane \(laneOfCable) emitted on cable \(ev.cable) (only lane \(live) live)")
                    return
                }
            }
        }
    }

    // CARD BACKS test 3: a part leaves on exactly the outputs its mask names. A lane with only its riff on emits only on the riff mask's outputs; with only its notes on, only on the notes mask's; a part routed nowhere makes no
    // sound on any output (the other lanes are off). Both parts on: the union of the two masks, nothing outside it.
    func testEachPartLeavesOnExactlyTheOutputsItsMaskNames() {
        var sawSilent = 0, sawMulti = 0, sawExact = 0
        for s in 1...800 {
            var g = SM64(UInt64(s) &* 0x55AA55AA)
            let which = Int.random(in: 0...2, using: &g)                       // 0 riff only, 1 notes only, 2 both
            let live = Int.random(in: 0...3, using: &g)
            var l = EuclidLine()
            l.enabled = true; l.pulses = 8; l.steps = 8
            l.riffOn = which != 1; l.useRiff = which != 1
            if which == 0 { l.litNotes = 0; l.topLit = false; l.top2Lit = false }
            else { l.litNotes = 0b0000_0011; l.notesWhen = 0b11; l.notesPlayAs = .chord }
            func mask(_ g: inout SM64) -> UInt8? { [nil, UInt8.random(in: 0...15, using: &g), UInt8.random(in: 1...15, using: &g), 0].randomElement(using: &g)! }
            let riffMask = mask(&g), notesMask = mask(&g)
            func run(routed: Bool) -> [TaggedEmitter.Ev] {
                var x = l
                if routed { x.riffOutMask = riffMask; x.notesOutMask = notesMask }
                var lines = (0..<4).map { _ -> EuclidLine in var o = EuclidLine(); o.enabled = false; return o }
                lines[live] = x
                var gg = SM64(UInt64(s))
                var (st, pool) = rDoc(&gg, lanes: lines, randomRouting: false)
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
                return e.events
            }
            let ev = run(routed: true), reference = run(routed: false)
            var probe = l; probe.riffOutMask = riffMask; probe.notesOutMask = notesMask
            let rm = probe.riffOutMaskResolved(lane: live), nm = probe.notesOutMaskResolved(lane: live)
            let allowed: UInt8 = which == 0 ? rm : which == 1 ? nm : rm | nm
            let used = ev.filter { $0.cable >= 1 && $0.cable <= 4 && $0.status == 0x90 }.reduce(UInt8(0)) { $0 | (UInt8(1) << ($1.cable - 1)) }
            if used & ~allowed != 0 { XCTFail("seed \(s): the lane emitted on outputs \(used) outside its mask \(allowed) (riff \(rm), notes \(nm), mode \(which))"); return }
            // a single part that sounds at all (its unrouted reference did) sounds on EVERY output of its mask; two parts only have to stay inside the union (either may be silent by the document)
            let refSounded = reference.contains { $0.status == 0x90 }
            if which != 2 && refSounded && used != allowed { XCTFail("seed \(s): the mask \(allowed) names outputs the part never sounded on (used \(used), mode \(which))"); return }
            if which != 2 && refSounded && allowed != 0 { sawExact += 1 }
            if allowed == 0 { sawSilent += 1; XCTAssertTrue(ev.filter { $0.status == 0x90 }.isEmpty, "seed \(s): routed nowhere ⇒ no note-on on any cable, ALL included") }
            if allowed.nonzeroBitCount > 1 { sawMulti += 1 }
            let allOn = ev.filter { $0.cable == 0 && $0.status == 0x90 }.count, outOn = ev.filter { $0.cable >= 1 && $0.cable <= 4 && $0.status == 0x90 }.count
            if allOn != outOn { XCTFail("seed \(s): ALL carries \(allOn) note-ons but the outputs \(outOn)"); return }
            var bal: [Int: Int] = [:]
            for e in ev where e.status == 0x90 || e.status == 0x80 { bal[(Int(e.cable) * 16 + Int(e.chan)) * 128 + Int(e.note), default: 0] += e.status == 0x90 ? 1 : -1 }
            if !bal.values.allSatisfy({ $0 == 0 }) { XCTFail("seed \(s): a note left sounding"); return }
        }
        XCTAssertGreaterThan(sawSilent, 20, "the draws must include parts routed nowhere"); XCTAssertGreaterThan(sawMulti, 100, "…and parts routed to several outputs")
        XCTAssertGreaterThan(sawExact, 100, "…and single parts whose every output was checked")
    }

    // MARK: - HOCKET (ferry 2026-10-27) §12 test 16 — "a stress run cycling every setting of every rule during ties, ratchets, ROLL, RUN, GATE 100, LANES mutes and transport restarts leaves nothing sounding on any output"
    // Seeds are SEPARATE from the two fingerprinted fuzz runs above (they draw no rules and must stay byte-identical).

    private func rHocketRules(_ g: inout SM64) -> [HocketRule] {
        var pool = Array(1...8); pool.shuffle(using: &g)
        var rules: [HocketRule] = []
        for _ in 0..<Int.random(in: 0...4, using: &g) {
            var r = HocketRule()
            r.on = Int.random(in: 0...5, using: &g) != 0
            r.mode = Int.random(in: 0...2, using: &g) == 0 ? .swap : .pass
            let nm = Int.random(in: 1...3, using: &g), na = Int.random(in: 1...3, using: &g)
            r.main = Array(pool.prefix(nm)); pool.removeFirst(min(nm, pool.count))
            r.alt = Array(pool.prefix(na)); pool.removeFirst(min(na, pool.count))
            if let m = r.main.first, Int.random(in: 0...3, using: &g) == 0 { r.alt.append(m) }          // an output in both groups of its own rule
            r.unit = HocketUnit.allCases.randomElement(using: &g)!
            let small = Int.random(in: 0...2, using: &g) != 0                                  // mostly short cycles, so ALT turns come round often
            r.mainLen = small ? Int.random(in: 1...3, using: &g) : Int.random(in: 1...8, using: &g); r.altLen = small ? Int.random(in: 1...3, using: &g) : Int.random(in: 1...8, using: &g); r.offset = Int.random(in: 0...15, using: &g)
            r.several = Bool.random(using: &g) ? .together : .rotate
            r.countOn = Int.random(in: 0...3, using: &g)
            r.own = Bool.random(using: &g) ? .replace : .merge
            rules.append(r)
        }
        return HocketRuleSet(rules).rules
    }
    /// One edit of one setting of one rule (or a whole new set, or a delete) — every setting the pop-up has.
    private func editRules(_ rules: inout [HocketRule], _ g: inout SM64) {
        let what = Int.random(in: 0...13, using: &g)
        if what == 0 || rules.isEmpty { rules = rHocketRules(&g); return }
        let i = Int.random(in: 0..<rules.count, using: &g)
        var r = rules[i]
        switch what {
        case 1: r.on.toggle()
        case 2: r.mode = r.mode == .swap ? .pass : .swap
        case 3: if r.main.isEmpty { r.main = [Int.random(in: 1...8, using: &g)] } else { r.main.removeLast() }
        case 4: if r.alt.isEmpty { r.alt = [Int.random(in: 1...8, using: &g)] } else { r.alt.removeFirst() }
        case 5: r.unit = HocketUnit.allCases.randomElement(using: &g)!
        case 6: r.mainLen = Int.random(in: 1...8, using: &g)
        case 7: r.altLen = Int.random(in: 1...8, using: &g)
        case 8: r.offset = Int.random(in: 0...15, using: &g)
        case 9: r.several = r.several == .together ? .rotate : .together
        case 10: r.own = r.own == .replace ? .merge : .replace
        case 11: r.countOn = Int.random(in: 0...3, using: &g)
        case 12: rules.remove(at: i); return                                   // delete the rule
        default: r.main.shuffle(using: &g); r.alt.shuffle(using: &g)
        }
        rules[i] = r
        rules = HocketRuleSet(rules).rules
    }

    /// Coverage: how many note-ons left on ANOTHER lane's output (a passed line) and how many windows ran with a rule lit — so a fuzz that stopped exercising the feature would fail instead of passing quietly.
    private var hocketPassedNotes = 0, hocketLitWindows = 0, hocketSharedChannelRuns = 0
    /// A random lane that mostly PLAYS (so there are notes to pass): on, a real rhythm, riff and/or notes lit, mostly its own rhythm and pitches (LISTEN borrowing is still exercised now and then).
    private func rPlayingLane(_ g: inout SM64) -> EuclidLine {
        var l = rLine(&g)
        l.enabled = Int.random(in: 0...9, using: &g) == 0 ? false : nil
        l.pulses = max(2, l.pulses); l.steps = max(l.pulses, l.steps)
        if Int.random(in: 0...3, using: &g) != 0 { l.riffOn = true; l.useRiff = true }
        if Int.random(in: 0...3, using: &g) != 0 { l.notesOn = true; if l.litOrderResolved.count == 0 { l.litNotes = 0b0000_0011 } }
        if Int.random(in: 0...3, using: &g) != 0 { l.listenRhythm = .own; l.listenPitch = .own }
        l.patternMiss = nil
        return l
    }
    private func runHocketSession(seed: UInt64, windows: Int, rawGates: Bool) -> String? {
        var g = SM64(seed)
        let router = Router()
        var diag = KernelDiag()
        let e = TaggedEmitter()
        var (st, pool) = rDoc(&g, lanes: (0..<4).map { _ in rPlayingLane(&g) }, rawGates: rawGates)
        pool.reset(); for n in [48, 55, 60, 64, 67, 72] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        st.euclideousNoteSource = .midi
        let distinctChannels = Bool.random(using: &g)
        if distinctChannels { st.busChannels = Array((1...16).shuffled(using: &g).prefix(4)) }
        var rules = rHocketRules(&g)
        st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules)
        var box = SnapshotBuilder.build(from: st)
        let sr = 48_000.0
        var tempo = Double([120, 140, 160, 200].randomElement(using: &g)!)
        var beat = 0.0, ts = 0.0
        var playing = true
        var winChans: [[UInt8]] = [], winLit: [UInt8] = [], winStart: [Int64] = []
        func litMask(_ b: SnapshotBox) -> UInt8 { b.cells[Snap.euclideousRow].procs.first?.hocketRules.litBusMask ?? 0 }
        for w in 0..<windows {
            e.win = w
            if Int.random(in: 0...2, using: &g) == 0 {            // a rule edit lands between two windows, with notes sounding
                editRules(&rules, &g)
                st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules)
                box = SnapshotBuilder.build(from: st)
            }
            if Int.random(in: 0...9, using: &g) == 0 {            // a whole new set of LANES mutes / lanes, the rules kept
                let keep = st.hocketRules; let ch = st.busChannels
                (st, _) = rDoc(&g, lanes: (0..<4).map { _ in rPlayingLane(&g) }, rawGates: rawGates, randomRouting: false); st.euclideousNoteSource = .midi; st.hocketRules = keep; st.busChannels = ch
                box = SnapshotBuilder.build(from: st)
            }
            if Int.random(in: 0...4, using: &g) == 0 { tempo = Double([60, 90, 120, 160, 200].randomElement(using: &g)!) }
            if Int.random(in: 0...7, using: &g) == 0 {
                pool.reset()
                for _ in 0..<Int.random(in: 1...5, using: &g) { pool.noteOn(UInt8.random(in: 36...84, using: &g), velocity: UInt8.random(in: 20...127, using: &g), channel: 0) }
            }
            let frames = UInt32([512, 1024, 2048, 4096, 8192].randomElement(using: &g)!)
            if Int.random(in: 0...11, using: &g) == 0 { playing.toggle() }                        // transport restarts
            if Int.random(in: 0...12, using: &g) == 0 { beat += Double.random(in: -8...32, using: &g) }   // seek / loop jump
            winChans.append(box.busChannels); winLit.append(litMask(box)); winStart.append(Int64(ts))
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames,
                           euclideousSoloLive: UInt16(st.euclideousSoloMaskResolved), out: e, diag: &diag)
            beat += Double(frames) * tempo / 60.0 / sr
            ts += Double(frames)
        }
        e.win = windows
        winChans.append(box.busChannels); winLit.append(litMask(box)); winStart.append(Int64(ts))
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)

        // ---- invariants ----
        hocketLitWindows += winLit.filter { $0 != 0 }.count
        if !distinctChannels { hocketSharedChannelRuns += 1 }
        var bal: [Int: Int] = [:]
        var portMS: [String: Int] = [:], allMS: [String: Int] = [:]
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            if ev.status == 0x90 {
                bal[k, default: 0] += 1
                if ev.cable >= 1 && ev.cable <= 4 {
                    let want = (winChans[ev.win][Int(ev.cable) - 1] &- 1) & 15
                    if ev.chan != want { return "seed \(seed): cable \(ev.cable) note-ON ch \(ev.chan) != the output's channel \(want) (win \(ev.win))" }
                    // lane isolation: a lane's note leaves only on its own output, unless a LIT rule says a part of the destination lane takes passed notes
                    let portLane = Int(ev.cable) - 1
                    if ev.lane >= 0 && ev.lane != portLane { hocketPassedNotes += 1 }
                    // A deferred strike (a ratchet repeat, a ROLL / RUN note) of a hit struck BEFORE a rule edit keeps the routing it began with (§6.4, §7.4 — "only notes struck after the change follow the new routing"), so it
                    // may land on an output the new rules no longer name: an output lit in any window of the previous 4 seconds is allowed. A strike by the new rules never reaches an output no rule has ever named.
                    var litRecently = false
                    for j in 0...ev.win where winLit[j] & (UInt8(3) << UInt8(2 * (ev.cable - 1))) != 0 && winStart[j] >= ev.sample - 4 * 48_000 { litRecently = true; break }
                    if ev.lane >= 0 && ev.lane != portLane && !litRecently {
                        return "seed \(seed): lane \(ev.lane) struck a note on lane \(portLane)'s output (cable \(ev.cable)) with no lit rule naming it (win \(ev.win))"
                    }
                }
                let key = "\(ev.sample)/\(ev.note)/\(ev.vel)/\(ev.chan)"
                if ev.cable == 0 { allMS[key, default: 0] += 1 } else if ev.cable <= 4 { portMS[key, default: 0] += 1 }
            } else {
                bal[k, default: 0] -= 1
                if bal[k]! < 0 { return "seed \(seed): ORPHAN note-off cable \(ev.cable) ch \(ev.chan) note \(ev.note) (win \(ev.win))" }
            }
        }
        for (k, v) in bal where v != 0 { return "seed \(seed): STUCK note — cable \((k / 128) / 16) ch \((k / 128) % 16) note \(k % 128) balance \(v) at the end" }
        if distinctChannels && portMS != allMS {
            let a = portMS.filter { allMS[$0.key] != $0.value }.keys.sorted().first, b = allMS.filter { portMS[$0.key] != $0.value }.keys.sorted().first
            return "seed \(seed): ALL != the union of the outputs (distinct channels) — output-only \(a ?? "-") / all-only \(b ?? "-")"
        }
        return nil
    }

    func testHocketRulesChangingMidRunNeverStrandANoteOrLeakAcrossLanes() {
        for s in 1...300 { if let msg = runHocketSession(seed: UInt64(s) &+ 500_000, windows: 120, rawGates: false) { XCTFail(msg); return } }
        XCTAssertGreaterThan(hocketPassedNotes, 200, "the fuzz must actually pass lines between lanes (\(hocketPassedNotes) passed notes)")
        XCTAssertGreaterThan(hocketLitWindows, 1000, "…with rules lit (\(hocketLitWindows) windows)")
        XCTAssertGreaterThan(hocketSharedChannelRuns, 50, "…and some sessions share channels across outputs")
    }
    func testHocketRulesChangingMidRunAtGate100() {
        for s in 1...300 { if let msg = runHocketSession(seed: UInt64(s) &+ 700_000, windows: 120, rawGates: true) { XCTFail(msg); return } }
        XCTAssertGreaterThan(hocketPassedNotes, 20, "the raw-gate fuzz passes lines between lanes too (\(hocketPassedNotes))")
    }
}

// MARK: - lane isolation under a lit rule (adversarial review 2026-10-27)
extension PortsStressTests {
    /// A lit rule on lanes 1–2 must leave lanes 3–4's outputs byte-identical (the clock pre-pass runs the reference lanes twice a window; ALL joins only while a rule is lit, and these channels are distinct).
    func testARuleOnLanes1And2LeavesLanes3And4OutputsByteIdentical() {
        var diverged: [String] = [], litRuns = 0
        for seed in 1...160 {
            var g = SM64(UInt64(seed) &* 0x9E3779B97F4A7C15)
            var (st, pool) = rDoc(&g, lanes: (0..<4).map { _ in rPlayingLane(&g) }, rawGates: seed % 2 == 0, randomRouting: false)
            pool.reset(); for n in [48, 55, 60, 64, 67, 72] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
            st.euclideousNoteSource = .midi
            st.busChannels = [1, 2, 3, 4]
            var r = HocketRule()
            switch seed % 4 {
            case 0: r.main = [1]; r.alt = [3]; r.unit = .hits; r.mainLen = 3; r.altLen = 1
            case 1: r.mode = .pass; r.main = [2]; r.alt = [4]; r.unit = .bars
            case 2: r.mode = .pass; r.main = [1, 2]; r.alt = [3, 4]; r.several = .rotate; r.unit = .passes; r.mainLen = 2
            default: r.main = [2, 4]; r.alt = [1]; r.unit = .hits; r.countOn = 1; r.several = .rotate
            }
            var baseState = st; baseState.hocketRules = nil
            var ruleState = st; ruleState.hocketRules = HocketRuleSet([r]); ruleState.busChannels = st.busChannels
            func run(_ s: PluginState) -> [TaggedEmitter.Ev] {
                var gg = SM64(UInt64(seed) &* 77)
                let box = SnapshotBuilder.build(from: s)
                let router = Router(); var diag = KernelDiag(); let e = TaggedEmitter()
                var beat = 0.0, ts = 0.0
                for w in 0..<60 {
                    e.win = w
                    let frames = UInt32([512, 1024, 2048, 4096].randomElement(using: &gg)!)
                    router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 140, sampleRate: 48_000, timestampSample: ts, frameCount: frames,
                                   euclideousSoloLive: UInt16(s.euclideousSoloMaskResolved), out: e, diag: &diag)
                    beat += Double(frames) * 140.0 / 60.0 / 48_000; ts += Double(frames)
                }
                return e.events
            }
            let a = run(baseState), b = run(ruleState)
            func slice(_ evs: [TaggedEmitter.Ev]) -> [String] {
                evs.filter { ($0.status == 0x90 || $0.status == 0x80) && (($0.cable == 3 || $0.cable == 4) || ($0.cable == 0 && ($0.chan == 2 || $0.chan == 3))) }.map { "\($0.sample)/\($0.cable)/\($0.status)/\($0.chan)/\($0.note)/\($0.vel)" }
            }
            let sa = slice(a).sorted(), sb = slice(b).sorted()          // as sets: which voice slot a note lands in (so the order a window's offs come out in) shifts when another lane's notes are routed
            litRuns += 1
            if sa != sb { diverged.append("seed \(seed) (rule kind \(seed % 4)): \(sa.count) vs \(sb.count) events on lanes 3–4's outputs") }
        }
        XCTAssertTrue(diverged.isEmpty, "a rule on lanes 1–2 changed lanes 3–4's outputs: \(diverged.prefix(5))")
    }
}

// MARK: - ADVERSARIAL REVIEW of CARD BACKS (2026-10-28) — HOCKET × non-default routing masks
// The shipped HOCKET fuzz draws `rDoc(lanes:)`, which never randomises masks, and HocketRouterTests render through a two-pass adapter (riff parts only, then notes parts) — so a lit rule on parts that share outputs,
// reach several outputs or reach none is exercised nowhere. This runs the HOCKET session with random masks drawn at the start AND changed mid-run, and also checks the roll feed against the wire.
extension PortsStressTests {
    private func runHocketMaskSession(seed: UInt64, windows: Int, rawGates: Bool, sameChannels: Bool = false) -> String? {
        var g = SM64(seed)
        let router = Router()
        var diag = KernelDiag()
        let e = TaggedEmitter()
        var lanes = (0..<4).map { _ in rRouting(&g, rPlayingLane(&g)) }
        var (st, pool) = rDoc(&g, lanes: lanes, rawGates: rawGates)
        pool.reset(); for n in [48, 55, 60, 64, 67, 72] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        st.euclideousNoteSource = .midi
        let distinctChannels = !sameChannels && Bool.random(using: &g)
        if distinctChannels { st.busChannels = Array((1...16).shuffled(using: &g).prefix(4)) }
        var rules = rHocketRules(&g)
        st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules)
        var box = SnapshotBuilder.build(from: st)
        let sr = 48_000.0
        var tempo = Double([120, 140, 160, 200].randomElement(using: &g)!)
        var beat = 0.0, ts = 0.0
        var playing = true
        var winChans: [[UInt8]] = [], winParams: [(beat: Double, ts: Double)] = [], winTempos: [Double] = []
        var rolls: [NoteRollRecord] = []
        var maxActive = 0
        func rebuild() {
            st.euclideousLines = lanes
            let ls = rawGates ? lanes : st.euclideousLinesResolved
            st.euclideousLines = ls
            let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                              soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
            st.scenes = [FourfoldCompose.scene(input)]
            box = SnapshotBuilder.build(from: st)
        }
        rebuild()
        for w in 0..<windows {
            e.win = w
            if Int.random(in: 0...2, using: &g) == 0 { editRules(&rules, &g); st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules); box = SnapshotBuilder.build(from: st) }
            if Int.random(in: 0...2, using: &g) == 0 { lanes = lanes.map { rRouting(&g, $0) }; rebuild() }          // masks change with notes sounding
            if Int.random(in: 0...12, using: &g) == 0 { lanes = (0..<4).map { _ in rRouting(&g, rPlayingLane(&g)) }; rebuild() }
            if Int.random(in: 0...4, using: &g) == 0 { tempo = Double([60, 90, 120, 160, 200].randomElement(using: &g)!) }
            if Int.random(in: 0...7, using: &g) == 0 {
                pool.reset()
                for _ in 0..<Int.random(in: 1...5, using: &g) { pool.noteOn(UInt8.random(in: 36...84, using: &g), velocity: UInt8.random(in: 20...127, using: &g), channel: 0) }
            }
            let frames = UInt32([256, 512, 1024, 2048, 4096, 8192].randomElement(using: &g)!)
            if Int.random(in: 0...11, using: &g) == 0 { playing.toggle() }
            if Int.random(in: 0...12, using: &g) == 0 { beat += Double.random(in: -8...32, using: &g) }
            let allOff = Int.random(in: 0...14, using: &g) == 0, panic = Int.random(in: 0...40, using: &g) == 0
            let live = Int.random(in: 0...5, using: &g) == 0 ? (0x100 | UInt16.random(in: 0...15, using: &g)) : UInt16(st.euclideousSoloMaskResolved)   // 0x100 = "the page has spoken": without it the router ignores the live word (the shipped fuzz never sets it)
            winChans.append(box.busChannels); winParams.append((beat, ts)); winTempos.append(tempo)
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames,
                           panic: panic, euclideousAllNotesOff: allOff, euclideousSoloLive: live, out: e, diag: &diag)
            rolls += router.rollRing.drain()
            maxActive = max(maxActive, diag.activeVoiceCount)
            beat += Double(frames) * tempo / 60.0 / sr
            ts += Double(frames)
        }
        e.win = windows
        winChans.append(box.busChannels); winParams.append((beat, ts)); winTempos.append(tempo)
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        rolls += router.rollRing.drain()
        var bal: [Int: Int] = [:]
        var portMS: [String: Int] = [:], allMS: [String: Int] = [:]
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            if ev.status == 0x90 {
                bal[k, default: 0] += 1
                if ev.cable >= 1 && ev.cable <= 4 {
                    let want = (winChans[ev.win][Int(ev.cable) - 1] &- 1) & 15
                    if ev.chan != want { return "seed \(seed): cable \(ev.cable) note-ON ch \(ev.chan) != the output's channel \(want) (win \(ev.win))" }
                }
                let key = "\(ev.sample)/\(ev.note)/\(ev.vel)/\(ev.chan)"
                if ev.cable == 0 { allMS[key, default: 0] += 1 } else if ev.cable <= 4 { portMS[key, default: 0] += 1 }
            } else {
                bal[k, default: 0] -= 1
                if bal[k]! < 0 { return "seed \(seed): ORPHAN note-off cable \(ev.cable) ch \(ev.chan) note \(ev.note) (win \(ev.win))" }
            }
        }
        for (k, v) in bal where v != 0 { return "seed \(seed): STUCK note — cable \((k / 128) / 16) ch \((k / 128) % 16) note \(k % 128) balance \(v) at the end" }
        if distinctChannels && portMS != allMS && maxActive < 120 {
            let a = portMS.filter { allMS[$0.key] != $0.value }.keys.sorted().first, b = allMS.filter { portMS[$0.key] != $0.value }.keys.sorted().first
            return "seed \(seed): ALL != the union of the outputs (distinct channels, maxActive \(maxActive)) — output-only \(a ?? "-") / all-only \(b ?? "-")"
        }
        var m = NoteRollModel(); m.ingest(rolls)
        if m.openCount != 0 { return "seed \(seed): \(m.openCount) note(s) left open in the roll after the stop" }
        return nil
    }
    func testReviewHocketWithRoutingMasksNeverStrandsANote() {
        var fails: [String] = []
        for s in 1...400 { if let msg = runHocketMaskSession(seed: UInt64(s) &+ 910_000, windows: 100, rawGates: false) { fails.append(msg); if fails.count >= 6 { break } } }
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "\n"))
    }
    func testReviewHocketWithRoutingMasksAtGate100() {
        var fails: [String] = []
        for s in 1...400 { if let msg = runHocketMaskSession(seed: UInt64(s) &+ 920_000, windows: 100, rawGates: true) { fails.append(msg); if fails.count >= 6 { break } } }
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "\n"))
    }
    /// The same session, 3,000 more seeds (mixed gates and channel plans) — the long run behind "nothing found".
    func testReviewHocketWithRoutingMasksLongRun() {
        var fails: [String] = []
        for s in 1...3000 { if let msg = runHocketMaskSession(seed: UInt64(s) &+ 940_000, windows: 80, rawGates: s % 3 == 0, sameChannels: s % 5 == 0) { fails.append(msg); if fails.count >= 6 { break } } }
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "\n"))
    }
    func testReviewHocketWithRoutingMasksOnSharedChannels() {
        var fails: [String] = []
        for s in 1...400 { if let msg = runHocketMaskSession(seed: UInt64(s) &+ 930_000, windows: 100, rawGates: s % 2 == 0, sameChannels: true) { fails.append(msg); if fails.count >= 6 { break } } }
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "\n"))
    }
}
