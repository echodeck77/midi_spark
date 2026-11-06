//  RhythmDirectionHuntTests.swift — BUG HUNT (2026-11-06): the RHYTHM lane's DIRECTION (FWD / BKW / PING-PONG) driven through the REAL Router against an independent brute-force model, and against each engine dependent's own derivation.
//  The model below is written from the rule alone (a hit at buffer cell b sounds at tick b under FWD, n−1−b under BKW, and at b AND 2n−1−b under PING-PONG, every lap of cycleLen ticks) — never from the engine's own functions.

import XCTest

final class RhythmDirectionHuntTests: XCTestCase {
    struct Rng { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
        mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] } }

    func lane(hits: Int, steps: Int, rate: ArpRate = .r1_8, dir: EuclidDir? = nil, rotate: Int = 0) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: hits, steps: steps, velocityAbsolute: 100, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
        l.direction = dir; l.rotate = rotate
        return l
    }

    struct Rec { var onBeat: Double; var length: Double; var isEnd: Bool; var part: Int; var pitch: Int }
    final class NullOut: MIDIEmitter { var events: [(sample: Int64, cable: UInt8, b0: UInt8, b1: UInt8, b2: UInt8)] = []
        func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append((sampleTime, cable, b0, b1, b2)) } }

    func document(_ lines: [EuclidLine], riff: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], swing: Int = 50, tweak: ((inout PluginState) -> Void)? = nil) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riff)
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.swing = swing
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        tweak?(&st)
        return st
    }

    /// Drive the real Router. `boxAt(beat)` picks the snapshot per window (a mid-play document change); returns the roll records and the raw MIDI.
    @discardableResult
    func drive(_ boxAt: (Double) -> SnapshotBox, beats: Double, frames: UInt32 = 480, tempo: Double = 120, start: Double = 0, playingAt: (Double) -> Bool = { _ in true },
               out: NullOut = NullOut()) -> (recs: [Rec], out: NullOut) {
        let router = Router(); var diag = KernelDiag()
        let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let sr = 48_000.0; var ts = 0.0, recs: [Rec] = []
        func beatNow() -> Double { start + ts * tempo / 60.0 / sr }
        while beatNow() < start + beats {
            router.process(box: boxAt(beatNow()), pool: pool, playing: playingAt(beatNow()), beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
            for r in router.rollRing.drain() { recs.append(Rec(onBeat: r.onBeat, length: Double(r.length), isEnd: r.isEnd, part: Int(r.part), pitch: Int(r.pitch))) }
            ts += Double(frames)
        }
        // a closing stopped window flushes sounding voices
        router.process(box: boxAt(beatNow()), pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
        for r in router.rollRing.drain() { recs.append(Rec(onBeat: r.onBeat, length: Double(r.length), isEnd: r.isEnd, part: Int(r.part), pitch: Int(r.pitch))) }
        return (recs, out)
    }
    func onsets(_ recs: [Rec], lane: Int) -> [Double] {
        Array(Set(recs.filter { !$0.isEnd && $0.part / 2 == lane }.map { ($0.onBeat * 1e6).rounded() / 1e6 })).sorted()
    }

    // MARK: the independent model
    /// Hit cells in BUFFER space after HITS / TILT / OFFSET / FLIP — built by the SAME pattern builder the engine uses (the pattern is not what is under test), then read by the model's own direction rule.
    func bufferCells(_ L: EuclidLine) -> (cells: [Bool], micro: [Double], n: Int) {
        var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 0, count: 16)
        let n = euclideousBuildHitPatternInto(L, cells: &cells, micro: &micro)
        return (cells, micro, n)
    }
    /// Onset beats of every hit of `L` in [from, to), anchored to the absolute beat grid (no restarts): tick t sounds at (t + delay) × sub.
    func modelOnsets(_ L: EuclidLine, from: Double, to: Double) -> [Double] {
        let (cells, micro, n) = bufferCells(L)
        let sub = L.rate?.beats ?? 0.5
        let dir = L.directionResolved
        let cl = dir == .pingpong ? 2 * n : n
        let f = L.offsetFractionResolved
        // every hit as continuous positions u in [0, cl) of the lap
        var us: [Double] = []
        for b in 0..<n where cells[b] {
            var x = Double(b) + micro[b] + f
            while x >= Double(n) { x -= Double(n) }
            switch dir {
            case .fwd: us.append(x)
            case .bkw: us.append(Double(n) - 1 - x)
            case .pingpong: us.append(x); us.append(2 * Double(n) - 1 - x)
            }
        }
        var out: [Double] = []
        let lapBeats = Double(cl) * sub
        var lap = Int((from / lapBeats).rounded(.down)) - 1
        while Double(lap) * lapBeats < to {
            for u0 in us {
                var u = u0; while u < 0 { u += Double(cl) }; while u >= Double(cl) { u -= Double(cl) }
                let b = (Double(lap) * Double(cl) + u) * sub
                if b >= from - 1e-9 && b < to - 1e-9 { out.append(b) }
            }
            lap += 1
        }
        return out.sorted()
    }

    // MARK: 1 — the plain tick math through the real Router
    /// FWD / BKW / PING-PONG × every STEPS 2…16 × HITS × OFFSET, no timing: the engine's strikes are exactly the model's, at any host buffer size and tempo.
    func testPlainDirectionsMatchTheModel() {
        var rng = Rng(s: 20261106); var bad: [String] = []; var trials = 0
        for _ in 0..<180 {
            let n = rng.int(2...16), k = rng.int(0...n), dir = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rot = rng.int(0...(n - 1))
            let rate = rng.pick([ArpRate.r1_8, .r1_16, .r1_8d, .r1_16d, .r1_4, .r1_32, .r1_4d])   // dyadic and dotted steps: exact in binary (triplets: `testTripletRatesKeepEveryDirectionsPatternPeriodic`)
            let L = lane(hits: k, steps: n, rate: rate, dir: dir, rotate: rot)
            let frames = UInt32(rng.pick([64, 480, 1000, 2048, 4096])), tempo = rng.pick([93.9, 120.0, 137.31, 60.0])
            let beats = min(24.0, 2.2 * Double(dir == .pingpong ? 2 * n : n) * (rate.beats))
            let box = SnapshotBuilder.build(from: document([L]))
            let r = drive({ _ in box }, beats: beats, frames: frames, tempo: tempo)
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }, want = modelOnsets(L, from: 0, to: beats - 2e-3).map { ($0 * 1e6).rounded() / 1e6 }
            trials += 1
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 3e-4 }) {
                let ticks: ([Double]) -> [Int] = { $0.map { Int(($0 / rate.beats).rounded()) } }
                bad.append("\(k)/\(n) rot \(rot) \(dir) \(rate.rawValue) frames \(frames) \(tempo) bpm: engine ticks \(ticks(got).prefix(24)) vs model \(ticks(want).prefix(24)) (\(got.count) vs \(want.count))")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(trials) configurations differ:\n" + bad.prefix(6).joined(separator: "\n"))
    }

    // MARK: 2 — hit timing (OFFSET's fraction, a fine TILT) in every direction
    /// A fractional OFFSET and/or an unrounded TILT push each hit a fraction of a step into (or across) its cell; the direction mirrors the position. The engine's strikes must be the model's (a PING-PONG hit that lands in an already-taken cell
    /// at the turn is the one documented exception: it moves to the next free cell — the model reports those configurations separately).
    func testHitTimingInEveryDirectionMatchesTheModel() {
        var rng = Rng(s: 909); var bad: [String] = [], turnCollisions = 0, trials = 0, collisionByDir: [String: Int] = [:]
        for _ in 0..<160 {
            let n = rng.int(2...16), k = rng.int(1...n), dir = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rot = rng.int(0...(n - 1))
            var L = lane(hits: k, steps: n, rate: rng.pick([.r1_8, .r1_16, .r1_4, .r1_8d]), dir: dir, rotate: rot)
            let useFraction = rng.int(0...2) != 0, useTilt = rng.int(0...2) != 0
            if useFraction { L.offsetFraction = Double(rng.int(5...95)) / 100 }
            if useTilt { L.tiltFine = Double(rng.int(-90...90)) / 100 }
            if !useFraction && !useTilt { continue }
            let rate = L.rate!
            let beats = min(24.0, 2.2 * Double(dir == .pingpong ? 2 * n : n) * rate.beats)
            let box = SnapshotBuilder.build(from: document([L]))
            let r = drive({ _ in box }, beats: beats, frames: UInt32(rng.pick([480, 2048])), tempo: 120)
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 5e-3 }, want = modelOnsets(L, from: 0, to: beats - 5e-3)
            trials += 1
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 6e-4 }) {
                // is the model itself ambiguous here (two hits of one lap in the same tick cell — only possible at a PING-PONG turn or when two micro-delays collide)?
                let cl = dir == .pingpong ? 2 * n : n
                let cells = want.filter { $0 < Double(cl) * rate.beats }.map { Int(($0 / rate.beats).rounded(.down)) }
                if Set(cells).count != cells.count { turnCollisions += 1; collisionByDir["\(dir)/\(useFraction ? "F" : "-")\(useTilt ? "T" : "-")", default: 0] += 1; continue }
                let ticks: ([Double]) -> [String] = { $0.map { String(format: "%.2f", $0 / rate.beats) } }
                bad.append("\(k)/\(n) rot \(rot) \(dir) \(rate.rawValue) frac \(L.offsetFraction ?? 0) tilt \(L.tiltFine ?? 0): engine \(ticks(got).prefix(14)) vs model \(ticks(want).prefix(14))")
            }
        }
        print("HUNT timing: \(trials) trials, \(turnCollisions) with two hits in one tick cell (set aside) \(collisionByDir)")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) timing configurations differ:\n" + bad.prefix(5).joined(separator: "\n"))
    }

    // MARK: 3 — COPY / FILL (RHYTHM borrowing) with a PING-PONG or BKW source
    /// Two lanes: lane 0 = the follower (RHYTHM COPY or FILL of lane 1), lane 1 = the source. Returns [lane: onsets].
    func borrow(source: EuclidLine, follower: EuclidLine, mode: EuclideousListenRhythmMode, beats: Double, frames: UInt32 = 480) -> [Int: [Double]] {
        var f = follower; f.setAnswerRhythm(mode); f.listenSource = 1
        let box = SnapshotBuilder.build(from: document([f, source]))
        let r = drive({ _ in box }, beats: beats, frames: frames)
        return [0: onsets(r.recs, lane: 0), 1: onsets(r.recs, lane: 1)]
    }
    /// COPY at DIRECTION FWD / SPEED 0 / DELAY 0 plays EXACTLY what the source plays ("the order the source is playing its OWN pattern right now", §3.4): the follower's hits are the source's hits, tick for tick, whatever the source's direction.
    func testCopyOfAPingPongOrBkwSourceFollowsTheSourcesLiveOrder() {
        var bad: [String] = []
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            for (k, n, rot) in [(3, 8, 0), (3, 8, 2), (5, 8, 1), (2, 5, 0), (4, 7, 3), (1, 4, 0)] {
                let src = lane(hits: k, steps: n, rate: .r1_8, dir: dir, rotate: rot)
                let fol = lane(hits: 7, steps: 8, rate: .r1_8, dir: .fwd)           // its own pattern is irrelevant while borrowing
                let r = borrow(source: src, follower: fol, mode: .copy, beats: 24)
                if r[0] != r[1] { bad.append("source \(k)/\(n) rot \(rot) \(dir): follower \(r[0]!.prefix(12).map { String(format: "%.2f", $0) }) vs source \(r[1]!.prefix(12).map { String(format: "%.2f", $0) })") }
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) COPY followers do not follow the source's live order:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    /// A follower whose own DIRECTION is PING-PONG plays the source's stored pattern bouncing (period 2n), like a PING-PONG lane of the same pattern — not just the forward half.
    func testACopyFollowerInPingPongBouncesTheSourcesStoredPattern() {
        var bad: [String] = []
        for (k, n, rot) in [(3, 8, 0), (3, 8, 2), (5, 8, 1), (2, 5, 0), (4, 7, 3)] {
            let src = lane(hits: k, steps: n, rate: .r1_8, dir: .fwd, rotate: rot)
            var fol = lane(hits: 7, steps: 8, rate: .r1_8, dir: .fwd); fol.listenDirection = .pingpong
            let r = borrow(source: src, follower: fol, mode: .copy, beats: 24)
            let want = modelOnsets(lane(hits: k, steps: n, rate: .r1_8, dir: .pingpong, rotate: rot), from: 0, to: 24 - 2e-3)
            let got = r[0]!.filter { $0 < 24 - 2e-3 }
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 3e-4 }) { bad.append("source \(k)/\(n) rot \(rot) FWD, follower PING-PONG: \(got.prefix(10).map { String(format: "%.2f", $0) }) vs \(want.prefix(10).map { String(format: "%.2f", $0) })") }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) PING-PONG followers do not bounce:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    // MARK: 4 — a direction CHANGE while playing
    /// Per output note: every note-on has its note-off by the end of a closing stop (no stuck note), none is struck twice at one instant.
    func hangingNotes(_ out: NullOut) -> [String] {
        var depth: [String: Int] = [:], sameInstant: [String: Int] = [:], bad: [String] = []
        for e in out.events {
            let st = e.b0 & 0xF0, key = "c\(e.cable) ch\(e.b0 & 0x0F) n\(e.b1)"
            if st == 0x90 && e.b2 > 0 { depth[key, default: 0] += 1; sameInstant["\(key)@\(e.sample)", default: 0] += 1 }
            else if st == 0x80 || (st == 0x90 && e.b2 == 0) { depth[key, default: 0] -= 1 }
        }
        for (k, v) in depth where v != 0 { bad.append("\(k) depth \(v)") }
        for (k, v) in sameInstant where v > 1 { bad.append("\(k) struck \(v)×") }
        return bad
    }
    /// Swap the lane's direction between windows (FWD → BKW → PING-PONG → …, at awkward beats and buffer sizes, with a high GATE so notes overlap their neighbours): afterwards each segment plays the model of ITS direction, no note hangs and none is struck twice.
    func testChangingDirectionWhilePlayingKeepsTheSoundHonest() {
        var rng = Rng(s: 31337); var bad: [String] = []
        for _ in 0..<40 {
            let n = rng.int(2...12), k = rng.int(1...n), rot = rng.int(0...(n - 1))
            let dirs = [rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rng.pick([EuclidDir.fwd, .bkw, .pingpong])]
            let rate = rng.pick([ArpRate.r1_8, .r1_16, .r1_4])
            var gate = 0.9; if rng.int(0...2) == 0 { gate = 0.99 }
            func make(_ d: EuclidDir) -> SnapshotBox { var L = lane(hits: k, steps: n, rate: rate, dir: d, rotate: rot); L.gate = gate; return SnapshotBuilder.build(from: document([L])) }
            let boxes = dirs.map(make)
            let t1 = Double(rng.int(20...90)) / 10, t2 = t1 + Double(rng.int(20...90)) / 10, total = t2 + Double(rng.int(20...60)) / 10
            func idx(_ b: Double) -> Int { b < t1 ? 0 : (b < t2 ? 1 : 2) }
            let out = NullOut()
            let r = drive({ boxes[idx($0)] }, beats: total, frames: UInt32(rng.pick([64, 480, 1000, 4096])), tempo: 120, out: out)
            let got = onsets(r.recs, lane: 0)
            let margin = 2 * rate.beats * Double(n) * 2   // one worst-case lap of the new direction after a switch (nothing may be claimed about the first lap: the riff walk re-counts, but the HITS must already be right)
            _ = margin
            for (si, (lo, hi)) in [(0.0, t1), (t1, t2), (t2, total)].enumerated() {
                let L = lane(hits: k, steps: n, rate: rate, dir: dirs[si], rotate: rot)
                let want = modelOnsets(L, from: lo, to: hi - 5e-3), seg = got.filter { $0 >= lo - 1e-9 && $0 < hi - 5e-3 }
                // a window that straddles the switch is rendered with the old document (≤ 4096 frames = 0.17 beat): nothing is claimed within 0.2 beat of a switch
                let slack = 0.2005   // (and a hair: strikes sit on sample boundaries)
                let w = want.filter { $0 >= lo + slack && $0 < hi - slack }, g = seg.filter { $0 >= lo + slack && $0 < hi - slack }
                if w.count != g.count || zip(w, g).contains(where: { abs($0 - $1) > 6e-4 }) {
                    bad.append("\(k)/\(n) rot \(rot) \(rate.rawValue) \(dirs[0])→\(dirs[1])@\(t1)→\(dirs[2])@\(t2) segment \(si): engine \(g.prefix(8).map { String(format: "%.2f", $0) }) vs model \(w.prefix(8).map { String(format: "%.2f", $0) })")
                }
            }
            let hang = hangingNotes(out)
            if !hang.isEmpty { bad.append("\(k)/\(n) \(rate.rawValue) \(dirs) gate \(gate): \(hang.prefix(3))") }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) direction-change problems:\n" + bad.prefix(5).joined(separator: "\n"))
    }

    // MARK: 5 — rhythm restarts (BAR and another lane's PASS) in every direction
    /// Onsets of a no-timing lane whose rhythm restarts at `restarts` (ascending beats, the first = 0): at a restart the lap begins again at its raw 0 (FWD the first cell, BKW the last, PING-PONG the first on its way out); a segment is cut at the next restart.
    func modelOnsetsWithRestarts(_ L: EuclidLine, restarts: [Double], to: Double) -> [Double] {
        let (cells, _, n) = bufferCells(L)
        let sub = L.rate?.beats ?? 0.5, dir = L.directionResolved, cl = dir == .pingpong ? 2 * n : n
        func hit(_ raw: Int) -> Bool { cells[dir == .fwd ? raw : (dir == .bkw ? n - 1 - raw : (raw < n ? raw : 2 * n - 1 - raw))] }
        var out: [Double] = []
        for (i, s) in restarts.enumerated() {
            let e = i + 1 < restarts.count ? restarts[i + 1] : to
            if s >= to { break }
            // a restart takes effect at the first tick at or after it, counted from the tick GRID it falls on (the origin is floored to the lane's own tick)
            let originTick = Int((s / sub + 1e-9).rounded(.down))
            var t = Int((s / sub - 1e-9).rounded(.up))
            while Double(t) * sub < min(e, to) - 1e-9 { if hit(((t - originTick) % cl + cl) % cl) { out.append(Double(t) * sub) }; t += 1 }
        }
        return out
    }
    func barRestartBeats(_ links: [Int], upTo: Double, bar: Double = 4) -> [Double] {
        var out = [0.0], t = 0.0, i = 0
        while t < upTo { t += Double(links[i % links.count]) * bar; i += 1; out.append(t) }
        return out
    }
    /// A rhythm restart chain counted in BARS: after each restart the lap starts over at its first step (whatever the direction); the pass that a restart cuts short never plays its tail.
    func testRhythmBarRestartsInEveryDirection() {
        var rng = Rng(s: 555); var bad: [String] = []
        for _ in 0..<60 {
            let n = rng.int(3...12), k = rng.int(1...n), dir = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rot = rng.int(0...(n - 1))
            let links = rng.pick([[1], [2], [3], [2, 1], [1, 3, 2]])
            var L = lane(hits: k, steps: n, rate: rng.pick([.r1_8, .r1_16, .r1_4]), dir: dir, rotate: rot)
            L.restartRhythmBars = links.map { UInt8($0) }; L.restartRhythmOn = true; L.restartMelodyPasses = []
            let beats = 30.0
            let box = SnapshotBuilder.build(from: document([L]))
            let r = drive({ _ in box }, beats: beats, frames: UInt32(rng.pick([480, 2048])), tempo: 120)
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }
            let want = modelOnsetsWithRestarts(L, restarts: barRestartBeats(links, upTo: beats), to: beats - 2e-3)
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 4e-4 }) {
                bad.append("\(k)/\(n) rot \(rot) \(dir) \(L.rate!.rawValue) restart bars \(links): engine \(got.prefix(12).map { String(format: "%.2f", $0) }) vs model \(want.prefix(12).map { String(format: "%.2f", $0) })")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) restart configurations differ:\n" + bad.prefix(4).joined(separator: "\n"))
    }
    /// A rhythm restart on ANOTHER lane's passes: lane 0 starts over whenever lane 1 (free-running, any direction) begins a pass — a pass of a PING-PONG lane is 2n steps.
    func testRhythmPassRestartsFollowTheSourcesRealLap() {
        var rng = Rng(s: 8128); var bad: [String] = []
        for _ in 0..<30 {
            let n0 = rng.int(3...9), n1 = rng.int(2...8), dir0 = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), dir1 = rng.pick([EuclidDir.fwd, .bkw, .pingpong])
            let link = rng.pick([1, 2, 3])
            var L0 = lane(hits: rng.int(1...n0), steps: n0, rate: .r1_8, dir: dir0, rotate: rng.int(0...(n0 - 1)))
            L0.restartRhythmBars = [UInt8(link)]; L0.restartRhythmUnit = .pass; L0.restartRhythmSource = 1; L0.restartRhythmOn = true; L0.restartMelodyPasses = []
            let L1 = lane(hits: rng.int(1...n1), steps: n1, rate: rng.pick([.r1_8, .r1_16, .r1_4]), dir: dir1, rotate: 0)
            let lap1 = Double(dir1 == .pingpong ? 2 * n1 : n1) * L1.rate!.beats
            let beats = 28.0
            var restarts = [0.0], t = 0.0
            while t < beats { t += Double(link) * lap1; restarts.append(t) }
            let box = SnapshotBuilder.build(from: document([L0, L1]))
            let r = drive({ _ in box }, beats: beats, frames: 480, tempo: 120)
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }
            let want = modelOnsetsWithRestarts(L0, restarts: restarts, to: beats - 2e-3)
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 4e-4 }) {
                bad.append("lane0 \(n0) steps \(dir0) restarts every \(link) pass(es) of lane1 (\(n1) steps \(dir1) \(L1.rate!.rawValue), lap \(lap1) beats): engine \(got.prefix(10).map { String(format: "%.2f", $0) }) vs model \(want.prefix(10).map { String(format: "%.2f", $0) })")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) PASS-restart configurations differ:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    // MARK: 6 — dependents that read "which step plays when" from the lane
    /// AVOID silences the follower's hit where the SOURCE's step holds a rhythm hit, MEET where it does not (ANSWER v2). The source's tick set comes from the model (PING-PONG: both visits of an endpoint, BKW mirrored).
    func testAvoidAndMeetReadTheSourcesStepInEveryDirection() {
        var rng = Rng(s: 2718); var bad: [String] = []
        for _ in 0..<60 {
            let n0 = rng.int(2...10), n1 = rng.int(2...10), dir0 = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), dir1 = rng.pick([EuclidDir.fwd, .bkw, .pingpong])
            let r0 = rng.pick([ArpRate.r1_8, .r1_16, .r1_4]), r1 = rng.pick([ArpRate.r1_8, .r1_16, .r1_4, .r1_32])
            let meet = rng.int(0...1) == 0
            var f = lane(hits: rng.int(1...n0), steps: n0, rate: r0, dir: dir0, rotate: rng.int(0...(n0 - 1)))
            let s = lane(hits: rng.int(1...n1), steps: n1, rate: r1, dir: dir1, rotate: rng.int(0...(n1 - 1)))
            f.setAnswerRhythm(meet ? .meet : .avoid); f.listenSource = 1
            let beats = 24.0
            let box = SnapshotBuilder.build(from: document([f, s]))
            let r = drive({ _ in box }, beats: beats, frames: UInt32(rng.pick([480, 2048])), tempo: 120)
            var plain = f; plain.listenSource = nil
            plain.setAnswerRhythm(.own)
            let srcTicks = Set(modelOnsets(s, from: 0, to: beats + 1).map { Int(($0 / r1.beats).rounded()) })
            let want = modelOnsets(plain, from: 0, to: beats - 2e-3).filter { b in
                let playing = srcTicks.contains(Int(((b / r1.beats) + 1e-9).rounded(.down)))
                return meet ? playing : !playing
            }
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 4e-4 }) {
                bad.append("\(meet ? "MEET" : "AVOID") follower \(f.pulses)/\(n0) \(dir0) \(r0.rawValue) source \(s.pulses)/\(n1) \(dir1) \(r1.rawValue): engine \(got.prefix(10).map { String(format: "%.2f", $0) }) vs model \(want.prefix(10).map { String(format: "%.2f", $0) })")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) AVOID / MEET configurations differ:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    /// The CHORDS grid's LOOP advance counts a lane's laps through the restart schedule: a PING-PONG lane's lap is 2n steps (a COPY follower's, 2n when its source or its DIRECTION is PING-PONG), BKW's n.
    func testChordsLoopAdvanceCountsTheLanesRealLap() {
        let steps = 8
        var bad: [String] = []
        for (label, lines, lap) in [
            ("PING-PONG 5 steps 1/8", [lane(hits: 2, steps: 5, rate: .r1_8, dir: .pingpong)], 10),
            ("BKW 5 steps 1/8", [lane(hits: 2, steps: 5, rate: .r1_8, dir: .bkw)], 5),
            ("COPY of a PING-PONG 6 steps 1/16", { var f = self.lane(hits: 3, steps: 8, rate: .r1_8); f.setAnswerRhythm(.copy); f.listenSource = 1; return [f, self.lane(hits: 2, steps: 6, rate: .r1_16, dir: .pingpong)] }(), 12),
        ] as [(String, [EuclidLine], Int)] {
            let set = euclideousRestartScheduleSet(lines: lines + (lines.count..<4).map { _ in EuclidLine(enabled: false) }, barBeats: 4, defaultRateBeats: 0.5, riffColumns: 8)
            let sub = label.hasPrefix("COPY") ? 0.25 : 0.5, lapBeats = Double(lap) * sub
            let cfg = ChordsAdvanceConfig(rateBeats: 1, steps: steps, rotate: 0, advanceUnit: .loop, advanceLane: 0, advanceEvery: 1, restartOn: false, restartUnit: .bar, restartLane: 0, restartEvery: 1)
            for k in 0..<400 {
                let beat = Double(k) * 0.37
                let want = Int(((beat + 1e-9) / lapBeats).rounded(.down)) % steps
                let got = chordColumn(cfg, beat: beat, schedule: set, barBeats: 4)
                if got != want { bad.append("\(label) @ beat \(beat): column \(got), the lane's lap (\(lapBeats) beats) says \(want)"); break }
            }
        }
        XCTAssertTrue(bad.isEmpty, "LOOP advance disagrees with the lane's lap:\n" + bad.joined(separator: "\n"))
    }

    // MARK: 7 — the legacy `reverse` flag
    /// An old document stores only `reverse` (true = BKW); a new one stores `direction`, which wins. Through the real Router, and through a JSON round trip.
    func testTheLegacyReverseFlagStillPlaysBackwardsAndDirectionWins() throws {
        func heard(_ l: EuclidLine) -> [Double] {
            let box = SnapshotBuilder.build(from: document([l])); return onsets(drive({ _ in box }, beats: 12).recs, lane: 0).filter { $0 < 11.99 }
        }
        var old = lane(hits: 3, steps: 8, rate: .r1_8, rotate: 1); old.direction = nil; old.reverse = true
        let bkw = lane(hits: 3, steps: 8, rate: .r1_8, dir: .bkw, rotate: 1), fwd = lane(hits: 3, steps: 8, rate: .r1_8, dir: .fwd, rotate: 1)
        XCTAssertEqual(heard(old), heard(bkw), "reverse = true, no direction: plays BKW")
        XCTAssertNotEqual(heard(old), heard(fwd))
        var both = old; both.direction = .fwd
        XCTAssertEqual(heard(both), heard(fwd), "a stored direction wins over the legacy flag")
        let decoded = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded.directionResolved, .bkw)
        XCTAssertEqual(heard(decoded), heard(bkw))
    }

    /// The lap of a COPY / FILL follower — the source's n steps walked in the follower's DIRECTION (§3.4): 2n when the follower is PING-PONG or its source is, else n; the follower's OWN stored `direction` is paused and never counts. The sound, the
    /// lane geometry the mute sweep / MUTE tab / AVOID's source grid size a pass with, the walk mirror and the restart schedule must all agree on it.
    func testABorrowingLanesLapIsTheSameEverywhere() {
        var bad: [String: [String]] = [:]
        let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong]
        for (k, n, rot) in [(2, 5, 0), (3, 7, 0), (1, 4, 0)] {
            for own in dirs { for listen in dirs { for srcDir in dirs {
                var f = lane(hits: 7, steps: 8, rate: .r1_8, dir: own); f.setAnswerRhythm(.copy); f.listenSource = 1; f.listenDirection = listen
                let s = lane(hits: k, steps: n, rate: .r1_8, dir: srcDir, rotate: rot)
                let expected = (listen == .pingpong || srcDir == .pingpong) ? 2 * n : n
                let tag = "\(k)/\(n) source \(srcDir), follower stored \(own), listen DIRECTION \(listen): expected lap \(expected)"
                // what is heard: the smallest period of the follower's strikes over 112 ticks
                let box = SnapshotBuilder.build(from: document([f, s]))
                let r = drive({ _ in box }, beats: 56, frames: 2048)
                var hit = [Bool](repeating: false, count: 112); for o in onsets(r.recs, lane: 0) where o < 55.9 { hit[Int((o / 0.5).rounded())] = true }
                var period = 0
                for p in 1...32 where period == 0 { if (0..<(112 - p)).allSatisfy({ hit[$0] == hit[$0 + p] }) { period = p } }
                if period != expected { bad["sound", default: []].append("\(tag): heard period \(period)") }
                let lines = [f, s]
                let geo = euclideousLaneStepGeometry(lines: lines, lane: 0, defaultRateBeats: 0.5)
                if geo.cycleLen != expected { bad["geometry", default: []].append("\(tag): euclideousLaneStepGeometry says \(geo.cycleLen)") }
                if let cfg = euclideousWalkLaneConfig(lane: 0, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8), euclidCycleLen(cfg.dir, n: cfg.n) != expected {
                    bad["mirror", default: []].append("\(tag): the walk mirror says \(euclidCycleLen(cfg.dir, n: cfg.n))")
                }
                if let inp = euclideousScheduleLaneInput(lane: 0, lines: lines, defaultRateBeats: 0.5, riffColumns: 8), inp.rawHit.count != expected {
                    bad["schedule", default: []].append("\(tag): the restart schedule's lap is \(inp.rawHit.count)")
                }
            } } }
        }
        let summary = bad.keys.sorted().map { "\($0): \(bad[$0]!.count) of 81 — e.g. \(bad[$0]!.first!)" }
        XCTAssertTrue(bad.isEmpty, "a COPY follower's lap differs between consumers:\n" + summary.joined(separator: "\n"))
    }

    /// A rhythm restart counted in RIFF completions of another lane (the restart SCHEDULE's simulation): the source lane's riff (LENGTH P, FWD) completes after every P-th hit it plays — PING-PONG counts an endpoint's two visits as two hits — and the
    /// completion falls at the start of its next step; the follower starts over there.
    func testRhythmRiffRestartsFollowTheSourcesHits() {
        var rng = Rng(s: 6006); var bad: [String] = [], restartedTrials = 0
        for _ in 0..<40 {
            let n0 = rng.int(3...9), n1 = rng.int(2...7), dir0 = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), dir1 = rng.pick([EuclidDir.fwd, .bkw, .pingpong])
            let P = rng.int(2...5)
            var L0 = lane(hits: rng.int(1...n0), steps: n0, rate: .r1_8, dir: dir0, rotate: rng.int(0...(n0 - 1)))
            L0.restartRhythmBars = [1]; L0.restartRhythmUnit = .riff; L0.restartRhythmSource = 1; L0.restartRhythmOn = true; L0.restartMelodyPasses = []
            var L1 = lane(hits: rng.int(1...n1), steps: n1, rate: rng.pick([.r1_8, .r1_16]), dir: dir1, rotate: rng.int(0...(n1 - 1)))
            L1.riffLength = P
            let sub1 = L1.rate!.beats, beats = 26.0
            let hitTicks = modelOnsets(L1, from: 0, to: beats + 8).map { Int(($0 / sub1).rounded()) }
            var restarts = [0.0]
            var j = P; while j <= hitTicks.count { restarts.append(Double(hitTicks[j - 1] + 1) * sub1); j += P }
            let box = SnapshotBuilder.build(from: document([L0, L1]))
            let r = drive({ _ in box }, beats: beats, frames: 480, tempo: 120)
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }
            let want = modelOnsetsWithRestarts(L0, restarts: restarts, to: beats - 2e-3)
            let free = modelOnsets(L0, from: 0, to: beats - 2e-3)
            if free.count != want.count || zip(free, want).contains(where: { abs($0 - $1) > 4e-4 }) { restartedTrials += 1 }
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 4e-4 }) {
                bad.append("lane0 \(n0) steps \(dir0), restart every riff cycle (LENGTH \(P)) of lane1 \(L1.pulses)/\(n1) \(dir1) \(L1.rate!.rawValue): engine \(got.prefix(10).map { String(format: "%.2f", $0) }) vs model \(want.prefix(10).map { String(format: "%.2f", $0) }) (restarts \(restarts.prefix(5).map { String(format: "%.2f", $0) }))")
            }
        }
        XCTAssertGreaterThan(restartedTrials, 15, "the restarts must actually change the pattern in most trials, or the test proves nothing")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) RIFF-restart configurations differ:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    /// HOCKET's HITS / PASSES counts (`hocketLaneCounts`) for a reference lane in every direction, with and without a BAR restart chain, against a brute-force tick count: HITS = pattern hits at ticks up to and including the moment, minus one (a PING-PONG
    /// endpoint counts at both its visits); PASSES = the lap index (2n steps for PING-PONG) since the rhythm origin.
    func testHocketCountsAreTheBruteForceCountInEveryDirection() {
        var rng = Rng(s: 99); var bad: [String] = []
        for _ in 0..<80 {
            let n = rng.int(2...12), dir = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rate = rng.pick([ArpRate.r1_8, .r1_16, .r1_4, .r1_8d])
            var L = lane(hits: rng.int(1...n), steps: n, rate: rate, dir: dir, rotate: rng.int(0...(n - 1)))
            let links = rng.pick([[Int](), [1], [2], [1, 3], [3, 2, 1]])
            if !links.isEmpty { L.restartRhythmBars = links.map { UInt8($0) }; L.restartRhythmOn = true; L.restartMelodyPasses = [] }
            let bar = 4.0, sub = rate.beats, cl = dir == .pingpong ? 2 * n : n
            let (cells, _, _) = bufferCells(L)
            func hit(_ raw: Int) -> Bool { cells[dir == .fwd ? raw : (dir == .bkw ? n - 1 - raw : (raw < n ? raw : 2 * n - 1 - raw))] }
            let chains = euclideousLaneRestartChains(line: L, lane: 0, barBeats: bar, lapBeats: Double(cl) * sub)
            var clock = HocketLaneClock()
            var buf = [Bool](repeating: false, count: 32); for i in 0..<n { buf[i] = cells[i] }
            clock.capture(cells: buf, delays: [Double](repeating: 0, count: 32), timing: false, n: n, dir: dir, cycleLen: cl, sub: sub, chains: chains, legacySpanBeats: 0)
            let restarts = links.isEmpty ? [0.0] : barRestartBeats(links, upTo: 40, bar: bar)
            for k in stride(from: 0, to: 36.0 / sub, by: 1) {
                let m = Double(k) * sub + sub * 0.37
                // brute force: the count restarts at the latest rhythm restart (origin floored to the lane's tick) and runs tick by tick to this one
                let tickNow = Int(m / sub)
                let latest = restarts.last(where: { $0 <= Double(tickNow) * sub + 1e-9 }) ?? 0   // a restart takes effect from the first tick that STARTS at or after it
                let o = Int((latest / sub + 1e-9).rounded(.down))
                var hits: Int64 = 0
                if tickNow >= o { for t in o...tickNow where hit((t - o) % cl) { hits += 1 } }
                let pass = Int64((tickNow - o) / cl)
                let got = hocketLaneCounts(clock, atMusicalBeat: m)
                if got.hit != max(0, hits - 1) || got.pass != pass { bad.append("\(L.pulses)/\(n) \(dir) \(rate.rawValue) restart bars \(links) @ beat \(m): engine hits \(got.hit) pass \(got.pass) vs brute force hits \(max(0, hits - 1)) pass \(pass)"); break }
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) HOCKET count configurations differ:\n" + bad.prefix(4).joined(separator: "\n"))
    }

    /// The same defect at its source: with no restart chain and no ladder span, a lane's local tick IS the host tick, for every step length — `tick × sub ÷ sub` is not `tick` in binary for a triplet step.
    func testTheLanePhaseIsTheHostTickAtEveryStepLength() {
        var bad: [String] = []
        for rate in ArpRate.allCases where rate.beats > 0 {
            let sub = rate.beats; var wrong = 0, first = -1
            for tick in 0..<4000 {
                let ph = euclideousLaneChainPhase(buf: [Bool](repeating: true, count: 16), n: 16, dir: .fwd, cycleLen: 16, sub: sub, tick: Int64(tick), chains: .off, legacySpanBeats: 0)
                if ph.localT != Int64(tick) { wrong += 1; if first < 0 { first = tick } }
            }
            if wrong > 0 { bad.append("\(rate.rawValue) (\(sub) beat): \(wrong) of 4000 ticks read the previous tick's cell, first at tick \(first)") }
        }
        XCTAssertTrue(bad.isEmpty, "the lane phase drifts a tick behind the host tick:\n" + bad.prefix(8).joined(separator: "\n"))
    }

    /// A triplet step (1/8T = 1/3 beat …) is not exact in binary: the per-tick core derived the lane's phase as `floor((tick × sub) / sub)`, which is `tick − 1` for ticks 7, 14, 25, 28, 31, 50 … — so the lane read the PREVIOUS step's cell there (a hit
    /// dropped at one tick, a rest sounding at the next), whatever the direction. Every direction at every triplet rate must play the model's strikes, every lap.
    func testTripletRatesKeepEveryDirectionsPatternPeriodic() {
        var rng = Rng(s: 4711); var bad: [String] = []
        for _ in 0..<45 {
            let n = rng.int(2...16), k = rng.int(1...n), dir = rng.pick([EuclidDir.fwd, .bkw, .pingpong]), rot = rng.int(0...(n - 1))
            let rate = rng.pick([ArpRate.r1_8t, .r1_16t, .r1_4t, .r1_32t, .r1_2t])
            let L = lane(hits: k, steps: n, rate: rate, dir: dir, rotate: rot)
            let beats = min(24.0, 2.2 * Double(dir == .pingpong ? 2 * n : n) * rate.beats)
            let box = SnapshotBuilder.build(from: document([L]))
            let r = drive({ _ in box }, beats: beats, frames: UInt32(rng.pick([480, 2048])), tempo: rng.pick([120.0, 93.9]))
            let got = onsets(r.recs, lane: 0).filter { $0 < beats - 2e-3 }, want = modelOnsets(L, from: 0, to: beats - 2e-3)
            if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 3e-4 }) {
                let ticks: ([Double]) -> [Int] = { $0.map { Int(($0 / rate.beats).rounded()) } }
                bad.append("\(k)/\(n) rot \(rot) \(dir) \(rate.rawValue): engine ticks \(ticks(got).prefix(20)) vs model \(ticks(want).prefix(20))")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) triplet configurations differ:\n" + bad.prefix(5).joined(separator: "\n"))
    }
}
