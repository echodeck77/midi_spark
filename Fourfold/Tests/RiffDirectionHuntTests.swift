//  RiffDirectionHuntTests.swift — BUG HUNT (2026-11-06), the RIFF WALK's DIRECTION (RiffDir: FWD / REV / PENDULUM / PING-PONG), engine AND mirrors.
//  The real Router is driven offline and its note-ons are compared with an INDEPENDENT brute-force walk model: the walk is built as an explicit list of positions (a bounce sequence), never through `riffStepAt` /
//  `euclideousRiffColumn`, so a bug in the shared formula cannot hide behind the engine and its displays agreeing with each other. One lane, a held 8-note pool (rank r = pool[r-1]), 8 columns written with
//  distinct ranks (a column is identified by its pitch) and some rests, one step a beat (24 000 samples at 120 BPM / 48 kHz).

import XCTest

private final class HuntEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 && $0.cable == 1 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 && $0.cable == 1 } }
}

/// A tiny SplitMix64 so every trial is reproducible from its index.
struct HuntRng {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 10_000) / 10_000 < p }
}

/// What one trial configures (everything the walk reads).
private struct Hunt {
    var dir: RiffDir = .forward
    var length = 8, stride = 1, shift = 0, every = 1
    var step = false                 // ADVANCE STEP (the walk counts steps) vs HIT
    var onRest: EuclidRiffOnRest = .skip
    var ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8]   // 0 = a rest column
    var hits: [Bool] = [true, true, true, true]   // the rhythm, one entry per step
    var invert = false
    var rdir: EuclidDir = .fwd       // the RHYTHM lane's own direction (a PING-PONG rhythm gives the walk 'two legs')
    var melodyPasses: Int? = nil     // MELODY restart every n passes (a pass = one lap of the rhythm); nil = FREE
    var gate = 0.5
}

private let huntPool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
private let beatSamples: Int64 = 24_000

private func gcdI(_ a: Int, _ b: Int) -> Int { var x = abs(a), y = abs(b); while y != 0 { (x, y) = (y, x % y) }; return max(1, x) }

/// The walk as an explicit sequence of positions 0…L-1, straight from each direction's DEFINITION (not from `riffStepAt`).
func bounceSequence(_ dir: RiffDir, _ L: Int) -> [Int] {
    let up = Array(0..<L), down = Array((0..<L).reversed())
    switch dir {
    case .forward, .random, .drunk: return up
    case .reverse: return down
    case .pendulum: return L <= 2 ? up : up + Array((1...(L - 2)).reversed())          // bounce once at each end: 0…L-1, L-2…1
    case .pingpong: return up + down                                                      // each end sounds twice: 0…L-1, L-1…0
    }
}
/// The column the walk reads for an ordinal (ADVANCE EVERY applied).
private func modelColumn(_ h: Hunt, ordinal o: Int) -> Int {
    let seq = bounceSequence(h.dir, max(1, h.length))
    let w = o / max(1, h.every)
    let pos = seq[(w * h.stride) % seq.count]
    return (pos + h.shift) % 8
}
private func rankPitch(_ rank: Int, _ h: Hunt) -> UInt8? {
    guard rank >= 1 else { return nil }
    let r = h.invert ? 9 - rank : rank
    return huntPool[r - 1]
}

final class RiffDirectionHuntTests: XCTestCase {
    private var setAside = 0
    private func lane(_ h: Hunt) -> EuclidLine {
        let n = h.hits.count
        var l = EuclidLine(target: 0, pulses: max(1, h.hits.filter { $0 }.count), steps: n)
        l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi
        l.customHits = h.hits
        l.riffDir = h.dir; l.riffLength = h.length; l.riffStride = h.stride; l.riffRotate = h.shift; l.riffAdvanceEvery = h.every
        l.riffAdvanceStep = h.step; l.riffOnRest = h.onRest; l.riffInvert = h.invert
        l.direction = h.rdir; l.gate = h.gate
        if let m = h.melodyPasses { l.restartMelodyPasses = [UInt8(m)]; l.restartRhythmBars = [] }   // the rhythm chain stays FREE so a pass is one lap
        return l
    }
    private func state(_ h: Hunt) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: h.ranks)
        c.paramsA.euclidLines = [lane(h)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: false, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [], midiOctaves: .keep)
        st.euclideousSameNoteGuard = false
        return st
    }
    /// Drive the real Router; `swaps` replaces the document from the first window that STARTS at or after the given sample.
    private func run(_ st: PluginState, beats: Double, frames: UInt32 = 2048, swaps: [(sample: Int64, state: PluginState)] = []) -> HuntEmitter {
        let e = HuntEmitter(); let router = Router(); var diag = KernelDiag()
        var box = SnapshotBuilder.build(from: st)
        let tempo = 120.0, sr = 48_000.0
        let p = NotePool(); for n in huntPool { p.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        var pending = swaps
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            if let s = pending.first, Int64(ts) >= s.sample { box = SnapshotBuilder.build(from: s.state); pending.removeFirst() }
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    /// Does the rhythm strike at tick k (the pattern read in the lane's own direction; PING-PONG = a lap of 2n, each end sounding twice)?
    private func isHit(_ h: Hunt, _ k: Int) -> Bool {
        let n = h.hits.count
        switch h.rdir {
        case .fwd: return h.hits[k % n]
        case .bkw: return h.hits[n - 1 - (k % n)]
        case .pingpong: let t = k % (2 * n); return h.hits[t < n ? t : 2 * n - 1 - t]
        }
    }
    /// The model's note-ons for ticks 0..<ticks under a (possibly switching) configuration: (tick, pitch, the note's length in beats).
    private func modelOns(_ configs: [(fromTick: Int, h: Hunt)], ticks: Int) -> [(tick: Int, note: UInt8, beats: Double)] {
        func cfg(at k: Int) -> Hunt { configs.last(where: { $0.fromTick <= k })!.h }
        let horizon = ticks + 90   // the TIE lookahead and the next-hit gap read ahead
        var hitTicks: [Int] = []
        for k in 0..<horizon where isHit(cfg(at: k), k) { hitTicks.append(k) }
        func origin(_ h: Hunt, _ k: Int) -> Int {
            guard let m = h.melodyPasses else { return 0 }
            let lap = h.rdir == .pingpong ? 2 * h.hits.count : h.hits.count
            return (k / (lap * m)) * lap * m
        }
        func ordinalAt(_ h: Hunt, _ k: Int) -> Int {
            let o = origin(h, k)
            return h.step ? k - o : hitTicks.filter { $0 >= o && $0 < k }.count
        }
        func columnAt(_ h: Hunt, _ k: Int) -> Int { modelColumn(h, ordinal: ordinalAt(h, k)) }
        var out: [(tick: Int, note: UInt8, beats: Double)] = []
        for (hi, k) in hitTicks.enumerated() where k < ticks {
            let h = cfg(at: k)
            let rank = h.ranks[columnAt(h, k)]
            let nextGap = hi + 1 < hitTicks.count ? Double(hitTicks[hi + 1] - k) : 1
            if let p = rankPitch(rank, h) {
                var beats = h.gate * nextGap
                if h.onRest == .tie {   // the note carries through every consecutive tied rest (bounded by the walk's period × EVERY hits, at most 64)
                    let L = max(1, h.length), D = bounceSequence(h.dir, L).count
                    let P = L == 1 ? 1 : D / gcdI(D, h.stride)
                    let bound = min(64, P * max(1, h.every))
                    var last = -1, j = hi + 1
                    while j < hitTicks.count, j - hi <= bound {
                        let k2 = hitTicks[j]
                        if h.melodyPasses != nil, origin(h, k2) != origin(h, k) { break }   // a melody restart always breaks the chain
                        if h.ranks[columnAt(h, k2)] >= 1 { break }
                        last = k2; j += 1
                    }
                    if last >= 0 { beats = nextGap + h.gate * Double(last - k) }
                }
                out.append((k, p, beats)); continue
            }
            if h.onRest == .repeatLast {
                // nearest EARLIER hit (in time) since the melody origin whose column, read now, is not a rest
                var j = hi - 1
                while j >= 0, hitTicks[j] >= origin(h, k) {
                    if let p = rankPitch(h.ranks[columnAt(h, hitTicks[j])], h) { out.append((k, p, h.gate * nextGap)); break }
                    j -= 1
                }
            }
        }
        return out
    }

    private func randomHunt(_ r: inout HuntRng, dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong], withRhythmDirs: Bool = false, withMelody: Bool = false) -> Hunt {
        var h = Hunt()
        h.dir = dirs[r.int(0...(dirs.count - 1))]
        h.length = r.int(1...8); h.stride = r.int(1...7); h.shift = r.int(0...7); h.every = r.int(1...4)
        h.step = r.bool(0.4)
        h.onRest = [.skip, .tie, .repeatLast][r.int(0...2)]
        var ranks = Array(1...8); for i in stride(from: 7, to: 0, by: -1) { ranks.swapAt(i, r.int(0...i)) }
        h.ranks = ranks.map { r.bool(0.3) ? 0 : $0 }
        let n = r.int(2...9)
        h.hits = (0..<n).map { _ in r.bool(0.65) }; if !h.hits.contains(true) { h.hits[r.int(0...(n - 1))] = true }
        h.invert = r.bool(0.25)
        if withRhythmDirs { h.rdir = [.fwd, .bkw, .pingpong][r.int(0...2)] }
        if withMelody, r.bool(0.4) { h.melodyPasses = r.int(1...3) }
        return h
    }
    /// The REPEAT + SHIFT defect (A2): REPEAT's early-out scans columns 0..<LEN, so with a SHIFT and no note in 0..<LEN the lookback answers "nothing to repeat". Trials that hit it are counted and set aside so the other trials can speak.
    private func hitsRepeatEarlyOutBug(_ h: Hunt) -> Bool {
        guard h.onRest == .repeatLast else { return false }
        let len = max(1, min(8, h.length))
        let unshiftedHasNote = (0..<len).contains { h.ranks[$0] >= 1 }
        let windowHasNote = (0..<len).contains { h.ranks[(h.shift + $0) % 8] >= 1 }
        return !unshiftedHasNote && windowHasNote
    }
    /// The TIE + ADV STEP + MELODY-restart defect (A3): the TIE lookahead ends a run at a melody restart by testing `advOrd == 0`, which under ADV STEP is only true when a hit lands exactly ON the restart tick.
    private func hitsStepTieRestartBug(_ h: Hunt) -> Bool { h.onRest == .tie && h.step && h.melodyPasses != nil }
    private func describe(_ h: Hunt) -> String {
        "rdir \(h.rdir) melody \(h.melodyPasses.map(String.init) ?? "free") dir \(h.dir) len \(h.length) stride \(h.stride) shift \(h.shift) every \(h.every) \(h.step ? "STEP" : "HIT") onRest \(h.onRest) ranks \(h.ranks) hits \(h.hits.map { $0 ? "x" : "." }.joined()) invert \(h.invert)"
    }
    private func tick(_ sample: Int64) -> Int { Int((sample + 12_000) / beatSamples) }

    /// Compare the engine's note-ons (and, with `lengths`, note-off times) of one trial with the model; returns a failure line or nil.
    private func check(_ tag: String, _ configs: [(fromTick: Int, h: Hunt)], swaps: [(sample: Int64, state: PluginState)] = [], beats: Double, lengths: Bool = false) -> String? {
        let h0 = configs[0].h
        if configs.contains(where: { hitsRepeatEarlyOutBug($0.h) }) { setAside += 1; return nil }   // the known REPEAT + SHIFT defect (A2) — set aside, counted
        let e = run(state(h0), beats: beats, swaps: swaps)
        let ticks = Int(beats) - 1
        let want = modelOns(configs, ticks: ticks)
        let got = e.ons.map { (tick: tick($0.sample), note: $0.note, sample: $0.sample) }.filter { $0.tick < ticks }
        if got.map({ $0.note }) != want.map({ $0.note }) || got.map({ $0.tick }) != want.map({ $0.tick }) {
            let d = zip(got, want).enumerated().first(where: { $0.element.0.note != $0.element.1.note || $0.element.0.tick != $0.element.1.tick })
            return "\(tag): \(configs.map { "[from \($0.fromTick)] " + describe($0.h) }.joined(separator: "  ⟶  ")) — first difference at index \(d?.offset ?? min(got.count, want.count)): got \(got.prefix(14).map { "\($0.tick):\($0.note)" }) want \(want.prefix(14).map { "\($0.tick):\($0.note)" })"
        }
        guard lengths else { return nil }
        // note-off times: the pitch's next off after each on, unless the same pitch is struck again before the model's off (a restrike moves the off)
        for (i, w) in want.enumerated() {
            let onSample = got[i].sample
            let expectedOff = onSample + Int64((w.beats * Double(beatSamples)).rounded())
            if Double(w.tick) + w.beats + 2 >= Double(ticks) { continue }   // a note still sounding when the run ends (the transport stop closes it) says nothing about its length
            // the same pitch struck again while this (or an earlier) note of it still sounds: the engine reference-counts the pitch, so one off can serve two notes — nothing to pair
            if want.prefix(i).contains(where: { $0.note == w.note && Double($0.tick) + $0.beats + 0.01 > Double(w.tick) }) { continue }
            if let nextSame = got.dropFirst(i + 1).first(where: { $0.note == w.note }), nextSame.sample <= expectedOff + 100 { continue }
            guard let off = e.offs.first(where: { $0.note == w.note && $0.sample > onSample + 50 }) else { return "\(tag): tick \(w.tick) note \(w.note) never ended — \(describe(configs[0].h))" }
            if abs(off.sample - expectedOff) > 200 {
                return "\(tag): tick \(w.tick) note \(w.note) ends at +\(Double(off.sample - onSample) / Double(beatSamples)) beats, the model says +\(w.beats) — \(describe(configs[0].h))"
            }
        }
        return nil
    }
    private func report(_ name: String, _ failures: [String], of total: Int) {
        print("HUNT \(name): \(failures.count) of \(total) trials differ (\(setAside) set aside for the known REPEAT + SHIFT defect)")
        for f in failures.prefix(8) { print("HUNT \(name) FAIL " + f) }
    }

    // MARK: A — the real engine's note-ons against the brute-force model (HIT / STEP, every, stride, shift, onRest; FWD rhythm)
    func testEngineStrikesMatchTheBruteForceWalk() {
        var failures: [String] = []
        for trial in 0..<400 {
            var r = HuntRng(s: UInt64(trial) &* 7919 &+ 1)
            let h = randomHunt(&r)
            if let f = check("trial \(trial)", [(0, h)], beats: 36) { failures.append(f) }
        }
        report("A", failures, of: 400)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of 400 random walks differ from the brute-force model; first: \(failures.first ?? "")")
    }

    // MARK: A2 — targeted: ON REST = REPEAT with SHIFT (the window is columns SHIFT…SHIFT+LEN-1 wrapping at 8, not 0…LEN-1)
    /// LEN 2 SHIFT 4 walks indices 4 and 5. Only index 4 carries a note; the columns 0…1 (where an unshifted LEN-2 window would sit) are rests. A hit that lands on the rest at index 5 must REPEAT the note of index 4 —
    /// `euclideousRiffRepeatLookback`'s "does any column the walk reaches have a note" early-out (Derivations.swift) looks at columns 0..<LEN instead of the shifted window and answers "none".
    func testRepeatWithShiftRepeatsTheNoteOfTheShiftedWindow() {
        var h = Hunt()
        h.dir = .forward; h.length = 2; h.shift = 4; h.onRest = .repeatLast
        h.ranks = [0, 0, 0, 0, 3, 0, 0, 0]
        let e = run(state(h), beats: 12)
        let want = modelOns([(0, h)], ticks: 11)
        let got = e.ons.map { (tick: tick($0.sample), note: $0.note) }.filter { $0.tick < 11 }
        XCTAssertEqual(want.map { $0.note }, Array(repeating: huntPool[2], count: 11), "the model: every hit (index 4's note, then index 5 REPEATing it) sounds the third pool note")
        XCTAssertEqual(got.map { $0.tick }, want.map { $0.tick }, "REPEAT must sound on every hit; the engine goes silent on the rest column")
        XCTAssertEqual(got.map { $0.note }, want.map { $0.note })
    }
    /// The same with REV and a window that wraps past column 8 (LEN 3 SHIFT 6: indices 6, 7, 0).
    func testRepeatWithAWrappingShiftedWindow() {
        var h = Hunt()
        h.dir = .reverse; h.length = 3; h.shift = 6; h.onRest = .repeatLast
        h.ranks = [0, 0, 0, 0, 0, 0, 0, 5]          // index 7 (the second column of the window) is the only note; indices 0…2 (an unshifted window) are rests
        let e = run(state(h), beats: 12)
        let want = modelOns([(0, h)], ticks: 11)
        let got = e.ons.map { (tick: tick($0.sample), note: $0.note) }.filter { $0.tick < 11 }
        XCTAssertEqual(got.map { $0.tick }, want.map { $0.tick })
        XCTAssertEqual(got.map { $0.note }, want.map { $0.note })
    }

    // MARK: B — the same, with the RHYTHM lane's own direction (BKW / PING-PONG) and MELODY restart chains
    func testEngineStrikesMatchTheModelUnderRhythmDirectionsAndMelodyChains() {
        var failures: [String] = []
        for trial in 0..<400 {
            var r = HuntRng(s: UInt64(trial) &* 104_729 &+ 3)
            let h = randomHunt(&r, withRhythmDirs: true, withMelody: true)
            if let f = check("trial \(trial)", [(0, h)], beats: 46) { failures.append(f) }
        }
        report("B", failures, of: 400)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of 400 differ; first: \(failures.first ?? "")")
    }

    // MARK: C — TIE: the length of every note against the model (the lookahead reads the walk forward in each direction)
    func testTieNoteLengthsMatchTheModelInEveryDirection() {
        var failures: [String] = []
        for trial in 0..<300 {
            var r = HuntRng(s: UInt64(trial) &* 15_485_863 &+ 5)
            var h = randomHunt(&r, withRhythmDirs: true, withMelody: true)
            h.onRest = .tie
            h.ranks = h.ranks.map { $0 == 0 || r.bool(0.35) ? 0 : $0 }   // plenty of rests so ties happen
            if !h.ranks.contains(where: { $0 >= 1 }) { h.ranks[0] = 1 }
            if hitsStepTieRestartBug(h) { setAside += 1; continue }   // the known defect, pinned by its own test below
            if let f = check("trial \(trial)", [(0, h)], beats: 46, lengths: true) { failures.append(f) }
        }
        report("C", failures, of: 300)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of 300 differ; first: \(failures.first ?? "")")
    }

    // MARK: C2 — targeted: TIE under ADV STEP with a MELODY restart (a restart must end a tied run, §4.6: "no hit moves")
    /// n = 4 steps, the first a rest: ". x x x". MELODY restarts every pass, ADV STEP, ON REST = TIE, LEN 4. A pass's hits are at steps 1…3 and read walk steps 1…3 (the step ordinal counts from the pass start), so only column 3 has a note. The note
    /// struck at tick 3 (pass 0's last hit) is followed by tick 5, pass 1's first hit — a restart — which reads column 1 (a rest). The restart ends the tie: the note lasts GATE × the 2-beat gap = 1.0 beat. The engine's lookahead only recognises
    /// the restart when `advOrd == 0`, i.e. when a hit lands exactly on the restart tick; here the first hit is at step 1 (ordinal 1), so the run goes on through the new pass's rests (ticks 5 and 6) and the note rings 3.5 beats.
    func testATiedNoteDoesNotRingAcrossAMelodyRestartUnderAdvanceStep() {
        var h = Hunt()
        h.dir = .forward; h.length = 4; h.onRest = .tie; h.step = true; h.melodyPasses = 1
        h.ranks = [0, 0, 0, 5, 0, 0, 0, 0]
        h.hits = [false, true, true, true]
        let e = run(state(h), beats: 14)
        let ons = e.ons.map { (tick: tick($0.sample), sample: $0.sample, note: $0.note) }
        XCTAssertEqual(ons.prefix(2).map { $0.tick }, [3, 7], "the note sounds on the last hit of each pass")
        guard let on = ons.first, let off = e.offs.first(where: { $0.note == on.note && $0.sample > on.sample }) else { return XCTFail("no note") }
        XCTAssertEqual(Double(off.sample - on.sample) / Double(beatSamples), 1.0, accuracy: 0.01, "the tie ends at the melody restart: GATE 0.5 × the 2-beat gap to the next hit (the model; the engine rings 3.5 beats)")
    }
    /// The same lane under ADV HIT (where the first hit of a pass has ordinal 0): the restart already ends the tie there — the control.
    func testATiedNoteDoesNotRingAcrossAMelodyRestartUnderAdvanceHitControl() {
        var h = Hunt()
        h.dir = .forward; h.length = 4; h.onRest = .tie; h.step = false; h.melodyPasses = 1
        h.ranks = [0, 0, 5, 0, 0, 0, 0, 0]          // HIT ordinals 0,1,2 per pass → column 2 is the pass's last hit
        h.hits = [false, true, true, true]
        let e = run(state(h), beats: 14)
        let ons = e.ons.map { (tick: tick($0.sample), sample: $0.sample, note: $0.note) }
        XCTAssertEqual(ons.prefix(2).map { $0.tick }, [3, 7])
        guard let on = ons.first, let off = e.offs.first(where: { $0.note == on.note && $0.sample > on.sample }) else { return XCTFail("no note") }
        XCTAssertEqual(Double(off.sample - on.sample) / Double(beatSamples), 1.0, accuracy: 0.01)
    }
    // MARK: D — a MID-PLAY DIRECTION SWITCH: the walk position is derived from the ordinal, so it re-derives; nothing may double-strike, hang or skip
    func testSwitchingTheDirectionMidPlayFollowsTheModelAndLeavesNothingSounding() {
        var failures: [String] = []
        let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]
        for trial in 0..<300 {
            var r = HuntRng(s: UInt64(trial) &* 32_452_843 &+ 7)
            var h1 = randomHunt(&r, withRhythmDirs: trial % 3 == 0)
            h1.melodyPasses = nil
            var h2 = h1
            h2.dir = dirs[(dirs.firstIndex(of: h1.dir)! + r.int(1...3)) % 4]
            if r.bool(0.3) { h2.length = r.int(1...8) }
            let swapWindow = r.int(40...200)            // a window index: 2048-frame windows, swap before window `swapWindow`
            let swapSample = Int64(swapWindow) * 2048
            let swapTick = Int((swapSample + beatSamples - 1) / beatSamples)   // the first hit tick at or after the swap
            if let f = check("trial \(trial)", [(0, h1), (swapTick, h2)], swaps: [(swapSample, state(h2))], beats: 40) { failures.append(f) }
        }
        report("D", failures, of: 300)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of 300 differ; first: \(failures.first ?? "")")
    }
}
