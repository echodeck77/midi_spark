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




}
