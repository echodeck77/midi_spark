//  RestartFlashTests.swift
//  The RHYTHM tab's restart tiles flash every time their lane restarts (2026-10-21): the pure restart-event function against the engine's OWN origins (chain marks, pass starts, the riff walk's ordinals),
//  and the flash's look. The page only draws what these return.

import XCTest

final class RestartFlashTests: XCTestCase {
    private struct Rng { var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
        mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 10_000) / 10_000 < p } }

    private func lane(_ rng: inout Rng, riff: Bool = true) -> EuclidLine {
        let n = rng.int(3...16)
        var l = EuclidLine(target: 0, pulses: rng.int(1...n), steps: n, rate: [.r1_16, .r1_8, .r1_4][rng.int(0...2)], useRiff: riff, sourceMode: .midi)
        l.direction = [.fwd, .bkw, .pingpong][rng.int(0...2)]
        l.riffDir = [.forward, .reverse, .pendulum, .pingpong][rng.int(0...3)]
        l.riffLength = rng.int(1...8); l.riffStride = rng.int(1...3); l.riffRotate = rng.int(0...7)
        l.riffAdvanceEvery = rng.int(1...4); l.riffAdvanceStep = rng.bool(); l.riffOn = riff
        return l
    }
    private func cfg(_ l: EuclidLine, span: Int = 0, swing: Double = 50) -> EuclideousWalkLaneConfig {
        euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: span, lanesSeqRate: .oneBar, lanesSeqLen: 8, swingPercent: swing)!
    }

    // MARK: the flash's look
    func testTheFlashDecaysAndEndsAndScalesWithThePulseLevelAndDropsItsMotionUnderReduceMotion() {
        let full = euclideousRestartFlashLook(since: 0, scale: 1, reduceMotion: false)!
        XCTAssertEqual(full.wash, 1); XCTAssertEqual(full.rim, 1); XCTAssertEqual(full.glow, 1); XCTAssertEqual(full.sweep, 0); XCTAssertEqual(full.spinDegrees, 0); XCTAssertEqual(full.hot, 1)
        var last = 2.0
        for t in stride(from: 0.0, through: EuclideousRestartFlash.life, by: 0.01) {
            guard let f = euclideousRestartFlashLook(since: t, scale: 1, reduceMotion: false) else { break }
            XCTAssertLessThanOrEqual(f.glow, last + 1e-12, "the glow only decays"); last = f.glow
            XCTAssertGreaterThanOrEqual(f.spinDegrees, 0); XCTAssertLessThanOrEqual(f.spinDegrees, 360)
        }
        XCTAssertNil(euclideousRestartFlashLook(since: EuclideousRestartFlash.life + 0.01, scale: 1, reduceMotion: false), "over")
        XCTAssertNil(euclideousRestartFlashLook(since: -0.1, scale: 1, reduceMotion: false), "not yet")
        XCTAssertNil(euclideousRestartFlashLook(since: 0, scale: 0, reduceMotion: false), "PULSE OFF draws nothing")
        let sub = euclideousRestartFlashLook(since: 0, scale: 0.6, reduceMotion: false)!
        XCTAssertEqual(sub.wash, 0.6, accuracy: 1e-12); XCTAssertEqual(sub.sweepAlpha, 0.6, accuracy: 1e-12)
        let still = euclideousRestartFlashLook(since: 0.1, scale: 1, reduceMotion: true)!
        XCTAssertNil(still.sweep, "Reduce Motion: no sweep"); XCTAssertEqual(still.spinDegrees, 0, "…no spin"); XCTAssertGreaterThan(still.glow, 0.5, "…the glow stays")
        let mid = euclideousRestartFlashLook(since: 0.2, scale: 1, reduceMotion: false)!
        XCTAssertNotNil(mid.sweep); XCTAssertGreaterThan(mid.spinDegrees, 100)
        let end = euclideousRestartFlashLook(since: EuclideousRestartFlash.spinSeconds, scale: 1, reduceMotion: false)!
        XCTAssertEqual(end.spinDegrees, 360, accuracy: 1e-9, "one full turn"); XCTAssertNil(end.sweep, "the band has crossed by then")
    }

    // MARK: RHYTHM
    func testRhythmWithAChainFlashesAtExactlyTheChainsRestartMarks() {
        var rng = Rng(s: 0xA11CE)
        var checked = 0, flashing = 0
        for _ in 0..<300 {
            var l = lane(&rng)
            let links = (0..<rng.int(1...4)).map { _ in [1, 2, 3, 4, 6, 8][rng.int(0...5)] }.map { UInt8($0) }
            l.restartRhythmBars = links
            let c = cfg(l)
            let chain = c.chains.rhythm
            XCTAssertFalse(chain.isFree)
            let marks = euclideousChainRhythmMarkBeats(chain: chain, barBeats: c.chains.barBeats, windowStart: 0, windowBeats: 400)
            XCTAssertFalse(marks.isEmpty)
            for _ in 0..<40 {
                let beat = Double(rng.int(0...3600)) / 10
                let spb = 0.5
                let got = euclideousRestartSinceSeconds(.rhythm, cfg: c, beat: beat, secondsPerBeat: spb)
                let last = marks.filter { $0 <= beat + 1e-9 }.max()!
                let want = (beat - last) * spb
                checked += 1
                if want <= EuclideousRestartFlash.life + 1e-9 { XCTAssertEqual(got ?? -1, want, accuracy: 1e-9, "beat \(beat) chain \(links)"); flashing += 1 } else { XCTAssertNil(got, "beat \(beat) chain \(links)") }
            }
        }
        XCTAssertGreaterThan(checked, 10_000 - 1); XCTAssertGreaterThan(flashing, 500)
    }
    func testRhythmOnFreeFlashesAtEveryPassStartIncludingWithASpanAndUnderSwing() {
        var rng = Rng(s: 0xBEEF)
        var flashing = 0
        for trial in 0..<300 {
            var l = lane(&rng); l.restartRhythmBars = nil; l.restartMelodyPasses = nil
            let span = trial % 3 == 0 ? rng.int(1...4) : 0
            let swing = trial % 4 == 0 ? 58.0 : 50.0
            let c = cfg(l, span: span, swing: swing)
            XCTAssertTrue(c.chains.rhythm.isFree)
            let cl = euclidCycleLen(c.dir, n: c.n)
            let pass = Double(cl) * c.sub
            for _ in 0..<40 {
                let beat = Double(rng.int(0...2400)) / 10
                let mNow = swing == 50 ? beat : musicalOf(beat, stepBeats: c.swingStepBeats, a: c.swingA)
                // independent closed form: passes start at multiples of the pass length from the pass anchor (beat 0, or the start of the span's column)
                let anchor = c.spanBeats > 0 ? mNow - (mNow - columnStart(mNow, c.spanBeats)) : 0
                let local = mNow - anchor
                let k = (local / c.sub).rounded(.down)
                let eventM = anchor + (k - k.truncatingRemainder(dividingBy: Double(cl)) ) * c.sub
                let eventReal = swing == 50 ? eventM : realOf(eventM, stepBeats: c.swingStepBeats, a: c.swingA)
                let want = (beat - eventReal) * 0.5
                let got = euclideousRestartSinceSeconds(.rhythm, cfg: c, beat: beat, secondsPerBeat: 0.5)
                if want <= EuclideousRestartFlash.life + 1e-9 && want >= -1e-9 { XCTAssertEqual(got ?? -1, max(0, want), accuracy: 1e-6, "trial \(trial) beat \(beat) pass \(pass)"); flashing += 1 }
                else if want > EuclideousRestartFlash.life + 1e-6 { XCTAssertNil(got, "trial \(trial) beat \(beat)") }
            }
        }
        XCTAssertGreaterThan(flashing, 500)
    }

    // MARK: MELODY
    func testMelodyWithAChainFlashesAtExactlyTheChainsRestartPasses() {
        var rng = Rng(s: 0xC0DE)
        var flashing = 0
        for _ in 0..<300 {
            var l = lane(&rng)
            l.restartMelodyPasses = (0..<rng.int(1...4)).map { _ in [1, 2, 3, 4, 6, 8][rng.int(0...5)] }.map { UInt8($0) }
            if rng.bool(0.4) { l.restartRhythmBars = (0..<rng.int(1...3)).map { _ in [1, 2, 4][rng.int(0...2)] }.map { UInt8($0) } }
            let c = cfg(l)
            let marks = euclideousChainMelodyMarkBeats(melodyChain: c.chains.melody, rhythmChain: c.chains.rhythm, barBeats: c.chains.barBeats, lapBeats: c.chains.lapBeats, windowStart: 0, windowBeats: 300)
            XCTAssertFalse(marks.isEmpty)
            for _ in 0..<40 {
                let beat = Double(rng.int(0...2800)) / 10
                let got = euclideousRestartSinceSeconds(.melody, cfg: c, beat: beat, secondsPerBeat: 0.5)
                let last = marks.filter { $0 <= beat + 1e-9 }.max()!
                let want = (beat - last) * 0.5
                if want <= EuclideousRestartFlash.life + 1e-9 { XCTAssertEqual(got ?? -1, want, accuracy: 1e-9, "beat \(beat)"); flashing += 1 } else { XCTAssertNil(got, "beat \(beat)") }
            }
        }
        XCTAssertGreaterThan(flashing, 300)
    }
    /// FREE melody: the riff walk coming back to its first step — against the engine's walk mirror, tick by tick, for every direction, stride, EVERY and ADV STEP / HIT.
    func testMelodyOnFreeFlashesWhenTheWalkIsBackAtItsFirstStepAndRepeatsExactlyFromThere() {
        var rng = Rng(s: 0xF00D)
        var cyclesChecked = 0, lanesChecked = 0
        for trial in 0..<400 {
            var l = lane(&rng); l.restartRhythmBars = nil; l.restartMelodyPasses = nil
            if trial % 5 == 0 { l.restartRhythmBars = [UInt8([2, 3, 4][rng.int(0...2)])] }   // a rhythm chain with a FREE melody: the walk counts on the CUT schedule
            let c = cfg(l)
            let period = euclideousFXWalkPeriod(dir: c.riffDir, length: c.length, stride: c.stride)
            guard period > 1, c.chains.melody.isFree else { continue }
            let cyc = Int64(period) * Int64(max(1, c.every))
            var eventOrdinals: [Int64] = [], seq: [Int] = [], seqs: [[Int]] = []
            var sawHit = false
            for tick in Int64(0)..<Int64(c.n * 2 * Int(cyc) + 400) {
                let w = euclideousWalkTick(c, tick: tick)
                let beat = euclideousWalkRealBeat(c, tick: tick)
                let since = euclideousRestartSinceSeconds(.melody, cfg: c, beat: beat, secondsPerBeat: 0.5)
                let isEvent = since.map { $0 < 1e-9 } ?? false
                if isEvent {
                    XCTAssertEqual(w.advOrd % cyc, 0, "trial \(trial) tick \(tick): an event is a whole number of walk cycles in")
                    XCTAssertTrue(c.advanceStep || w.isHit, "ADV HIT restarts land on a hit")
                    eventOrdinals.append(w.advOrd)
                    if !seq.isEmpty { seqs.append(seq) }
                    seq = []
                }
                if c.advanceStep || w.isHit { if sawHit || isEvent { seq.append(w.playedStep) }; sawHit = true }
            }
            guard eventOrdinals.count >= 3 else { continue }
            lanesChecked += 1
            for i in 1..<eventOrdinals.count { XCTAssertEqual(eventOrdinals[i] - eventOrdinals[i - 1], cyc, "trial \(trial): consecutive restarts are exactly one walk cycle apart") }
            // the walk REALLY restarts: every cycle between two restarts plays the very same steps, starting from the step the walk plays at ordinal 0
            let first = euclideousRiffColumn(ordinal: 0, every: c.every, direction: c.riffDir, length: c.length, stride: c.stride, shift: c.rotate, seed: c.seed)
            for s in seqs where !s.isEmpty { XCTAssertEqual(s.first, first, "trial \(trial): a cycle starts on the walk's first step"); XCTAssertEqual(s, seqs[0], "trial \(trial): every cycle plays the same steps"); cyclesChecked += 1 }
        }
        XCTAssertGreaterThan(lanesChecked, 100); XCTAssertGreaterThan(cyclesChecked, 300)
    }
    func testAMelodyOnFreeWithTheRiffOffOrAWalkOfOneStepHasNoRestart() {
        var rng = Rng(s: 0x51DE)
        var off = lane(&rng, riff: false); off.restartRhythmBars = nil; off.restartMelodyPasses = nil
        for beat in stride(from: 0.0, to: 30, by: 0.25) { XCTAssertNil(euclideousRestartSinceSeconds(.melody, cfg: cfg(off), beat: beat, secondsPerBeat: 0.5), "riff off") }
        var one = lane(&rng); one.riffLength = 1; one.restartRhythmBars = nil; one.restartMelodyPasses = nil
        for beat in stride(from: 0.0, to: 30, by: 0.25) { XCTAssertNil(euclideousRestartSinceSeconds(.melody, cfg: cfg(one), beat: beat, secondsPerBeat: 0.5), "a walk of one step has nothing to come back to") }
    }
    func testTheTransportStartIsARestartOfBoth() {
        var rng = Rng(s: 7)
        var l = lane(&rng); l.restartRhythmBars = [2]; l.restartMelodyPasses = [1]; l.pulses = max(1, l.pulses)
        let c = cfg(l)
        XCTAssertEqual(euclideousRestartSinceSeconds(.rhythm, cfg: c, beat: 0, secondsPerBeat: 0.5) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(euclideousRestartSinceSeconds(.melody, cfg: c, beat: 0, secondsPerBeat: 0.5) ?? -1, 0, accuracy: 1e-9)
        XCTAssertNil(euclideousRestartSinceSeconds(.rhythm, cfg: c, beat: .nan, secondsPerBeat: 0.5))
    }
}
