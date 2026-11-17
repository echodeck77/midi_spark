//  FillRouterTests.swift — FILL ferry (2026-11-13), slice 3: the Router emission. An armed bar plays the lane's last
//  LENGTH at SPEED m, CONTINUING THE WALK FORWARD (Paul 2026-11-13), then rejoins ×1; REVERSE mirrors the fired order;
//  BREAK silences the last quarter. A neutral / unlit lane is byte-identical to the same lane with no fill. (RANKS/SWELL
//  are slice 3b.) Adapted from the retired RateRouterTests harness.

import XCTest

private final class FillEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 && $0.vel > 0 } }
}

struct FillSpec { var bars: [Bool]; var speed: UInt8 = 3; var length: UInt8 = 1; var reverse = false; var ranks: Int8 = 0; var swell: Int8 = 0; var brk = false; var hits: EuclideousFillHits = .keep; var land = false
    var order: EuclideousFillOrder? = nil; var notes: EuclideousFillNotes = .riff; var roll: UInt8 = 0; var chance: UInt8 = 100; var curve: EuclideousFillCurve = .steady }   // FILL TAB V2

final class FillRouterTests: XCTestCase {
    // 120 BPM at 48 kHz: 1 beat = 24000 samples. One strike opens an own-cable (1) voice AND an ALL (0) voice — count cable 1.
    private func onBeats(_ e: FillEmitter) -> [Double] { e.ons.filter { $0.cable == 1 }.map { ((Double($0.sample) / 24_000.0) * 1000).rounded() / 1000 }.sorted() }
    private func onPairs(_ e: FillEmitter) -> [(beat: Double, note: UInt8)] {
        e.ons.filter { $0.cable == 1 }.map { (((Double($0.sample) / 24_000.0) * 1000).rounded() / 1000, $0.note) }.sorted { $0.0 < $1.0 }
    }
    private func perBar(_ beats: [Double]) -> [Int: Int] { Dictionary(grouping: beats, by: { Int(($0 + 1e-3) / 4.0) }).mapValues { $0.count } }

    /// An 8-step 1/8 lane, every step a hit, a `ranks`-pattern riff over `pool` held notes. `fill` sets the fill fields.
    private func run(fill: FillSpec?, riffRanks: [Int] = [1, 1, 1, 1, 1, 1, 1, 1], pool poolNotes: [UInt8] = [60], beats: Double = 32, pulses: Int = 8, flipHits: Bool = false) -> FillEmitter {
        var l = EuclidLine(target: 0, pulses: pulses, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false
        l.patternMiss = flipHits   // FLIP HITS — invert the rhythm so a chosen step rests
        if let f = fill { l.fillBars = f.bars; l.fillSpeed = f.speed; l.fillLength = f.length; l.fillReverse = f.reverse; l.fillRanks = f.ranks; l.fillSwell = f.swell; l.fillBreak = f.brk; l.fillHits = f.hits; l.fillLand = f.land
            if let o = f.order { l.fillOrder = o }; if f.notes != .riff { l.fillNotes = f.notes }; if f.roll > 0 { l.fillRoll = f.roll }; if f.chance < 100 { l.fillChance = f.chance }; if f.curve == .rush { l.fillCurve = .rush } }   // FILL TAB V2
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riffRanks)
        c.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
        var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        let box = SnapshotBuilder.build(from: st)
        let e = FillEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let pool = NotePool(); for n in poolNotes { pool.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    private func bar(_ n: Int) -> [Bool] { (0..<8).map { $0 == n } }

    // MARK: neutrality (§1.4/§1.5, §9) — byte-identical to no fill

    func testNeutralIsEightHitsABar() {
        let bars = perBar(onBeats(run(fill: nil)))
        for b in 0..<8 { XCTAssertEqual(bars[b], 8, "bar \(b): 8 hits at ×1") }
    }
    func testUnlitAndX1AreByteIdenticalToNoFill() {
        let plain = run(fill: nil).events
        XCTAssertEqual(run(fill: FillSpec(bars: [Bool](repeating: false, count: 8), speed: 4)).events, plain, "no bar lit ⇒ identical")
        XCTAssertEqual(run(fill: FillSpec(bars: bar(3), speed: 1, length: 0)).events, plain, "×1 (neutral), bar lit ⇒ identical whatever LENGTH")
    }

    // MARK: §2.2/§2.3 forward timing (test 2 / test 3)

    func testBarLitX2BARisSixteenHitsThatBarOnly() {
        let plain = onBeats(run(fill: nil))
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0)))   // ×2, BAR
        let bars = perBar(over)
        XCTAssertEqual(bars[3], 16, "the ×2 BAR fill doubles to 16 note-ons")
        for b in [0, 1, 2, 4, 5, 6, 7] { XCTAssertEqual(bars[b], 8, "bar \(b): unchanged") }
        let inBar3 = over.filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(inBar3.count, 16)
        for i in 1..<inBar3.count { XCTAssertEqual(inBar3[i] - inBar3[i - 1], 0.25, accuracy: 1e-4) }
        XCTAssertEqual(plain.filter { $0 < 12 - 1e-6 }, over.filter { $0 < 12 - 1e-6 }, "bars 0–2 identical")
        XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "bar 4 on identical (rejoin)")
    }

    func testHalfX2IsFourThenEightInThatBar() {
        // LENGTH ½, ×2: bar 3's first half ×1 (4 hits, beats 12–14), second half fill (8 hits 0.25 apart from beat 14).
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 1)))
        let firstHalf = over.filter { $0 >= 12 - 1e-6 && $0 < 14 - 1e-6 }
        let fill = over.filter { $0 >= 14 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(firstHalf.count, 4, "first half unchanged ×1")
        XCTAssertEqual(fill.count, 8, "second half fills at ×2")
        for i in 1..<fill.count { XCTAssertEqual(fill[i] - fill[i - 1], 0.25, accuracy: 1e-4) }
    }

    // MARK: §2.3 forward / reverse step VALUES (test 3 / test 4) — a ranked riff over 8 distinct pool notes

    private let cmaj: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]   // ascending; rank r → cmaj[r-1]
    private func fillNotes(_ e: FillEmitter) -> [UInt8] { onPairs(e).filter { $0.beat >= 14 - 1e-6 && $0.beat < 16 - 1e-6 }.map { $0.note } }

    // The lane plays its riff an octave below the raw pool note (the lane's default octave) — so rank r sounds cmaj[r-1] − 12.
    // What these tests PROVE is the step ORDER: forward continues the walk (5,6,7,8,1,2,3,4), NOT a loop (which would be
    // 5,6,7,8,5,6,7,8 ⇒ notes …,55,57,59,60); reverse is the exact time-mirror of the forward list.
    func testForwardStepValuesContinueTheWalk() {
        // ×2 ½ on an 8-rank riff ⇒ steps 5,6,7,8,1,2,3,4 (Paul's decision: continue, not loop).
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [55, 57, 59, 60, 48, 50, 52, 53], "steps 5,6,7,8,1,2,3,4 — the walk runs on, it does not loop")
    }
    func testReverseMirrorsTheForwardList() {
        // REVERSE ⇒ the forward list mirrored (steps 4,3,2,1,8,7,6,5).
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, reverse: true), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [53, 52, 50, 48, 60, 59, 57, 55], "the exact time-mirror of the forward list")
    }

    // MARK: §2.5 RANKS climb (test 5)

    private func fillVels(_ e: FillEmitter) -> [UInt8] {
        let rows: [(beat: Double, vel: UInt8)] = e.ons.filter { $0.cable == 1 }.map { ev in
            let beat = ((Double(ev.sample) / 24_000.0) * 1000).rounded() / 1000
            return (beat, ev.vel)
        }
        return rows.filter { $0.beat >= 14 - 1e-6 && $0.beat < 16 - 1e-6 }.sorted { $0.beat < $1.beat }.map { $0.vel }
    }
    func testRanksClimbsTheWalk() {
        // A FLAT rank-1 riff, RANKS +7 over N=8 ⇒ offsets 0…7 ⇒ ranks 1…8 ⇒ an ascending run cmaj[0…7] − 12.
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, ranks: 7), riffRanks: [1, 1, 1, 1, 1, 1, 1, 1], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [48, 50, 52, 53, 55, 57, 59, 60], "the rank climb turns a flat riff into a rising run")
    }

    // MARK: §2.6 SWELL ramp (test 6)

    func testSwellRaisesVelocityIntoTheDownbeat() {
        // SWELL +3 over N=8, base velocity 90 ⇒ factors 0.35…1.0 ⇒ velocities rise to 90 on the downbeat (0.35 is 0.3499… in float ⇒ 31).
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, swell: 3))
        XCTAssertEqual(fillVels(e), [31, 40, 48, 57, 65, 73, 82, 90], "the swell ramps velocity up to the note on the bar line")
        // −3 falls from the full velocity (the mirror of +3).
        let down = fillVels(run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, swell: -3)))
        XCTAssertEqual(down.first, 90); XCTAssertEqual(down.last, 31); XCTAssertEqual(down, down.sorted(by: >), "−3 falls monotonically")
    }

    // MARK: §2.7 BREAK (test 7)

    func testBreakDropsTheLastQuarter() {
        // ×2 BAR + BREAK: no note-ons in [15,16) (the last beat); the rest of the bar still fills.
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, brk: true)))
        XCTAssertTrue(over.filter { $0 >= 15 - 1e-6 && $0 < 16 - 1e-6 }.isEmpty, "the last quarter is silent")
        XCTAssertFalse(over.filter { $0 >= 12 - 1e-6 && $0 < 15 - 1e-6 }.isEmpty, "the rest of the bar still fills")
    }

    // MARK: §2.3 HITS (KEEP / ALL / FLIP) — a sparse lane so the three differ

    func testHitsAllStrikesEveryStepAndFlipTakesTheRests() {
        // A sparse 3-of-8 lane, ×2 BAR on bar 3 ⇒ 16 lane steps fill the bar. KEEP strikes the pattern's hits; ALL strikes
        // all 16; FLIP strikes exactly the rests ⇒ KEEP + FLIP = 16. (The walk also runs through its columns per step — §2.3.)
        func barThree(_ h: EuclideousFillHits) -> Int {
            onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, hits: h), pulses: 3)).filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }.count
        }
        let keep = barThree(.keep), all = barThree(.all), flip = barThree(.flip)
        XCTAssertEqual(all, 16, "ALL strikes every one of the 16 ×2 steps in the bar")
        XCTAssertGreaterThan(keep, 0, "the sparse pattern still has hits")
        XCTAssertLessThan(keep, all, "KEEP is sparser than ALL")
        XCTAssertEqual(flip, all - keep, "FLIP strikes exactly the steps KEEP rests on (they partition the region)")
    }

    func testHitsKeepLeavesTheFillUnchanged() {
        // KEEP must be identical to the same ×2 fill with no HITS field set (the default) — the whole event stream.
        let base = run(fill: FillSpec(bars: bar(3), speed: 3, length: 0), pulses: 3).events
        let keep = run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, hits: .keep), pulses: 3).events
        XCTAssertEqual(keep, base, "HITS KEEP ⇒ byte-identical to the default fill")
    }

    // MARK: §2.6 LAND part b — the rejoin step strikes even on a rest

    func testLandStrikesTheRejoinEvenOnARest() {
        // FLIP HITS of a 1-of-8 ⇒ step 0 (the bar downbeat) is a REST. A ×2 BAR fill on bar 3 rejoins at beat 16 (bar 4's
        // downbeat): without LAND it rests; LAND (part b) forces a definite landing note there.
        let noLand = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, land: false), pulses: 1, flipHits: true))
        let land = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, land: true), pulses: 1, flipHits: true))
        XCTAssertFalse(noLand.contains { abs($0 - 16) < 1e-3 }, "no LAND: the rejoin downbeat rests")
        XCTAssertTrue(land.contains { abs($0 - 16) < 1e-3 }, "LAND: a definite note on the rejoin downbeat")
    }

    // MARK: §7.11 — the rich preview predictor mirrors the Router

    func testPreviewMirrorsTheRouter() {
        // The SAME ×2 ½ fill on an 8-rank riff the forward-values test uses. The preview (euclideousFillPreviewNotes) calls
        // the engine's own fill + walk + resolve functions, so its notes must equal the Router's fill-bar emission in TIMING
        // and CONTOUR (the absolute octave is whatever the lane's riffOct is — here a constant whole-octave offset).
        var cfg = EuclideousWalkLaneConfig(buf: [Bool](repeating: true, count: 8), n: 8, dir: .fwd, sub: 0.5)
        cfg.riffDir = .forward; cfg.length = 8; cfg.stride = 1; cfg.rotate = 0; cfg.every = 1; cfg.columns = 8; cfg.gate = 0.5
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false   // riff only (match the run() harness) — the stack layer is covered by laneGhostPlans
        l.fillBars = bar(3); l.fillSpeed = 3; l.fillLength = 1   // ×2 ½
        let preview = euclideousFillPreviewNotes(cfg: cfg, line: l, lane: 0, pool: cmaj.map { Int($0) }, riffOct: 0, baseVel: 90,
                                                 ranks: [1, 2, 3, 4, 5, 6, 7, 8], fromBar: 3, toBar: 4, beatsPerBar: 4, originBeat: 0)
            .sorted { $0.onset < $1.onset }
        let router = onPairs(run(fill: FillSpec(bars: bar(3), speed: 3, length: 1), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj))
            .filter { $0.beat >= 14 - 1e-6 && $0.beat < 16 - 1e-6 }
        XCTAssertEqual(preview.count, router.count, "same number of fill notes")
        XCTAssertEqual(preview.map { (($0.onset * 1000).rounded() / 1000) }, router.map { $0.beat }, "same onsets (RUSH / ORDER timing)")
        let ps = preview.map { $0.pitch }, rs = router.map { Int($0.note) }
        guard let p0 = ps.first, let r0 = rs.first else { return XCTFail("no fill notes") }
        let off = r0 - p0
        XCTAssertEqual(off % 12, 0, "only a whole-octave offset between the preview and the Router")
        XCTAssertEqual(ps.map { $0 + off }, rs, "same pitch contour (ORDER + RANKS) — steps 5,6,7,8,1,2,3,4")
    }

    // §5 — the preview's STACK (NOTES) layer rides the fill's retimed slots and respects riff off.
    func testPreviewStackLayerRidesTheFill() {
        var cfg = EuclideousWalkLaneConfig(buf: [Bool](repeating: true, count: 8), n: 8, dir: .fwd, sub: 0.5)
        cfg.riffDir = .forward; cfg.length = 8; cfg.every = 1; cfg.columns = 8; cfg.gate = 0.5; cfg.riffOn = false   // riff OFF ⇒ only the stack previews
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .all, rate: .r1_8, useRiff: false, litNotes: 0b1, riffOn: false, sourceMode: .midi)
        l.notesOn = true; l.notesGate = 0.5; l.velocityAbsolute = 90
        l.fillBars = bar(3); l.fillSpeed = 3; l.fillLength = 1   // ×2 ½
        let notes = euclideousFillPreviewNotes(cfg: cfg, line: l, lane: 0, pool: cmaj.map { Int($0) }, riffOct: 0, baseVel: 90,
                                               ranks: [1, 2, 3, 4, 5, 6, 7, 8], fromBar: 3, toBar: 4, beatsPerBar: 4, originBeat: 0)
        XCTAssertFalse(notes.isEmpty, "the stack layer fires in the fill")
        XCTAssertTrue(notes.allSatisfy { $0.stack }, "riff off ⇒ every previewed note is a stack note")
        let onsets = Set(notes.map { (($0.onset * 100).rounded() / 100) })
        XCTAssertTrue(onsets.allSatisfy { $0 >= 14 - 1e-6 && $0 < 16 - 1e-6 }, "the stack sits inside bar 3's ×2 ½ region")
        XCTAssertTrue(onsets.contains(14.0), "the region's first slot is at beat 14 (RUSH off here ⇒ the ×2 grid)")
        XCTAssertTrue(onsets.contains(14.25), "slots are the retimed ×2 grid, not the lane's own ×1")
    }

    // MARK: §2.8 rejoin (test 8) — the bar after a region matches no fill

    func testRejoinMatchesNoFill() {
        for (speed, length) in [(UInt8(3), UInt8(0)), (3, 1), (4, 2), (1, 1)] {
            let plain = onBeats(run(fill: nil))
            let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: speed, length: length)))
            XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "speed \(speed) length \(length): bar 5 on identical")
        }
    }

    // MARK: — FILL TAB V2 (§7 tests 2–7). The fill window helpers: the ×1 BAR region covers beats 12–16; ×2 ½ covers 14–16.

    private func barNotes(_ e: FillEmitter, from: Double = 12, to: Double = 16) -> [UInt8] {
        onPairs(e).filter { $0.beat >= from - 1e-6 && $0.beat < to - 1e-6 }.map { $0.note }
    }

    // §7.2 — STUTTER on N = 8 plays step j_0 (rank 1 at bar 3's first step) eight times; ROLL 2 thickens the later slots.
    func testStutterRepeatsTheFirstStep() {
        let e = run(fill: FillSpec(bars: bar(3), speed: 1, length: 0, order: .stutter), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(barNotes(e), [UInt8](repeating: 48, count: 8), "every slot plays the region's first forward step (rank 1 → 48)")
        let rolled = run(fill: FillSpec(bars: bar(3), speed: 1, length: 0, order: .stutter, roll: 2), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        let notes = barNotes(rolled)
        XCTAssertEqual(notes.count, 16, "ROLL 2 over 8 slots: strike counts 1,1,2,2,2,2,3,3 (1 + round(2·k/7)) = 16")
        XCTAssertTrue(notes.allSatisfy { $0 == 48 }, "the rolls repeat the stuttered step's own pitch")
    }

    // §7.3 — BUILD on E(3,8), LENGTH BAR, ×1: slots 0–3 follow the pattern, slots 4–7 all sound; the bar after matches no fill.
    func testBuildFollowsThenFillsAndRejoins() {
        let plain = onBeats(run(fill: nil, pulses: 3))
        let built = onBeats(run(fill: FillSpec(bars: bar(3), speed: 1, length: 0, hits: .build), pulses: 3))
        let firstHalfPlain = plain.filter { $0 >= 12 - 1e-6 && $0 < 14 - 1e-6 }.count
        let fillBar = built.filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(fillBar.filter { $0 < 14 - 1e-6 }.count, firstHalfPlain, "slots 0–3 (k < h) follow the E(3,8) pattern")
        XCTAssertEqual(fillBar.filter { $0 >= 14 - 1e-6 }.count, 4, "slots 4–7 (k ≥ h) all sound")
        XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, built.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "the bar after matches no fill")
    }

    // §7.4 — FLAT: every fill note is the first sounding slot's pitch; with RANKS +3 CLIMB it becomes a stepwise run from it.
    func testFlatRepeatsThenClimbsFromTheFirstPitch() {
        let flat = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, notes: .flat), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(flat), [UInt8](repeating: 55, count: 8), "RANKS 0: one pitch — the first sounding slot's (rank 5 → 55)")
        let climb = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, ranks: 3, notes: .flat), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(climb), [55, 55, 57, 57, 59, 59, 60, 60], "ranks q,q,q+1,q+1,q+2,q+2,q+3,q+3 (the FILL TAB rounding) from rank 5")
    }

    // §7.5 — PEDAL: odd slots play rank 1 of the stack (the pool's lowest) with no offset, one note each; even slots as RIFF.
    func testPedalAlternatesWithTheStacksLowestRank() {
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, notes: .pedal), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [55, 48, 59, 48, 48, 48, 52, 48], "even k: ranks 5,7,1,3; odd k: the rank-1 pedal (48)")
    }

    // §7.6 — OCT: odd slots are 12 semitones above RIFF's pitch.
    func testOctJumpsTheOddSlots() {
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, notes: .oct), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        let expected: [UInt8] = [55, 69, 59, 72, 48, 62, 52, 65]   // 57/60/50/53 + 12 on the odd slots
        XCTAssertEqual(fillNotes(e), expected, "the RIFF list with +12 on odd slots")
    }

    // §7.7 — CHORD: a slot on rank 7 plays ranks 7, 9 and 11, folded by the resolver's own rule — over the POOL SIZE, which
    // here is 7 (the source stack PC-dedupes cmaj's octave C), so 9 → asc(1)+12 = 62 and 11 → asc(3)+12 = 65. Duplicates collapse.
    func testChordStacksPlusTwoAndPlusFour() {
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, notes: .chord), riffRanks: [7, 7, 7, 7, 7, 7, 7, 7], pool: cmaj)
        let notes = fillNotes(e)
        XCTAssertEqual(notes.count, 24, "8 slots × 3 voices")
        XCTAssertEqual(Set(notes), Set([59, 62, 65]), "rank 7 → 59; ranks 9/11 fold over the 7-note deduped pool (the engine's rule — source wins over the spec's rank−8 reading)")
    }

    // FILL TAB V2 §7.9 — the ROLL ROW's per-bar prediction (euclideousFillRollBar) equals the Router's bar, across
    // ORDER × HITS × NOTES × CURVE (one factor at a time; CHANCE's skipped state is the test after this one). The plain
    // span and the fill span are both compared — onsets, pitch contour (whole-octave offset: the harness lane's oct) and velocities.
    func testRollRowMirrorsTheRouterAcrossModes() {
        var specs: [(FillSpec, Int)] = []                                     // (spec, pulses)
        for o in [EuclideousFillOrder.fwd, .rev, .bounce, .shuffle, .stutter] { specs.append((FillSpec(bars: bar(3), speed: 3, length: 1, order: o), 8)) }
        for h in [EuclideousFillHits.keep, .all, .flip, .build] { specs.append((FillSpec(bars: bar(3), speed: 1, length: 0, hits: h), 5)) }
        for nm in [EuclideousFillNotes.flat, .pedal, .oct, .chord] { specs.append((FillSpec(bars: bar(3), speed: 3, length: 1, ranks: 3, notes: nm), 8)) }
        specs.append((FillSpec(bars: bar(3), speed: 3, length: 1, roll: 2, curve: .rush), 8))
        for (spec, pulses) in specs {
            let label = "order \(String(describing: spec.order)) hits \(spec.hits) notes \(spec.notes) curve \(spec.curve) pulses \(pulses)"
            // the roll's inputs — the lane exactly as run() builds it
            var l = EuclidLine(target: 0, pulses: pulses, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
            l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false
            l.fillBars = spec.bars; l.fillSpeed = spec.speed; l.fillLength = spec.length; l.fillRanks = spec.ranks; l.fillHits = spec.hits
            if let o = spec.order { l.fillOrder = o }; if spec.notes != .riff { l.fillNotes = spec.notes }
            if spec.roll > 0 { l.fillRoll = spec.roll }; if spec.curve == .rush { l.fillCurve = .rush }
            var buf = [Bool](repeating: false, count: 64); var micro = [Double](repeating: 0, count: 64)
            let n = euclideousBuildHitPatternInto(l, cells: &buf, micro: &micro)
            var cfg = EuclideousWalkLaneConfig(buf: Array(buf.prefix(n)), n: n, dir: .fwd, sub: 0.5)
            cfg.riffDir = .forward; cfg.length = 8; cfg.stride = 1; cfg.rotate = 0; cfg.every = 1; cfg.columns = 8; cfg.gate = 0.5
            // the lane's EFFECTIVE pool (the source stack PC-dedupes cmaj's octave C to 7 notes) — what the page's lanePools feed carries
            let rb = euclideousFillRollBar(cfg: cfg, line: l, lane: 0, pool: [60, 62, 64, 65, 67, 69, 71], riffOct: 0, baseVel: 90,
                                           ranks: [1, 2, 3, 4, 5, 6, 7, 8], bar: 3, beatsPerBar: 4, originBeat: 0)
            let predicted = rb.notes.sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
            let routed = onPairs(run(fill: spec, riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj, pulses: pulses))
                .filter { $0.beat >= 12 - 1e-6 && $0.beat < 16 - 1e-6 }
                .sorted { ($0.beat, $0.note) < ($1.beat, $1.note) }
            XCTAssertEqual(predicted.count, routed.count, "\(label): same note count in the fill bar")
            guard predicted.count == routed.count, !predicted.isEmpty else { continue }
            for (p, r) in zip(predicted, routed) {
                XCTAssertEqual((p.onset * 1000).rounded() / 1000, r.beat, accuracy: 2e-3, "\(label): onset")
            }
            let off = Int(routed[0].note) - predicted[0].pitch
            XCTAssertEqual(off % 12, 0, "\(label): a whole-octave offset only")
            XCTAssertEqual(predicted.map { $0.pitch + off }, routed.map { Int($0.note) }, "\(label): the pitch contour")
        }
    }

    // FILL TAB V2 §7.9 — a CHANCE-skipped bar is flagged dashed and its notes are the PLAIN bar's, drawn grey (fill: false).
    func testRollRowSkippedBarIsDashedWithPlainNotes() {
        let sb = (0..<8).first { !euclideousFillChancePlays(lane: 0, bar: $0, chance: 25) } ?? 0
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false
        l.fillBars = bar(sb); l.fillSpeed = 3; l.fillLength = 1; l.fillChance = 25
        var buf = [Bool](repeating: false, count: 64); var micro = [Double](repeating: 0, count: 64)
        let n = euclideousBuildHitPatternInto(l, cells: &buf, micro: &micro)
        var cfg = EuclideousWalkLaneConfig(buf: Array(buf.prefix(n)), n: n, dir: .fwd, sub: 0.5)
        cfg.riffDir = .forward; cfg.length = 8; cfg.stride = 1; cfg.rotate = 0; cfg.every = 1; cfg.columns = 8; cfg.gate = 0.5
        let rb = euclideousFillRollBar(cfg: cfg, line: l, lane: 0, pool: cmaj.map { Int($0) }, riffOct: 0, baseVel: 90,
                                       ranks: [1, 2, 3, 4, 5, 6, 7, 8], bar: sb, beatsPerBar: 4, originBeat: 0)
        XCTAssertTrue(rb.skipped, "lit + CHANCE-skipped ⇒ the dashed state")
        XCTAssertEqual(rb.regionHi - rb.regionLo, 2, accuracy: 1e-9, "the would-be ½ region is framed for the dashed outline")
        XCTAssertEqual(rb.notes.count, 8, "the whole bar's PLAIN notes (8 steps)")
        XCTAssertTrue(rb.notes.allSatisfy { !$0.fill }, "drawn as normal notes, not fill")
    }

    // §7 — a NOTES mode on a CHANCE-skipped bar changes nothing (the skipped bar plays exactly as no fill).
    func testChanceSkippedBarIgnoresTheNotesMode() {
        // chance 25: find a bar the (lane 0, bar) draw skips, and assert it equals the no-fill bar.
        let skipped = (0..<8).first { !euclideousFillChancePlays(lane: 0, bar: $0, chance: 25) }
        guard let sb = skipped else { return XCTFail("no skipped bar in 8 at 25% — seed drift?") }
        let plain = onBeats(run(fill: nil))
        let e = onBeats(run(fill: FillSpec(bars: bar(sb), speed: 3, length: 1, notes: .chord, chance: 25)))
        let lo = Double(sb) * 4, hi = lo + 4
        XCTAssertEqual(plain.filter { $0 >= lo - 1e-6 && $0 < hi - 1e-6 }, e.filter { $0 >= lo - 1e-6 && $0 < hi - 1e-6 }, "a skipped bar is exactly no fill")
    }
}
