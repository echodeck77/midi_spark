//  NoteRollLive.swift
//  CARD BACKS (2026-10-28) §5: what the card backs' rolls and jack lights read. A plain class held by `FourfoldTelemetry` (so, like the pulse feed, the 30 Hz drain mutates it WITHOUT re-running the page body): the leaf views that draw
//  the rolls read it from their own 60 fps `TimelineView`. The drain is the existing fast poll — nothing new is polled, no timer is added.

import Foundation

final class NoteRollLive {
    private(set) var model = NoteRollModel()
    private var lastBeat = 0.0, wasPlaying = false
    /// The poll: what the render thread struck since the last one, plus the transport's state — a new start or a jump back clears the roll (its notes belong to a beat that is about to come round again).
    func poll(records: [NoteRollRecord], beat: Double, playing: Bool) {
        if (playing && !wasPlaying) || beat < lastBeat - 0.5 { model.clear() }
        wasPlaying = playing; lastBeat = beat
        if !records.isEmpty { model.ingest(records) }
        // MUTE ZOOM (2026-11-03): the MUTE tab's roll reaches an 8-pass window AND ghosts an equal previous window behind it, so it needs
        // current + previous retained. 256 beats covers both for typical-to-moderately-slow lanes (a very slow lane at 8 passes is a narrow
        // residual edge, flagged); the per-part cap (768 notes) is the real memory bound, so this never grows unbounded. Card backs query
        // their own 2-bar window, so the extra retained history is invisible to them.
        model.prune(before: beat - 256)
    }
    /// The page was reset (a document load): forget what was drawn.
    func clear() { model.clear() }
}
