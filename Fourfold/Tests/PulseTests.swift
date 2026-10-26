//  PulseTests.swift
//  PULSE ferry (2026-10-20, "strikes that show velocity on the comet bar, riff arrows, MIX pads and OUT rings, and riff rests the comet passes through"): the pure surface — the envelope, the gap decision, the level mark,
//  the tail, the ripple, the ring, the Reduce Motion / OFF filter, the strike feed and the comet-tile mapping. The Router side (the event's velocities) lives in RouterTests next to the harness it needs.

import XCTest

final class PulseTests: XCTestCase {

    private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, b, accuracy: eps, msg, file: file, line: line) }

    // MARK: 1. vis
    func testVisIs02AtZeroOneAtFullAndAboutHalfAtMidVelocity() {
        near(euclideousPulseVis(0), 0.2); near(euclideousPulseVis(127), 1.0); near(euclideousPulseVis(64), 0.2 + 0.8 * pow(64.0 / 127.0, 1.3))
        XCTAssertEqual(euclideousPulseVis(64), 0.53, accuracy: 0.01)
        XCTAssertEqual(euclideousPulseVis(300), 1.0, "clamped"); XCTAssertEqual(euclideousPulseVis(-4), 0.2)
        var last = 0.0; for v in 0...127 { let x = euclideousPulseVis(v); XCTAssertGreaterThanOrEqual(x, last); last = x }
    }

    // MARK: 2. envelopes
    func testEnvelopesDecayWithTheirOwnTimeConstantsAndScaleWithPAndVelocity() {
        for v in [127, 40] {
            let vis = euclideousPulseVis(v)
            for t in [0.0, 0.05, 0.16, 1.5] {
                func expect(_ p: Double) -> (b: Double, f: Double, k: Double, a: Double) {
                    (min(1, vis * p * exp(-t / 0.05)), min(1, vis * p * exp(-t / 0.16)), min(1, vis * p * exp(-t / 0.08)), min(1, vis * p * exp(-t / 0.35)))
                }
                for p in [1.0, 0.6] {
                    let want = expect(p), e = euclideousPulseEnvelopes(velocity: v, seconds: t, scale: p)
                    if max(want.b, want.f, want.k, want.a) < 0.01 {
                        XCTAssertEqual(e, .none, "v \(v) t \(t) P \(p): every value under 0.01 draws nothing")
                    } else {
                        near(e.b, want.b, 1e-9, "b v\(v) t\(t) P\(p)"); near(e.f, want.f, 1e-9, "f"); near(e.k, want.k, 1e-9, "k"); near(e.a, want.a, 1e-9, "a")
                    }
                }
                XCTAssertEqual(euclideousPulseEnvelopes(velocity: v, seconds: t, scale: 0), .none, "OFF")
            }
        }
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: 1.5001, scale: 1), .none, "older than 1.5 s draws nothing")
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: -0.01, scale: 1), .none, "a strike that hasn't happened yet")
        XCTAssertGreaterThan(euclideousPulseEnvelopes(velocity: 127, seconds: 0.0, scale: 1).b, euclideousPulseEnvelopes(velocity: 40, seconds: 0.0, scale: 1).b, "louder = brighter")
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: 0, scale: 1).b, 1, accuracy: 1e-12); XCTAssertLessThanOrEqual(euclideousPulseEnvelopes(velocity: 127, seconds: 0, scale: 1).k, 1)
        XCTAssertEqual(euclideousPulseScale(level: 0), 0); XCTAssertEqual(euclideousPulseScale(level: 1), 0.6); XCTAssertEqual(euclideousPulseScale(level: 2), 1); XCTAssertEqual(euclideousPulseScale(level: 9), 1)
    }

    // MARK: 3. gaps
    func testAGapIsAHitOnARiffRestUnderSkipOrTieAndNothingElse() {
        // the harness lane (RIFF ferry §11): 8 steps of 1/8, hits on 1, 3, 5, 6, 8; the riff has a REST in column 3 (index 2), FWD, LEN 8
        let hitSteps = euclideousLapHitSteps(pulses: 5, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: [true, false, true, false, true, true, false, true])
        let ranks = [5, 3, 0, 4, 6, 2, 7, 1]
        func gaps(startOrd: Int64, onRest: EuclidRiffOnRest, riffOn: Bool = true) -> [Bool] {
            let pred = euclideousRiffCyclePrediction(hitSteps: hitSteps, advanceStep: false, dir: .forward, stride: 1, length: 8, rotate: 0, seed: 0, startOrd: startOrd)
            let states = euclideousFooterStates(hitSteps: hitSteps, lapSteps: 8, prediction: riffOn ? pred : nil, riffRanksResolved: ranks, anyLit: true)
            return states.map { euclideousPulseIsGap(state: $0, onRest: onRest, riffOn: riffOn) }
        }
        // pass 0 reads columns 1 2 3 4 5 on its five hits: the THIRD hit (step 5) reads column 3, the rest
        for onRest in [EuclidRiffOnRest.skip, .tie] {
            XCTAssertEqual(gaps(startOrd: 0, onRest: onRest), [false, false, false, false, true, false, false, false], "\(onRest.rawValue): pass 0 — the hit on step 5 reads column 3")
            XCTAssertEqual(gaps(startOrd: 5, onRest: onRest), [false, false, false, false, false, false, false, false], "\(onRest.rawValue): pass 1 reads columns 6 7 8 1 2 — no gap")
            XCTAssertEqual(gaps(startOrd: 2, onRest: onRest), [true, false, false, false, false, false, false, false], "\(onRest.rawValue): a pass that starts on column 3 gaps its FIRST hit")
        }
        XCTAssertEqual(gaps(startOrd: 0, onRest: .repeatLast), Array(repeating: false, count: 8), "REPEAT strikes: not a gap")
        XCTAssertEqual(gaps(startOrd: 0, onRest: .skip, riffOn: false), Array(repeating: false, count: 8), "the riff off: no gaps")
        XCTAssertFalse(euclideousPulseIsGap(state: .hitTied(riffStep: 3), onRest: .skip, riffOn: true), "an FX-tied hit is not a riff rest — Paul 2026-10-20")
        XCTAssertFalse(euclideousPulseIsGap(state: .miss, onRest: .skip, riffOn: true)); XCTAssertFalse(euclideousPulseIsGap(state: .hit(riffStep: 2), onRest: .skip, riffOn: true))
    }

    // MARK: 6. the ripple
    func testRippleGrowsWithVelocityAndFadesOut() {
        let end = euclideousPulseRipple(d0: 12, velocity: 127, seconds: 0.3599, scale: 1)!
        XCTAssertEqual(end.diameter, 12 + 44, accuracy: 0.05); XCTAssertEqual(end.opacity, 0, accuracy: 0.01)
        XCTAssertNil(euclideousPulseRipple(d0: 12, velocity: 127, seconds: 0.36, scale: 1), "gone after 0.36 s")
        // p = 0.5, vis 0.2 (v 0): diameter d0 + 10.56 at opacity 0.1 × P
        for p in [1.0, 0.6] {
            let r = euclideousPulseRipple(d0: 12, velocity: 0 + 1, seconds: 0.18, scale: p)!   // v 1 ≈ vis 0.2
            let vis = euclideousPulseVis(1)
            XCTAssertEqual(Double(r.diameter), 12 + 22 * (0.35 + 0.65 * vis), accuracy: 1e-6); XCTAssertEqual(r.opacity, 0.5 * vis * p, accuracy: 1e-9)
        }
        XCTAssertEqual(euclideousPulseRipple(d0: 12, velocity: 127, seconds: 0.18, scale: 1)!.diameter, 12 + 22, accuracy: 1e-6, "vis 1 at p 0.5")
        XCTAssertNil(euclideousPulseRipple(d0: 12, velocity: 100, seconds: 0.1, scale: 0), "OFF")
        // the ferry's own worked numbers, literally (vis 0.2, p 0.5): diameter d0 + 10.56 at opacity 0.1 × P — and at p = 1, vis 1: d0 + 44 at opacity 0
        for p in [1.0, 0.6] {
            let r = euclideousPulseRipple(d0: 12, vis: 0.2, progress: 0.5, scale: p)
            XCTAssertEqual(Double(r.diameter), 12 + 10.56, accuracy: 1e-9); XCTAssertEqual(r.opacity, 0.1 * p, accuracy: 1e-12)
        }
        let full = euclideousPulseRipple(d0: 12, vis: 1, progress: 1, scale: 1)
        XCTAssertEqual(Double(full.diameter), 56, accuracy: 1e-9); XCTAssertEqual(full.opacity, 0, accuracy: 1e-12)
    }

    // MARK: 7. the ring
    func testRingStrokeAndLetter() {
        XCTAssertEqual(euclideousPulseRingStroke(f: 1), 5); XCTAssertEqual(euclideousPulseRingStroke(f: 0), 2.5); XCTAssertEqual(euclideousPulseRingStroke(f: 0.5), 3.75); XCTAssertEqual(euclideousPulseRingStroke(f: 9), 5)
        XCTAssertTrue(euclideousPulseNameLit(f: 0.13)); XCTAssertFalse(euclideousPulseNameLit(f: 0.12))
    }

    // MARK: 8. Reduce Motion / OFF
    func testTheReduceMotionAndOffFilter() {
        for e in EuclideousPulseEffect.allCases { XCTAssertEqual(euclideousPulseFilter(e, scale: 0, reduceMotion: false), .off, "OFF: \(e)"); XCTAssertEqual(euclideousPulseFilter(e, scale: 0, reduceMotion: true), .off) }
        for e in EuclideousPulseEffect.allCases { XCTAssertEqual(euclideousPulseFilter(e, scale: 1, reduceMotion: false), .full, "FULL: \(e)") }
        for e in [EuclideousPulseEffect.keyDipMove, .ripple, .puckSwell, .arrowScale] { XCTAssertEqual(euclideousPulseFilter(e, scale: 1, reduceMotion: true), .off, "Reduce Motion: no \(e)") }
        for e in [EuclideousPulseEffect.glow, .wash, .overlay, .noteName, .letter] { XCTAssertEqual(euclideousPulseFilter(e, scale: 0.6, reduceMotion: true), .full, "Reduce Motion keeps \(e)") }
    }

    // MARK: the feed, the ruling, the tile mapping
    private func ev(_ onset: Double, notes: [UInt8], vels: [UInt8], riff: Bool, kind: UInt8 = 0) -> Router.EuclideousNoteViewEventSnapshot {
        var e = Router.EuclideousNoteViewEventSnapshot(onsetBeat: onset, durationBeat: 0.25, kind: kind, notes: notes); e.hasRiffNote = riff; e.vels = vels; return e
    }
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private func ingest(_ f: EuclideousPulseFeed, _ lane: Int, _ events: [Router.EuclideousNoteViewEventSnapshot]) { f.ingest(lane: lane, events: events, anchorBeat: 0, anchorAt: t0, tempo: 120) }
    func testTheFeedKeepsRiffAndNotesVelocitiesAndStampsTheDisplayClockOnset() {
        let f = EuclideousPulseFeed()
        f.noteTransport(playing: true, at: t0)
        ingest(f, 1, [ev(1, notes: [60, 55, 56], vels: [100, 70, 90], riff: true), ev(2, notes: [], vels: [], riff: false, kind: 2), ev(3, notes: [55, 56], vels: [40, 80], riff: false), ev(4, notes: [60], vels: [110], riff: true, kind: 3)])
        let s = f.strikes(lane: 1)
        XCTAssertEqual(s.map { [$0.onsetBeat, Double($0.riffVel), Double($0.notesVel)] }, [[1, 100, 90], [3, 0, 80], [4, 110, 0]],
                       "a rest flash (kind 2) is not a strike; the notes layer's velocity is the louder of its notes")
        // the anchor is beat 0 at t0, 120 BPM: beat b is b × 0.5 s after t0 — wall time, fixed at arrival
        XCTAssertEqual(s.map { $0.onsetAt - t0.timeIntervalSinceReferenceDate }, [0.5, 1.5, 2.0])
        XCTAssertEqual(f.latestHappened(lane: 1, now: .infinity, riff: true)?.onsetBeat, 4); XCTAssertEqual(f.latestHappened(lane: 1, now: .infinity, riff: false)?.onsetBeat, 3); XCTAssertNil(f.latest(lane: 0))
        // a beat that goes back (a restart or a loop) drops the old strikes
        ingest(f, 1, [ev(0.5, notes: [60], vels: [90], riff: true)]); XCTAssertEqual(f.strikes(lane: 1).count, 1)
        // a stop stamps the moment and settles for 1.5 s; a start clears the last run
        f.noteTransport(playing: false, at: t0); XCTAssertTrue(f.isSettling(now: t0.addingTimeInterval(1.4))); XCTAssertFalse(f.isSettling(now: t0.addingTimeInterval(1.6)))
        f.noteTransport(playing: false, at: t0.addingTimeInterval(1)); XCTAssertEqual(f.stoppedAt, t0, "a second 'stopped' reading is not a new edge")
        f.noteTransport(playing: true, at: t0.addingTimeInterval(5)); XCTAssertTrue(f.strikes(lane: 1).isEmpty, "a start drops the strikes of the last run…"); XCTAssertNil(f.stoppedAt)
        f.noteTransport(playing: false, at: t0.addingTimeInterval(5.1))
        f.ingest(lane: 0, events: [ev(1, notes: [60], vels: [90], riff: true)], anchorBeat: 0, anchorAt: t0.addingTimeInterval(5.05), tempo: 120)   // a strike that arrived just before the start edge was read
        f.noteTransport(playing: true, at: t0.addingTimeInterval(5.2)); XCTAssertEqual(f.strikes(lane: 0).count, 1, "…but not one that belongs to the new run (within 0.5 s of the start)")
        f.noteTransport(playing: true, at: t0.addingTimeInterval(6)); ingest(f, 1, [ev(1, notes: [60], vels: [90], riff: true)]); f.noteTransport(playing: true, at: t0.addingTimeInterval(7)); XCTAssertEqual(f.strikes(lane: 1).count, 1, "playing again is not an edge")
        // the ring is bounded
        ingest(f, 2, (0..<200).map { ev(Double($0), notes: [60], vels: [90], riff: true) }); XCTAssertEqual(f.strikes(lane: 2).count, EuclideousPulseFeed.ringCap)
        // an event without velocities (should not happen) still pulses, at a middling 100
        ingest(f, 3, [ev(1, notes: [60], vels: [], riff: true)]); XCTAssertEqual(f.strikes(lane: 3).first?.riffVel, 100)
    }
    func testTileMappingAndPerTileLatestStrikes() {
        // FWD: tick k reads step k; BKW reads n−1−k; PING-PONG n−1, … bounces
        XCTAssertEqual((0..<8).map { euclideousPulseTileForOnset(rawAtOnset: Double($0) - 1e-9, n: 8, dir: .fwd) }, Array(0..<8), "a hair under the tick still rounds to it")
        XCTAssertEqual((0..<8).map { euclideousPulseTileForOnset(rawAtOnset: Double($0), n: 8, dir: .bkw) }, [7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertEqual((0..<16).map { euclideousPulseTileForOnset(rawAtOnset: Double($0), n: 8, dir: .pingpong) }, [0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 0])
        // strikes at beats 0 (tile 0), 0.5 (tile 1), 1.0 (tile 2), 4.0 (tile 0 again), 4.5 (tile 1); 120 BPM, 1/8 steps (0.5 beat = 0.25 s); onsetAt = beat × 0.5 s
        func st(_ b: Double, _ r: UInt8, _ n: UInt8) -> EuclideousPulseStrike { EuclideousPulseStrike(onsetBeat: b, onsetAt: b * 0.5, riffVel: r, notesVel: n) }
        let strikes = [st(0, 100, 0), st(0.5, 0, 80), st(1.0, 60, 0), st(4.0, 60, 0), st(4.5, 110, 0)]
        let tileOf: (Double) -> Int = { euclideousPulseTileForOnset(rawAtOnset: $0 / 0.5, n: 8, dir: .fwd) }
        let feed = EuclideousPulseFeed()
        feed.ingest(lane: 0, events: strikes.map { s in var e = Router.EuclideousNoteViewEventSnapshot(onsetBeat: s.onsetBeat, durationBeat: 0.25, kind: 0, notes: [60, 55]); e.hasRiffNote = s.riffVel > 0; e.vels = s.riffVel > 0 ? [s.riffVel, s.notesVel] : [s.notesVel, s.notesVel]; return e },
                    anchorBeat: 0, anchorAt: Date(timeIntervalSinceReferenceDate: 0), tempo: 120)
        let resolved = feed.resolveTiles(lane: 0, key: 7, tileOf: tileOf)
        XCTAssertEqual(resolved.map { Int($0.tile) }, [0, 1, 2, 0, 1])
        var calls = 0
        _ = feed.resolveTiles(lane: 0, key: 7, tileOf: { calls += 1; return tileOf($0) }); XCTAssertEqual(calls, 0, "a strike is mapped once for a given geometry")
        _ = feed.resolveTiles(lane: 0, key: 8, tileOf: { calls += 1; return tileOf($0) }); XCTAssertEqual(calls, 5, "…and again when the geometry changes")
        let now = 4.2 * 0.5   // beat 4.2: the strike at 4.5 is still in the future
        // each layer keeps its own latest strike per step (the lane strip's chip reads the riff's, its key the notes')
        let (riff, notes) = euclideousStripTileStrikes(resolved.map { var r = $0; r.onsetAt = r.onsetBeat * 0.5; return r }, tiles: 8, now: now)
        XCTAssertEqual(riff[0]?.velocity, 60, "beat 4.0 maps back onto tile 0 and replaces beat 0's strike"); XCTAssertEqual(riff[0]?.seconds ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertNil(riff[1], "the notes-only strike at beat 0.5 is not a riff strike, and the strike at 4.5 has not happened yet"); XCTAssertEqual(riff[2]?.velocity, 60)
        XCTAssertNil(notes[0], "only the notes layer's strikes count for a key"); XCTAssertEqual(notes[1]?.velocity, 80)
    }

    // PER-LAYER EMITTER ROUTING ferry §5.1: the MIX OUT row (and its per-button PULSE glow) is gone — routing moved to
    // the RIFF/NOTES tabs. The old `testTheOutButtonFramesTileTheLanesPairUnderTheOctStepper` is removed with it
    // (`euclideousMixOutButtonFrame`/`outRowFrame` are kept, unused, per §0.2's "hide, don't delete").

    // MARK: 9.3 the pure cost of a frame
    /// All four lanes at 16 steps of 1/16 at 180 BPM with a full 48-strike ring each: per frame the strips map every strike to its tile and work out 16 tiles' envelopes. This times ONLY that pure part on the
    /// build machine (the draw calls and the SwiftUI diff are device-owed); the bound is deliberately loose, the printed figure is what the report quotes.
    func testAFramesPureWorkIsCheap() {
        let sub = 0.25, tempo = 180.0
        var strikes: [EuclideousPulseStrike] = []
        for k in 0..<48 { let beat = Double(k) * sub; strikes.append(EuclideousPulseStrike(onsetBeat: beat, onsetAt: beat * 60 / tempo, riffVel: UInt8(40 + k % 80), notesVel: 0)) }
        let now = 48 * sub * 60 / tempo
        let resolved = strikes.map { s -> EuclideousPulseStrike in var r = s; r.tile = Int16(euclideousPulseTileForOnset(rawAtOnset: s.onsetBeat / sub, n: 16, dir: .fwd)); return r }
        let frames = 600
        let start = Date()
        var sink = 0.0
        for f in 0..<frames {
            let t = now + Double(f) * (1.0 / 60.0)
            for _ in 0..<4 {
                let tiles = euclideousStripTileStrikes(resolved, tiles: 16, now: t)
                for tile in tiles.riff + tiles.notes { if let s = tile {
                    let e = euclideousPulseEnvelopes(velocity: s.velocity, seconds: s.seconds, scale: 1)
                    sink += e.k + e.b + e.f
                } }
            }
        }
        let perFrame = Date().timeIntervalSince(start) / Double(frames)
        print("PULSE pure work per frame (4 lanes x 16 tiles x 48 strikes): \(perFrame * 1000) ms (sink \(sink > 0))")
        XCTAssertLessThan(perFrame, 0.004, "well under a quarter of a 60 Hz frame on any machine")
    }

    /// The same frame with an ACTIVE restart chain. The chain-aware tile mapping builds a small pattern buffer per call (~2 ms a frame for 4 × 48 strikes in a debug build when redone every frame, which is what the first version of this ferry did);
    /// it is now resolved once per strike per geometry (`EuclideousPulseFeed.resolveTiles`), so a frame only scans. This times the first frame (all 192 strikes resolved) and then the steady state.
    func testAFramesPureWorkWithARestartChainIsStillCheap() {
        let sub = 0.25, tempo = 180.0
        var chains = EuclideousLaneRestartChains.off; chains.rhythm = .from([2, 1]); chains.melody = .from([1]); chains.barBeats = 4; chains.lapBeats = 4
        let feed = EuclideousPulseFeed()
        for lane in 0..<4 {
            feed.ingest(lane: lane, events: (0..<48).map { k in var e = Router.EuclideousNoteViewEventSnapshot(onsetBeat: Double(k) * sub, durationBeat: 0.1, kind: 0, notes: [60]); e.hasRiffNote = true; e.vels = [90]; return e },
                        anchorBeat: 0, anchorAt: Date(timeIntervalSinceReferenceDate: 0), tempo: tempo)
        }
        let key = euclideousPulseGeometryKey(n: 16, dir: .fwd, sub: sub, spanBeats: 0, swing: 1, stepBeats: 0.5, chains: chains)
        let tileOf: (Double) -> Int = { euclideousPulseTileForOnset(rawAtOnset: euclideousLaneCometChainRaw(beat: $0, n: 16, dir: .fwd, sub: sub, chains: chains, legacySpanBeats: 0), n: 16, dir: .fwd) }
        let first = Date()
        for lane in 0..<4 { _ = feed.resolveTiles(lane: lane, key: key, tileOf: tileOf) }
        let firstFrame = Date().timeIntervalSince(first)
        let now = 48 * sub * 60 / tempo
        let frames = 600
        let start = Date()
        var sink = 0
        for f in 0..<frames {
            let t = now + Double(f) / 60.0
            for lane in 0..<4 {
                let s = feed.resolveTiles(lane: lane, key: key, tileOf: tileOf)
                sink &+= euclideousStripTileStrikes(s, tiles: 16, now: t).riff.compactMap { $0 }.count
            }
        }
        let perFrame = Date().timeIntervalSince(start) / Double(frames)
        print("PULSE pure work WITH a restart chain: first frame \(firstFrame * 1000) ms, steady state \(perFrame * 1000) ms per frame (sink \(sink))")
        XCTAssertLessThan(perFrame, 0.004); XCTAssertLessThan(firstFrame, 0.05)
    }

    // MARK: marching ants (random mode's dice ring + THROW/TWEAK waiting border share this)
    func testMarchingAntsPhaseIsAContinuousSawtoothOverOneDashCyclePerHalfSecond() {
        let ref = Date(timeIntervalSinceReferenceDate: 0)
        // At t=0 the phase is 0; at the end of a cycle it has travelled one full `period` (negative direction).
        near(euclideousMarchingAntsPhase(ref), 0)
        near(euclideousMarchingAntsPhase(Date(timeIntervalSinceReferenceDate: 0.25)), -3, 1e-9, "halfway through the 0.5 s cycle = half of the default 6pt period")
        // Just before the seam it's nearly a full -6; it wraps back to ~0 at the seam (continuous loop, no jump in the dash).
        XCTAssertEqual(euclideousMarchingAntsPhase(Date(timeIntervalSinceReferenceDate: 0.499)), -5.988, accuracy: 0.001)
        near(euclideousMarchingAntsPhase(Date(timeIntervalSinceReferenceDate: 0.5)), 0, 1e-9, "one full cycle later = back to 0")
    }
    func testMarchingAntsPeriodMatchesTheDashArraysSumSoTheLoopSeamsInvisibly() {
        // The dice's [3,3] dash sums to 6 (the default); the THROW/TWEAK border's [4,3] sums to 7.
        let quarterCycle = Date(timeIntervalSinceReferenceDate: 0.125)   // a quarter of the 0.5 s cycle
        near(euclideousMarchingAntsPhase(quarterCycle, period: 6), -1.5)
        near(euclideousMarchingAntsPhase(quarterCycle, period: 7), -1.75)
    }
}
