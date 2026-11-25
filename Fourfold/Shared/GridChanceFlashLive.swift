//  GridChanceFlashLive.swift
//  GRID CHANCE amendment 2 (2026-11-24) §1/§3: what the % toggle's live cells read. A plain class held by `FourfoldTelemetry` (like the pulse feed / note roll): the 30 Hz drain mutates it WITHOUT re-running the page body;
//  the toggle's own 60 fps `TimelineView` reads it. The drain is the existing fast poll — nothing new is polled, no timer is added. Each event's onset is stamped on the display clock from the dejittered beat anchor (the pulse feed's formula),
//  so a flash lines up with what's heard (§1.3).

import Foundation

final class GridChanceFlashLive {
    private(set) var model = GridChanceFlashModel()
    private var lastBeat = 0.0, wasPlaying = false
    /// The poll: the chance rolls the render thread made since the last one, plus the transport's state — a new start or a jump back clears pending flashes (they belong to a beat about to come round again).
    func poll(events: [GridChanceEvent], anchorBeat: Double, anchorAt: Date, tempo: Double, beat: Double, playing: Bool) {
        if (playing && !wasPlaying) || beat < lastBeat - 0.5 { model.clear() }
        wasPlaying = playing; lastBeat = beat
        if !events.isEmpty { model.ingest(events, anchorBeat: anchorBeat, anchorAt: anchorAt.timeIntervalSinceReferenceDate, tempo: tempo) }
    }
    /// The page was reset (a document load): forget any pending flash.
    func clear() { model.clear() }
}
