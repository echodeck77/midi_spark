//  FourfoldTransportClock.swift
//  FOURFOLD Step 3 (2026-10-23, Docs/standalone-plan.md): the standalone app's INTERNAL TRANSPORT as a pure value — the second source of the one beat the Kernel consumes (seam rule 2: the host's beat is the clock; in the
//  standalone app the app is the host). Foundation-only, no audio, no atomics: the app's audio thread owns one of these and feeds it the render timeline; the UI reaches it through the engine's mailbox as DESIRED state.
//
//  Derived, never accumulated: the beat is a pure function of (anchor beat, anchor sample, tempo, the buffer's sample time). A tempo change re-anchors at the buffer start, so the beat is continuous across it. PLAY always starts at
//  beat 0 (like a hardware sequencer; the engine sees an ordinary transport start edge), STOP freezes the beat where it was.

import Foundation

struct FourfoldTransportClock: Equatable {
    static let tempoRange: ClosedRange<Double> = 30...300

    private(set) var sampleRate: Double
    private(set) var tempo: Double
    private(set) var playing = false
    private var anchorBeat = 0.0
    private var anchorSample = 0.0
    /// After the audio timeline restarts (engine restart / route change the sample time begins again from ~0) the NEXT buffer re-anchors here so the beat carries on instead of jumping.
    private var pendingRestartBeat: Double? = nil

    init(sampleRate: Double, tempo: Double = 120) {
        self.sampleRate = sampleRate
        self.tempo = Self.clamped(tempo)
    }

    static func clamped(_ t: Double) -> Double { t.isFinite ? min(max(t, tempoRange.lowerBound), tempoRange.upperBound) : 120 }

    /// The beat at `sampleTime` (a buffer's start): moving while playing, frozen at the stop position otherwise.
    func beat(at sampleTime: Double) -> Double {
        guard playing, sampleRate > 0 else { return anchorBeat }
        return anchorBeat + (sampleTime - anchorSample) / sampleRate * tempo / 60.0
    }

    /// Samples from `sampleTime` to the next whole beat (the musical-context block's `sampleOffsetToNextBeat`); 0 when stopped.
    func samplesToNextBeat(at sampleTime: Double) -> Int {
        guard playing, tempo > 0 else { return 0 }
        let b = beat(at: sampleTime)
        let frac = b - b.rounded(.down)
        return Int(((1.0 - frac) * sampleRate * 60.0 / tempo).rounded(.down))
    }

    /// Bring the clock to the DESIRED state at the START of the buffer at `sampleTime`. Level-triggered on purpose: a UI command can never be lost, only coalesced (PLAY then STOP inside one buffer is nothing).
    mutating func sync(desiredPlaying: Bool, desiredTempo: Double, at sampleTime: Double) {
        if let b = pendingRestartBeat {                       // the timeline restarted: carry the beat over
            anchorBeat = b; anchorSample = sampleTime; pendingRestartBeat = nil
        }
        let want = Self.clamped(desiredTempo)
        if want != tempo {
            anchorBeat = beat(at: sampleTime); anchorSample = sampleTime   // re-anchor so the beat is continuous across the change
            tempo = want
        }
        if desiredPlaying != playing {
            if desiredPlaying { playing = true; anchorBeat = 0; anchorSample = sampleTime }   // a start edge: from the top
            else { anchorBeat = beat(at: sampleTime); playing = false }                         // a stop edge: freeze
        }
    }

    /// The audio timeline is about to restart (engine restart, possibly at another sample rate): remember where the beat is, and re-anchor on the next buffer.
    mutating func timelineWillRestart(lastSampleTime: Double, newSampleRate: Double) {
        pendingRestartBeat = beat(at: lastSampleTime)
        sampleRate = newSampleRate
    }
}

/// Where an event the AU stamped at `eventSample` (the render timeline) falls on the mach host clock, given the buffer's own (sample, host) stamp — what CoreMIDI wants on a packet so the receiver sees sample-accurate spacing.
/// `numer`/`denom` are `mach_timebase_info`. An event before the buffer, absurdly far past it, or `AUEventSampleTimeImmediate` (0xFFFFFFFF00000000 — a NEGATIVE Int64) is stamped at the buffer start.
func fourfoldHostTime(eventSample: Int64, baseSample: Double, baseHost: UInt64, sampleRate: Double, numer: UInt32, denom: UInt32) -> UInt64 {
    guard sampleRate > 0, numer > 0 else { return baseHost }
    let delta = Double(eventSample) - baseSample
    guard delta > 0, delta < sampleRate * 4 else { return baseHost }
    let nanos = delta / sampleRate * 1_000_000_000
    return baseHost &+ UInt64(nanos * Double(denom) / Double(numer))
}
