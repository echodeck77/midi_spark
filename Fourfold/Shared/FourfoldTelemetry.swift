//  FourfoldTelemetry.swift
//  FOURFOLD Step 2 (2026-10-23): the fast-changing display clock Fourfold's page reads — the part of the 8x8 host's `LiveTelemetry` (AudioUnitViewController.swift) that the Fourfold page uses, and nothing else.
//  A plain class held by the root view via @State: @State tracks the REFERENCE, so the 4 Hz re-anchor and the 30 Hz strike feed mutate it WITHOUT re-running the page body (the CPU lesson that class was made for).

import Foundation

final class FourfoldTelemetry {
    /// HOCKET §8: the count of each lit rule, as the Router last published it (the pop-up's chips, bars and ring and the lane cards' glyphs observe it — never the page body).
    let hocket = HocketLiveModel()
    /// CARD BACKS §5: the notes each part struck (the rolls) and when each output last took one (the jack lights).
    let rolls = NoteRollLive()
    /// RATCH tab §3.10: each output's pattern index at its latest emitter hit (the RATCH tab's strikes' current slot — observed by that tab's leaf views only).
    let emitters = EmitterRatchetLive()
    // The BEAT anchor (4 Hz): the playheads extrapolate the beat from (anchor, anchorAt) at 30 fps, so it only needs re-anchoring periodically.
    var beatAnchor = 0.0
    var beatAnchorAt = Date()
    var beat = 0.0
    var tempo = 120.0
    var beatsPerBar = 4.0         // the host's real bar length (quarter notes), re-read every 4 Hz poll — see `Router.beatsPerBar`
    var wasPlaying = false        // dejitter: transport-edge detector for syncBeat
    var lastTempo = 120.0         // dejitter: tempo-change detector for syncBeat

    /// DEJITTER (Paul 2026-09-11, copied verbatim from `LiveTelemetry.syncBeat`): only HARD re-anchor on a genuine discontinuity (first tick / transport start / tempo change / a jump = loop or seek); otherwise FREE-RUN from the existing
    /// anchor so the 4 Hz sampling jitter never shows as a lurching playhead.
    func syncBeat(_ b: Double, tempo t: Double, playing: Bool, at when: Date) {
        beat = b
        let predicted = beatAnchor + when.timeIntervalSince(beatAnchorAt) * t / 60.0
        if !playing || !wasPlaying || t != lastTempo || abs(b - predicted) > 0.25 {
            beatAnchor = b; beatAnchorAt = when
        }
        tempo = t; wasPlaying = playing; lastTempo = t
    }

    /// PULSE (ferry 2026-10-20, §9.2): the strike feed every strike effect reads.
    let pulse = EuclideousPulseFeed()
}
