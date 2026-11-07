//  DirectionDisplayTests.swift — BUG HUNT (2026-11-06): how the RHYTHM lane's DIRECTION (FWD / BKW / PING-PONG) is reflected in the displays vs what the real Router plays.
//  The oracle is the real Router run offline; the displays are the pure functions the page calls (`euclidCometRaw`, `euclideousPulseTileForOnset`, `euclideousStripPlayhead`, `euclideousHitBoxes`, `euclideousLapHitSteps`, `restartTileState`, …).

import XCTest

final class DirRecorder: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

struct DirRng {
    var s: UInt64
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 10_000) / 10_000 < p }
    mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
}

enum DirHarness {
    static let sr = 48_000.0, tempo = 120.0
    static func box(_ st: PluginState) -> SnapshotBox { var d = st; var p = d.sourcePlanResolved; p.midiOctaves = .keep; d.euclideousSourcePlan = p; return SnapshotBuilder.build(from: d) }
    static func document(_ lines: [EuclidLine], swing: Int = 50) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.swing = swing
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousLanesSeqRate = .oneBar
        return st
    }
    /// Render `beats` of the document with 480-frame windows; `switchAt` swaps the document (a mid-play edit) at the first window starting at or after that beat.
    static func render(_ st: PluginState, beats: Double, switchAt: (beat: Double, to: PluginState)? = nil) -> DirRecorder {
        let e = DirRecorder(); let router = Router(); var diag = KernelDiag(); let pool = NotePool()
        for n in [48, 50, 52, 53, 55, 57, 59, 60] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        var box = DirHarness.box(st)
        var swapped = false
        var ts = 0.0
        let frames: UInt32 = 480
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            if let sw = switchAt, !swapped, beatNow() >= sw.beat - 1e-9 { box = DirHarness.box(sw.to); swapped = true }
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    /// One onset per hit (collapse the several pitches one hit may strike), as REAL beats, ascending.
    static func onsets(_ e: DirRecorder, cable: UInt8 = 1) -> [Double] {
        var out: [Double] = []
        for b in e.ons.filter({ $0.cable == cable }).map({ Double($0.sample) / sr * tempo / 60 }).sorted() where out.last.map({ b - $0 > 0.01 }) ?? true { out.append(b) }
        return out
    }
    static func musical(_ real: Double, swing: Int) -> Double { swing == 50 ? real : musicalOf(real, stepBeats: 0.5, a: Double(swing) / 50.0) }
    static func randomLine(_ rng: inout DirRng, timing: Bool, dir: EuclidDir? = nil) -> EuclidLine {
        let n = rng.int(2...16)
        var l = EuclidLine(target: 0, pulses: rng.int(1...n), steps: n, rate: [.r1_16, .r1_8, .r1_4][rng.int(0...2)], useRiff: true, sourceMode: .midi)
        l.noteSel = .low
        l.rotate = rng.int(0...(n - 1))
        l.direction = dir ?? [.fwd, .bkw, .pingpong][rng.int(0...2)]
        l.gate = 0.5
        if timing {
            if rng.bool(0.6) { l.offsetFraction = [0.2, 0.37, 0.5, 0.62, 0.9][rng.int(0...4)] }
            if rng.bool(0.6) { let t = [-0.6, -0.25, 0.3, 0.55][rng.int(0...3)]; if rng.bool(0.7) { l.tiltFine = t } else { l.tilt = t } }
        }
        return l
    }
}

final class DirectionDisplayTests: XCTestCase {

    /// 1. The mirror the page schedules from agrees with the real Router's note-on times for every direction, with and without fractional OFFSET / fine TILT, with swing.
    func testTheWalkMirrorsPredictedOnsetsAreTheRoutersNoteOnsForEveryDirectionAndTiming() {
        var rng = DirRng(s: 0xD1EC_0001)
        var checked = 0, timingChecked = 0
        for trial in 0..<120 {
            let line = DirHarness.randomLine(&rng, timing: true)
            let swing = [50, 58, 66][rng.int(0...2)]
            let st = DirHarness.document([line], swing: swing)
            let e = DirHarness.render(st, beats: 18)
            let engine = DirHarness.onsets(e)
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, swingPercent: Double(swing), stepBeats: 0.5) else { XCTFail("no cfg"); continue }
            let horizon = Int64(18.0 / cfg.sub) + 2
            let predicted = (0..<horizon).filter { euclideousWalkTick(cfg, tick: $0).isHit }.map { euclideousWalkRealBeat(cfg, tick: $0) }.filter { $0 < 15.99 }
            XCTAssertEqual(engine.filter { $0 < 15.99 }.count, predicted.count, "trial \(trial) \(line.directionResolved) n\(line.steps) k\(line.pulses) frac \(line.offsetFractionResolved) tiltFine \(line.tiltIsFine): number of strikes: engine \(engine.filter { $0 < 15.99 }.map { String(format: "%.3f", $0) }.suffix(4)) predicted \(predicted.map { String(format: "%.3f", $0) }.suffix(4))")
            for (i, b) in engine.filter({ $0 < 15.99 }).enumerated() where i < predicted.count {
                XCTAssertEqual(b, predicted[i], accuracy: 0.003, "trial \(trial) \(line.directionResolved) n\(line.steps) frac \(line.offsetFractionResolved) tilt \(line.tiltResolved) fine \(line.tiltIsFine) swing \(swing): strike \(i)")
                checked += 1; if !cfg.timing.isNone { timingChecked += 1 }
            }
        }
        XCTAssertGreaterThan(checked, 1500); XCTAssertGreaterThan(timingChecked, 800)
    }

    /// 2. The card's strike flash (`euclideousPulseTileForOnset` fed the comet raw at the onset) lights the BOX the hit is drawn in (`euclideousHitBoxes` of the lane's tick-space layout) — for every direction and timing.
    func testTheStrikeFlashLightsTheBoxTheHitIsDrawnIn() {
        var rng = DirRng(s: 0xD1EC_0002)
        var checked = 0, delayed = 0
        for trial in 0..<150 {
            let line = DirHarness.randomLine(&rng, timing: true)
            let steps = line.steps, dir = line.directionResolved
            let st = DirHarness.document([line])
            let engine = DirHarness.onsets(DirHarness.render(st, beats: 18)).filter { $0 < 17.5 }
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { continue }
            let sub = cfg.sub
            // the box each hit is DRAWN in: the lane's own timing layout mapped back through the direction (what `laneTimingBoxes` hands the bar), or the plain pattern
            let cl = euclidCycleLen(dir, n: steps)
            for b in engine {
                // which tick is it? the one whose real onset is this strike
                let k = Int64((b / sub).rounded(.down)) - 1
                guard let tick = (k...(k + 3)).first(where: { abs(euclideousWalkRealBeat(cfg, tick: $0) - b) < 0.003 && euclideousWalkTick(cfg, tick: $0).isHit }) else { XCTFail("trial \(trial): no tick for onset \(b)"); continue }
                let drawnBox = euclidReadIndex(Int(((tick % Int64(cl)) + Int64(cl)) % Int64(cl)), n: steps, dir: dir)
                let raw = euclidCometRaw(mTickBeat: b, sub: sub, spanBeats: 0, n: steps, dir: dir)
                let flashed = euclideousPulseTileForOnset(rawAtOnset: raw, n: steps, dir: dir)
                let delay = (b / sub) - Double(tick)
                if delay > 0.01 { delayed += 1 }
                XCTAssertEqual(flashed, drawnBox, "trial \(trial) \(dir) n\(steps) frac \(line.offsetFractionResolved) tilt \(line.tiltResolved) fine \(line.tiltIsFine): the onset sits \(String(format: "%.2f", delay)) step into tick \(tick); the flash lights box \(flashed) but the hit is drawn in box \(drawnBox)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 1000); XCTAssertGreaterThan(delayed, 300, "the fuzz really exercises delayed hits")
    }

    /// 3. Changing the direction while the transport plays: nothing sticks, and the strikes follow the OLD direction's mirror up to the edit and the NEW direction's from the next window on (the walk is a pure function of the beat).
    func testSwitchingDirectionMidPlayLeavesNoStuckNoteAndEachSideFollowsItsOwnDirectionsMirror() {
        var rng = DirRng(s: 0xD1EC_0005)
        for trial in 0..<60 {
            let a = DirHarness.randomLine(&rng, timing: rng.bool(0.5))
            var b = a
            b.direction = ([.fwd, .bkw, .pingpong].filter { $0 != a.directionResolved })[rng.int(0...1)]
            let e = DirHarness.render(DirHarness.document([a]), beats: 18, switchAt: (6.3, DirHarness.document([b])))
            var open: [UInt16: Int] = [:]
            for ev in e.events { let k = UInt16(ev.cable) << 8 | UInt16(ev.note); if ev.status == 0x90 { open[k, default: 0] += 1 } else if ev.status == 0x80 { open[k, default: 0] -= 1 } }
            XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "trial \(trial) \(a.directionResolved) → \(b.directionResolved): unbalanced note-ons / offs \(open.filter { $0.value != 0 })")
            let engine = DirHarness.onsets(e)
            for (line, lo, hi) in [(a, 0.0, 6.2), (b, 8.5, 15.99)] {
                guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail("no cfg"); continue }
                let horizon = Int64(18.0 / cfg.sub) + 2
                let predicted = (0..<horizon).filter { euclideousWalkTick(cfg, tick: $0).isHit }.map { euclideousWalkRealBeat(cfg, tick: $0) }.filter { $0 > lo && $0 < hi }
                let heard = engine.filter { $0 > lo && $0 < hi }
                // a hit the edit lands inside (the tick was already claimed under the old layout, or its delayed strike moves) may be dropped or doubled once — measured from 2 steps after the edit
                XCTAssertEqual(heard.count, predicted.count, "trial \(trial) \(a.directionResolved) → \(b.directionResolved) window \(lo)…\(hi): heard \(heard.map { String(format: "%.2f", $0) }.suffix(5)) predicted \(predicted.map { String(format: "%.2f", $0) }.suffix(5))")
                for (h, p) in zip(heard, predicted) { XCTAssertEqual(h, p, accuracy: 0.003, "trial \(trial) \(line.directionResolved)") }
            }
        }
    }

    /// 4. The roll behind the MUTE tab's cells (`euclideousLaneRollHits`): one bar per hit, where the Router strikes it, as long as the Router holds it — every direction, with and without fractional OFFSET / fine TILT.
    func testTheRollsBarsAreWhereAndAsLongAsTheRoutersNotesAreForEveryDirection() {
        var rng = DirRng(s: 0xD1EC_0006)
        var checked = 0
        for trial in 0..<100 {
            let line = DirHarness.randomLine(&rng, timing: rng.bool(0.5))
            let e = DirHarness.render(DirHarness.document([line]), beats: 18)
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail("no cfg"); continue }
            let toBeat = { (s: Int64) in Double(s) / DirHarness.sr * DirHarness.tempo / 60 }
            let ons = e.ons.filter { $0.cable == 1 }.map { (note: $0.note, beat: toBeat($0.sample), sample: $0.sample) }.sorted { $0.sample < $1.sample }
            let offs = e.offs.filter { $0.cable == 1 }.map { (note: $0.note, sample: $0.sample) }
            let roll = euclideousLaneRollHits(cfg: cfg, windowStart: 0, windowBeats: 16, minGateBeats: 0.01, rankAt: { col, _ in col + 1 }).filter { $0.beat < 14.8 }
            let heard = ons.filter { $0.beat < 14.8 }
            XCTAssertEqual(roll.count, heard.count, "trial \(trial) \(line.directionResolved) n\(line.steps) frac \(line.offsetFractionResolved) fine \(line.tiltIsFine): roll bars \(roll.map { String(format: "%.2f", $0.beat) }.suffix(4)) vs notes \(heard.map { String(format: "%.2f", $0.beat) }.suffix(4))")
            for (bar, on) in zip(roll, heard) {
                guard let off = offs.first(where: { $0.note == on.note && $0.sample > on.sample }) else { continue }
                let held = toBeat(off.sample) - on.beat
                XCTAssertEqual(bar.beat, on.beat, accuracy: 0.004, "trial \(trial) \(line.directionResolved): bar starts")
                XCTAssertEqual(bar.gateBeats, held, accuracy: 0.01, "trial \(trial) \(line.directionResolved) n\(line.steps) k\(line.pulses) frac \(line.offsetFractionResolved) fine \(line.tiltIsFine) rate \(cfg.sub): the bar at \(String(format: "%.2f", bar.beat)) is \(bar.gateBeats) beats long, the note is held \(held)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 800)
    }

    /// 5. Random mode's RHYTHM picture: its playhead ring sits on the circle position the Router reads at each strike, and that position is a hit of the picture's own pattern — FWD, BKW and PING-PONG.
    func testTheRandomPicturesPlayheadIsTheBoxTheRouterReadsForEveryDirection() {
        var rng = DirRng(s: 0xD1EC_0007)
        var checked = 0, oldFormulaWrong = 0
        for trial in 0..<100 {
            let line = DirHarness.randomLine(&rng, timing: false)
            let n = line.steps, sub = line.rate!.beats, dir = line.directionResolved
            let pattern = euclideousRandomPattern(hits: line.pulses, steps: n, offset: euclideousRandomDisplayedOffset(rotate: line.rotate, steps: n), tilt: line.tiltResolved)
            for b in DirHarness.onsets(DirHarness.render(DirHarness.document([line]), beats: 18)).filter({ $0 < 16 }) {
                let box = euclideousRandomPicturePlayhead(beat: b + 0.002, stepBeats: sub, steps: n, dir: dir)
                XCTAssertTrue(pattern[box], "trial \(trial) \(dir) n\(n) k\(line.pulses) rot \(line.rotate): the Router strikes at beat \(b) but the picture's ring sits on box \(box), a rest of its pattern \(pattern.map { $0 ? 1 : 0 })")
                let old = ((Int(((b + 0.002) / sub).rounded(.down)) % n) + n) % n
                if !pattern[old] { oldFormulaWrong += 1 }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 800); XCTAssertGreaterThan(oldFormulaWrong, 100, "the fuzz really exercises BKW / PING-PONG")
    }

    /// 6. A lane borrowing RHYTHM is DISPLAYED as it plays — FWD over the source's n boxes while its lap is n, and bouncing over the same n boxes (PING-PONG) when its lap is 2n (a PING-PONG source, or a follower with DIRECTION `><`): the lap the strip is predicted from (`euclideousLapHitSteps` with the display direction) is the set of lap-local ticks the Router strikes on, whatever the follower's stale DIRECTION field says.
    func testABorrowingLaneIsDisplayedFwdAndItsLapHitsAreTheTicksTheRouterStrikesOn() {
        var rng = DirRng(s: 0xD1EC_0008)
        var staleWouldDiffer = 0
        for trial in 0..<60 {
            let src = DirHarness.randomLine(&rng, timing: false)
            var f = DirHarness.randomLine(&rng, timing: false, dir: [.bkw, .pingpong][rng.int(0...1)])
            f.setAnswerRhythm(rng.bool() ? .copy : .fill); f.listenSource = 0
            let lines = [src, f]
            guard let eff = euclideousEffectiveHitPattern(lane: 1, lines: lines) else { XCTFail("no pattern"); continue }
            let n = eff.n, lap = eff.lap
            XCTAssertEqual(euclideousLaneDisplayDirection(lane: 1, lines: lines), lap > n ? .pingpong : .fwd, "trial \(trial): drawn by the lap it plays")
            XCTAssertEqual(euclideousLaneDisplayDirection(lane: 0, lines: lines), src.directionResolved, "an own-rhythm lane keeps its own direction")
            let shown = Set(euclideousLapHitSteps(buf: Array(eff.buf.prefix(n)), dir: euclideousLaneDisplayDirection(lane: 1, lines: lines)).map { $0.tick })
            let stale = Set(euclideousLapHitSteps(buf: Array(eff.buf.prefix(n)), dir: f.directionResolved).map { $0.tick })
            if shown != stale { staleWouldDiffer += 1 }
            let sub = eff.rateBeats
            let heard = Set(DirHarness.onsets(DirHarness.render(DirHarness.document(lines), beats: 40), cable: 2).filter { $0 < 36 }.map { Int(($0 / sub + 0.01).rounded(.down)) % lap })
            XCTAssertEqual(shown, heard, "trial \(trial): follower (own \(f.directionResolved)) of n\(n) — lap ticks drawn \(shown.sorted()) vs struck \(heard.sorted())")
        }
        XCTAssertGreaterThan(staleWouldDiffer, 20, "the stale field really would have changed the drawing")
    }

    /// 7. The RHYTHM tab's direction buttons: choosing the direction a lane already RESOLVES to is not an edit (a fresh lane has no stored direction, and nil ≠ `.fwd` to the funnel's `==`, which recorded a phantom undo step).
    func testChoosingTheDirectionTheLaneAlreadyHasChangesNothing() {
        let fresh = EuclidLine()
        var l = fresh
        l.chooseDirection(.fwd)
        XCTAssertEqual(l, fresh, "FWD on a lane that already plays FWD")
        l.chooseDirection(.pingpong)
        XCTAssertEqual(l.directionResolved, .pingpong)
        let ping = l
        l.chooseDirection(.pingpong)
        XCTAssertEqual(l, ping, "PING-PONG on a PING-PONG lane")
        l.chooseDirection(.fwd)
        XCTAssertEqual(l.directionResolved, .fwd); XCTAssertNotEqual(l, ping)
        var legacy = EuclidLine(); legacy.reverse = true
        let legacyBefore = legacy
        legacy.chooseDirection(.bkw)
        XCTAssertEqual(legacy, legacyBefore, "BKW on an old document's reversed lane")
        legacy.chooseDirection(.fwd)
        XCTAssertEqual(legacy.directionResolved, .fwd, "FWD on an old document's reversed lane still switches it")
    }

    // ── a lane that BORROWS its rhythm (ANSWER COPY / FILL) ─────────────────────────────────────────────────────────────────────────────────────────────────────
    /// The engine plays a borrowed pattern in the follower's own tick order, FWD, whatever the follower's own DIRECTION field says (Router `let dir = copyOrFillValid ? .fwd : dir`; the walk config does the same). The one lap function
    /// the engine's mute maths and the MUTE tab share (`euclideousLaneStepGeometry`) has to say the same lap: n, not 2n.
    func testABorrowingLanesLapIsItsSourcesStepCountWhateverItsOwnDirectionFieldSays() {
        var rng = DirRng(s: 0xD1EC_0003)
        for trial in 0..<80 {
            let src = DirHarness.randomLine(&rng, timing: false)
            var f = DirHarness.randomLine(&rng, timing: false, dir: [.bkw, .pingpong][rng.int(0...1)])
            f.setAnswerRhythm(rng.bool() ? .copy : .fill); f.listenSource = 0
            let lines = [src, f]
            guard let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail("no cfg"); continue }
            XCTAssertEqual(cfg.dir, .fwd, "trial \(trial): the walk plays a borrowed pattern FWD")
            let geo = euclideousLaneStepGeometry(lines: lines, lane: 1, defaultRateBeats: 0.25)
            XCTAssertEqual(geo.n, src.steps, "trial \(trial)")
            XCTAssertEqual(geo.cycleLen, euclidCycleLen(cfg.dir, n: cfg.n), "trial \(trial): follower with its own \(f.directionResolved) borrowing lane 1's \(src.steps) steps — the lap the mute maths uses (\(geo.cycleLen)) is not the lap the lane plays (\(euclidCycleLen(cfg.dir, n: cfg.n)))")
        }
    }

    /// The same, heard: the MUTE tab's cells for an OUTPUT span `passes` of its HOME lane's pass. Output B's home lane is a COPY follower whose own (paused, stale) DIRECTION is PING-PONG / BKW: its pass is the source's n steps, so
    /// the follower's DIRECTION field must have NO audible effect with a mute block set — the same document with that field FWD sounds identically.
    func testAnOutputMuteOnABorrowingHomeLaneDoesNotDependOnItsStaleDirectionField() {
        var rng = DirRng(s: 0xD1EC_0004)
        var cutSomething = 0
        for trial in 0..<24 {
            var src = DirHarness.randomLine(&rng, timing: false, dir: .fwd)
            src.steps = 8; src.pulses = rng.int(3...8); src.rate = .r1_8
            var f = DirHarness.randomLine(&rng, timing: false, dir: [.bkw, .pingpong][rng.int(0...1)])
            f.setAnswerRhythm(.copy); f.listenSource = 0
            var fwd = f; fwd.direction = .fwd
            var mutes = EuclideousOutputMutes(); mutes[1] = EuclideousOutputMute(cells16: 0x00FF, passes: 1)
            var stale = DirHarness.document([src, f]), plain = DirHarness.document([src, fwd]), unmuted = DirHarness.document([src, fwd])
            stale.euclideousOutputMutes = mutes; plain.euclideousOutputMutes = mutes
            let heardStale = DirHarness.onsets(DirHarness.render(stale, beats: 34), cable: 2).filter { $0 < 32 }
            let heardFwd = DirHarness.onsets(DirHarness.render(plain, beats: 34), cable: 2).filter { $0 < 32 }
            let all = DirHarness.onsets(DirHarness.render(unmuted, beats: 34), cable: 2).filter { $0 < 32 }
            if heardFwd.count < all.count { cutSomething += 1 }
            XCTAssertEqual(heardStale.count, heardFwd.count, "trial \(trial) (follower's own \(f.directionResolved)): stale-direction follower heard \(heardStale.map { String(format: "%.2f", $0) }.prefix(14)), the same lane with FWD \(heardFwd.map { String(format: "%.2f", $0) }.prefix(14))")
        }
        XCTAssertGreaterThan(cutSomething, 12, "the mute block really cuts notes in the control run")
    }
}
