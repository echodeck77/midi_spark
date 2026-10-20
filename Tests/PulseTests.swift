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

    // MARK: 4. the level mark
    func testLevelMarkBandRiseAndAlpha() {
        // the spec's tile: 44 tall, a 12-tall footer 3 above the tile's bottom -> footer top 29: the band runs from y 29 up to y 2 (27 tall)
        let band = euclideousPulseMarkBand(tileHeight: 44, footerTopY: 29)
        XCTAssertEqual(band.bottomY, 29); XCTAssertEqual(band.topY, 2); XCTAssertEqual(band.height, 27)
        XCTAssertEqual(euclideousPulseMarkRise(velocity: 127, band: band.height, seconds: 0.06), 27, accuracy: 1e-9)
        XCTAssertEqual(euclideousPulseMarkRise(velocity: 64, band: band.height, seconds: 0.06), 13.6, accuracy: 0.05)
        XCTAssertEqual(euclideousPulseMarkRise(velocity: 64, band: band.height, seconds: 0.03), 6.8, accuracy: 0.03, "half that at 30 ms")
        XCTAssertEqual(euclideousPulseMarkRise(velocity: 127, band: band.height, seconds: 5), 27, accuracy: 1e-9, "it stays at the velocity")
        XCTAssertEqual(euclideousPulseMarkRise(velocity: 127, band: band.height, seconds: 0, instant: true), 27, accuracy: 1e-9, "Reduce Motion: at once")
        // the real tile (source): a 14pt footer flush with the bottom of a 44 tall tile -> band y 30 … 2, 28 tall
        let real = euclideousPulseMarkBand(tileHeight: 44, footerTopY: 44 - 14)
        XCTAssertEqual(real.bottomY, 30); XCTAssertEqual(real.height, 28)
        // m at half a lap is 0.95 × e^(−1); m scales with the lap, so a longer lap holds it longer
        near(euclideousPulseMarkAlpha(seconds: 1, lapSeconds: 2, scale: 1), 0.95 * exp(-1.0))
        XCTAssertGreaterThan(euclideousPulseMarkAlpha(seconds: 1, lapSeconds: 8, scale: 1), euclideousPulseMarkAlpha(seconds: 1, lapSeconds: 2, scale: 1))
        near(euclideousPulseMarkAlpha(seconds: 0, lapSeconds: 4, scale: 0.6), 0.95 * 0.6); XCTAssertEqual(euclideousPulseMarkAlpha(seconds: 0, lapSeconds: 4, scale: 0), 0)
        near(euclideousPulseLapSeconds(cycleLen: 8, stepBeats: 0.5, tempo: 120), 2.0); near(euclideousPulseLapSeconds(cycleLen: 16, stepBeats: 0.25, tempo: 180), 16 * 0.25 * 60 / 180)
    }

    // MARK: 5. the tail
    func testTailLengthGrowsWithVelocityAndIsCutAtTheLeadingEdge() {
        XCTAssertEqual(euclideousPulseTailLength(vis: 0), 10); XCTAssertEqual(euclideousPulseTailLength(vis: 1), 70)
        let free = euclideousPulseTail(vis: 1, dotX: 200, areaMinX: 0, areaMaxX: 300, movingRight: true)
        XCTAssertEqual(free.length, 70); XCTAssertEqual(free.backX, 130)
        let cut = euclideousPulseTail(vis: 1, dotX: 30, areaMinX: 0, areaMaxX: 300, movingRight: true)
        XCTAssertEqual(cut.length, 30, "cut off at the step area's leading edge when the dot is 30 from it"); XCTAssertEqual(cut.backX, 0)
        let back = euclideousPulseTail(vis: 0, dotX: 100, areaMinX: 0, areaMaxX: 300, movingRight: false)
        XCTAssertEqual(back.length, 10); XCTAssertEqual(back.backX, 110, "a BKW comet trails to its right")
        XCTAssertEqual(euclideousPulseTail(vis: 1, dotX: 295, areaMinX: 0, areaMaxX: 300, movingRight: false).length, 5)
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
    }

    // MARK: 7. the ring
    func testRingStrokeAndLetter() {
        XCTAssertEqual(euclideousPulseRingStroke(f: 1), 5); XCTAssertEqual(euclideousPulseRingStroke(f: 0), 2.5); XCTAssertEqual(euclideousPulseRingStroke(f: 0.5), 3.75); XCTAssertEqual(euclideousPulseRingStroke(f: 9), 5)
        XCTAssertTrue(euclideousPulseRingLetterIsWhite(f: 0.36)); XCTAssertFalse(euclideousPulseRingLetterIsWhite(f: 0.35)); XCTAssertFalse(euclideousPulseRingLetterIsWhite(f: 0))
        XCTAssertTrue(euclideousPulseNameLit(f: 0.13)); XCTAssertFalse(euclideousPulseNameLit(f: 0.12))
        XCTAssertEqual(euclideousPulseRingVelocity(riffVel: 40, notesVel: 90), 90)
    }

    // MARK: 8. Reduce Motion / OFF
    func testTheReduceMotionAndOffFilter() {
        for e in EuclideousPulseEffect.allCases { XCTAssertEqual(euclideousPulseFilter(e, scale: 0, reduceMotion: false), .off, "OFF: \(e)"); XCTAssertEqual(euclideousPulseFilter(e, scale: 0, reduceMotion: true), .off) }
        for e in EuclideousPulseEffect.allCases { XCTAssertEqual(euclideousPulseFilter(e, scale: 1, reduceMotion: false), .full, "FULL: \(e)") }
        for e in [EuclideousPulseEffect.keyDipMove, .dotSwell, .tail, .ripple, .puckSwell, .arrowScale] { XCTAssertEqual(euclideousPulseFilter(e, scale: 1, reduceMotion: true), .off, "Reduce Motion: no \(e)") }
        for e in [EuclideousPulseEffect.keyDipOverlay, .glow, .wash, .overlay, .noteName, .letter] { XCTAssertEqual(euclideousPulseFilter(e, scale: 0.6, reduceMotion: true), .full, "Reduce Motion keeps \(e)") }
        XCTAssertEqual(euclideousPulseFilter(.flareCore, scale: 1, reduceMotion: true), .fixedCore, "the core stays, at a fixed 10 pt")
        XCTAssertEqual(euclideousPulseFilter(.levelMark, scale: 1, reduceMotion: true), .instantRise, "the mark stays, drawn at its height at once")
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
        XCTAssertEqual(f.latestRiff(lane: 1)?.onsetBeat, 4); XCTAssertEqual(f.latestNotes(lane: 1)?.onsetBeat, 3); XCTAssertNil(f.latest(lane: 0))
        // a beat that goes back (a restart or a loop) drops the old strikes
        ingest(f, 1, [ev(0.5, notes: [60], vels: [90], riff: true)]); XCTAssertEqual(f.strikes(lane: 1).count, 1)
        // a stop stamps the moment and settles for 1.5 s; the marks fade over the same window; a start clears the last run
        f.noteTransport(playing: false, at: t0); XCTAssertTrue(f.isSettling(now: t0.addingTimeInterval(1.4))); XCTAssertFalse(f.isSettling(now: t0.addingTimeInterval(1.6)))
        XCTAssertEqual(f.markFade(now: t0.addingTimeInterval(0.75)), 0.5, accuracy: 1e-9); XCTAssertEqual(f.markFade(now: t0.addingTimeInterval(3)), 0)
        f.noteTransport(playing: false, at: t0.addingTimeInterval(1)); XCTAssertEqual(f.stoppedAt, t0, "a second 'stopped' reading is not a new edge")
        f.noteTransport(playing: true, at: t0.addingTimeInterval(5)); XCTAssertTrue(f.strikes(lane: 1).isEmpty, "a start drops the strikes of the last run…"); XCTAssertNil(f.stoppedAt); XCTAssertEqual(f.markFade(now: t0), 1)
        f.noteTransport(playing: false, at: t0.addingTimeInterval(5.1))
        f.ingest(lane: 0, events: [ev(1, notes: [60], vels: [90], riff: true)], anchorBeat: 0, anchorAt: t0.addingTimeInterval(5.05), tempo: 120)   // a strike that arrived just before the start edge was read
        f.noteTransport(playing: true, at: t0.addingTimeInterval(5.2)); XCTAssertEqual(f.strikes(lane: 0).count, 1, "…but not one that belongs to the new run (within 0.5 s of the start)")
        f.noteTransport(playing: true, at: t0.addingTimeInterval(6)); ingest(f, 1, [ev(1, notes: [60], vels: [90], riff: true)]); f.noteTransport(playing: true, at: t0.addingTimeInterval(7)); XCTAssertEqual(f.strikes(lane: 1).count, 1, "playing again is not an edge")
        // the ring is bounded
        ingest(f, 2, (0..<200).map { ev(Double($0), notes: [60], vels: [90], riff: true) }); XCTAssertEqual(f.strikes(lane: 2).count, EuclideousPulseFeed.ringCap)
        // an event without velocities (should not happen) still pulses, at a middling 100
        ingest(f, 3, [ev(1, notes: [60], vels: [], riff: true)]); XCTAssertEqual(f.strikes(lane: 3).first?.riffVel, 100)
    }
    func testTheCometBarFollowsTheRiffWhenItIsOnAndTheNotesWhenItIsOff() {
        XCTAssertEqual(euclideousPulseStrikeVelocity(riffOn: true, riffVel: 90, notesVel: 50), 90)
        XCTAssertEqual(euclideousPulseStrikeVelocity(riffOn: true, riffVel: 0, notesVel: 50), 0, "riff on: a notes-only strike (the notes on a rest) passes through")
        XCTAssertEqual(euclideousPulseStrikeVelocity(riffOn: false, riffVel: 0, notesVel: 50), 50, "riff off: the notes layer is the lane's only voice (for now)")
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
        let now = 4.2 * 0.5   // beat 4.2: the strike at 4.5 is still in the future
        let on = euclideousPulseTileStrikes(strikes, riffOn: true, tiles: 8, now: now, tileOf: tileOf)
        XCTAssertEqual(on[0]?.velocity, 60, "beat 4.0 maps back onto tile 0 and replaces beat 0's strike"); XCTAssertEqual(on[0]?.seconds ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertNil(on[1], "riff on: the notes-only strike at beat 0.5 passes through, and the strike at 4.5 has not happened yet"); XCTAssertEqual(on[2]?.velocity, 60)
        let off = euclideousPulseTileStrikes(strikes, riffOn: false, tiles: 8, now: now, tileOf: tileOf)
        XCTAssertNil(off[0], "riff off: only the notes layer's strike counts"); XCTAssertEqual(off[1]?.velocity, 80)
        XCTAssertEqual(euclideousPulseLatestStrike(strikes, riffOn: true, now: now)?.velocity, 60, "the latest strike that has happened by beat 4.2 is the one at 4.0")
        XCTAssertEqual(euclideousPulseLatestStrike(strikes, riffOn: true, now: 4.6 * 0.5)?.velocity, 110)
        XCTAssertNil(euclideousPulseLatestStrike([], riffOn: true, now: 1))
    }
}
