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
        l.riffAdvanceEvery = rng.int(1...8); l.riffAdvanceStep = rng.bool(); l.riffOn = riff
        return l
    }
    private func cfg(_ l: EuclidLine, span: Int = 0, swing: Double = 50) -> EuclideousWalkLaneConfig {
        euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: span, lanesSeqRate: .oneBar, lanesSeqLen: 8, swingPercent: swing)!
    }





    private func chain(_ links: [Int]) -> EuclideousRestartChain {
        var c = EuclideousRestartChain(); for (i, l) in links.enumerated() { c.packed |= UInt32(l) << UInt32(8 * i) }; return c
    }

    // MARK: RHYTHM — the LANES panel's rhythm restart marks, against a brute-force restatement
    func testRhythmRestartMarksAreExactlyTheChainsRunningTotalsRepeatedEveryCycle() {
        var rng = Rng(s: 0xA11CE)
        for _ in 0..<300 {
            let links = (0..<rng.int(1...4)).map { _ in [1, 2, 3, 4, 6, 8][rng.int(0...5)] }
            let c = chain(links), barBeats = [3.0, 4.0, 6.0][rng.int(0...2)]
            let total = links.reduce(0, +)
            let start = Double(rng.int(0...300)) / 4, len = Double(rng.int(40...400)) / 2
            var want: [Double] = []
            for m in 0..<400 {
                var run = 0
                for l in links {
                    let beat = Double(m * total + run) * barBeats
                    if beat >= start - 1e-9 && beat < start + len - 1e-9 { want.append(beat) }
                    run += l
                }
            }
            let got = euclideousChainRhythmMarkBeats(chain: c, barBeats: barBeats, windowStart: start, windowBeats: len)
            XCTAssertEqual(got.count, want.count, "links \(links) bar \(barBeats) window \(start)+\(len)")
            for (g, w) in zip(got, want.sorted()) { XCTAssertEqual(g, w, accuracy: 1e-9) }
        }
        XCTAssertTrue(euclideousChainRhythmMarkBeats(chain: .free, barBeats: 4, windowStart: 0, windowBeats: 100).isEmpty, "FREE has no marks")
    }

    // MARK: MELODY — the restarting passes' start beats
    func testMelodyRestartMarksAreThePassStartsTheChainRestartsOn() {
        // rhythm FREE ⇒ pass q starts at q × lap. Melody [1]: every pass restarts. Melody [2,1]: passes 0, 2 of every 3.
        let lap = 2.0
        let every = euclideousChainMelodyMarkBeats(melodyChain: chain([1]), rhythmChain: .free, barBeats: 4, lapBeats: lap, windowStart: 0, windowBeats: 20)
        XCTAssertEqual(every, stride(from: 0.0, to: 20.0, by: lap).map { $0 })
        let two = euclideousChainMelodyMarkBeats(melodyChain: chain([2, 1]), rhythmChain: .free, barBeats: 4, lapBeats: lap, windowStart: 0, windowBeats: 20)
        XCTAssertEqual(two, [0, 4, 6, 10, 12, 16, 18])
        XCTAssertTrue(euclideousChainMelodyMarkBeats(melodyChain: .free, rhythmChain: .free, barBeats: 4, lapBeats: lap, windowStart: 0, windowBeats: 20).isEmpty, "FREE has no marks")
        // a window that starts mid-way sees only the marks inside it
        let late = euclideousChainMelodyMarkBeats(melodyChain: chain([2, 1]), rhythmChain: .free, barBeats: 4, lapBeats: lap, windowStart: 7, windowBeats: 8)
        XCTAssertEqual(late, [10, 12])
    }
}
