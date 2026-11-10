//  MutePanelTests.swift — the MUTE TAB EMITTER ROLL ferry (2026-11-09).
//  The per-emitter roll FEED (§3): PLAYED notes from the real send-log (`NoteRollModel`) split per output, UPCOMING
//  timing-only ghosts, the per-row pitch range. Pure Derivations functions; the engine gate + the §2.3 off-clamp are in
//  OutputMuteTests / RouterTests, the layout + draw-order will be in this file's §4–§7 section once the view lands.

import XCTest

final class MutePanelTests: XCTestCase {

    /// A START record for a note that left on `outputs` (a bitmask) from `part` (0…7 = 2·lane + notes).
    private func rec(_ beat: Double, len: Double, pitch: UInt8, part: UInt8, outs: UInt8) -> NoteRollRecord {
        NoteRollRecord(onBeat: beat, length: Float(len), pitch: pitch, velocity: 100, part: part, flags: outs & 0x0F, rank: 0)
    }
    private func model(_ records: [NoteRollRecord]) -> NoteRollModel { var m = NoteRollModel(); m.ingest(records); return m }

    private let u = 0.25   // a 1/16 cell = ¼ beat; a 16-cell window = 4 beats

    // §3.2 — PLAYED notes come from the log, split by OUTPUT, tagged with the sending lane + part; one output's roll never shows another's.
    func testPlayedNotesAreSplitPerOutputAndTagged() {
        let m = model([
            rec(0, len: 1, pitch: 60, part: 0, outs: 0b0001),   // riff, lane 0 → A
            rec(1, len: 1, pitch: 64, part: 1, outs: 0b0001),   // notes, lane 0 → A
            rec(2, len: 1, pitch: 67, part: 2, outs: 0b0010),   // riff, lane 1 → B
        ])
        let a = euclideousEmitterRoll(output: 0, windowStart: 0, windowEnd: 16 * u, playhead: 16 * u, model: m, cells16: 0xFFFF, unitBeats: u)
        XCTAssertEqual(a.count, 2, "output A shows only the two notes that left on A")
        XCTAssertEqual(Set(a.map { Int($0.pitch ?? 0) }), [60, 64])
        XCTAssertTrue(a.allSatisfy { $0.lane == 0 && $0.audible && !$0.ghost }, "both are lane 0, audible (no mute), played")
        XCTAssertEqual(a.first { $0.pitch == 60 }?.riff, true,  "pitch 60 is the riff part")
        XCTAssertEqual(a.first { $0.pitch == 64 }?.riff, false, "pitch 64 is the stack/notes part")
        let b = euclideousEmitterRoll(output: 1, windowStart: 0, windowEnd: 16 * u, playhead: 16 * u, model: m, cells16: 0xFFFF, unitBeats: u)
        XCTAssertEqual(b.map { Int($0.pitch ?? 0) }, [67], "output B shows only its own note, in lane 1")
        XCTAssertEqual(b.first?.lane, 1)
    }

    // review fix #1 — a note that STARTED in the previous window but is still sounding into this one stays drawn (it does not pop off at the window flip).
    func testPlayedNoteStartedBeforeWindowStillShows() {
        let m = model([rec(3.9, len: 0.9, pitch: 60, part: 0, outs: 0b0001)])   // struck beat 3.9, ends 4.8
        let a = euclideousEmitterRoll(output: 0, windowStart: 4, windowEnd: 8, playhead: 4.1, model: m, cells16: 0xFFFF, unitBeats: u)
        XCTAssertEqual(a.count, 1, "a note still ringing from the previous window is kept, not dropped at the flip")
        XCTAssertEqual(a[0].pitch, 60)
        XCTAssertLessThan(a[0].onset, 4, "its onset is before the window — the strip clips the head and shows the in-window tail")
    }

    // review fix #2 — the pitch axis stays ≥ an octave even at the MIDI rails (the window SHIFTS into range, it is not shrunk).
    func testPitchRangeNearRailsStaysAnOctaveWide() {
        let low = euclideousEmitterRollRange([EmitterRollNote(onset: 0, length: 1, pitch: 2, lane: 0, riff: true, audible: true, ghost: false)])
        XCTAssertGreaterThanOrEqual(low.hi - low.lo, 12); XCTAssertEqual(low.lo, 0); XCTAssertEqual(low.hi, 12)
        let high = euclideousEmitterRollRange([EmitterRollNote(onset: 0, length: 1, pitch: 125, lane: 0, riff: true, audible: true, ghost: false)])
        XCTAssertGreaterThanOrEqual(high.hi - high.lo, 12); XCTAssertEqual(high.hi, 127); XCTAssertEqual(high.lo, 115)
    }

    // §3.5 — a note running past the window end is CLIPPED to it (the recording's "bars past cell 16").
    func testPlayedNoteIsClippedToTheWindowEnd() {
        let m = model([rec(3, len: 2, pitch: 60, part: 0, outs: 0b0001)])   // onset beat 3, would end beat 5
        let a = euclideousEmitterRoll(output: 0, windowStart: 0, windowEnd: 4, playhead: 4, model: m, cells16: 0xFFFF, unitBeats: u)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].onset, 3, accuracy: 1e-9)
        XCTAssertEqual(a[0].length, 1, accuracy: 1e-9, "clipped at beat 4, not beat 5")
    }

    // §2.1/§4.6 — a note's `audible` reads the output's mute cell at its OWN onset: a muted-cell note draws as a grey outline, not a bar.
    func testPlayedNoteAudibilityFollowsTheMuteCell() {
        let m = model([
            rec(0.0, len: 0.1, pitch: 60, part: 0, outs: 0b0001),   // cell 0
            rec(0.5, len: 0.1, pitch: 62, part: 0, outs: 0b0001),   // cell 2
        ])
        let a = euclideousEmitterRoll(output: 0, windowStart: 0, windowEnd: 4, playhead: 4, model: m, cells16: 0xFFFB, unitBeats: u)   // cell 2 muted
        XCTAssertEqual(a.first { $0.pitch == 60 }?.audible, true,  "cell 0 sounds")
        XCTAssertEqual(a.first { $0.pitch == 62 }?.audible, false, "cell 2 is muted")
    }

    // §3.2/§3.3 — ghosts are UPCOMING only (onset > playhead), pitch unknown (nil → middle line); played notes are onset ≤ playhead; nothing crosses over.
    func testGhostsAreUpcomingOnlyAndPitchless() {
        let m = model([
            rec(0, len: 0.5, pitch: 60, part: 0, outs: 0b0001),   // played (onset 0 ≤ playhead 2)
            rec(3, len: 0.5, pitch: 72, part: 0, outs: 0b0001),   // onset 3 > playhead 2 → NOT a played note this window
        ])
        let ghosts = [EmitterGhostHit(lane: 0, riff: true, onset: 3, length: 0.5),   // after the playhead → shown
                      EmitterGhostHit(lane: 0, riff: true, onset: 1, length: 0.5)]   // before the playhead → excluded
        let a = euclideousEmitterRoll(output: 0, windowStart: 0, windowEnd: 4, playhead: 2, model: m, cells16: 0xFFFF, unitBeats: u, ghosts: ghosts)
        let played = a.filter { !$0.ghost }, ghostsOut = a.filter { $0.ghost }
        XCTAssertEqual(played.map { Int($0.pitch ?? 0) }, [60], "only the pre-playhead note is played; the beat-3 note is not yet struck")
        XCTAssertEqual(ghostsOut.count, 1, "only the upcoming ghost")
        XCTAssertNil(ghostsOut[0].pitch, "a ghost claims no pitch (drawn on the middle line)")
        XCTAssertEqual(ghostsOut[0].onset, 3, accuracy: 1e-9)
    }

    // §3.6 — the per-row pitch axis: lo…hi of the PLAYED pitches, ≥ an octave, empty = 60 ± 6.
    func testPitchRangeWidensToAnOctaveAndEmptyIsAround60() {
        XCTAssertEqual(euclideousEmitterRollRange([]).lo, 54)
        XCTAssertEqual(euclideousEmitterRollRange([]).hi, 66)
        let notes = [EmitterRollNote(onset: 0, length: 1, pitch: 60, lane: 0, riff: true, audible: true, ghost: false),
                     EmitterRollNote(onset: 1, length: 1, pitch: 64, lane: 0, riff: false, audible: true, ghost: false)]
        let r = euclideousEmitterRollRange(notes)
        XCTAssertGreaterThanOrEqual(r.hi - r.lo, 12, "a 4-semitone spread widens to at least an octave")
        XCTAssertLessThanOrEqual(r.lo, 60); XCTAssertGreaterThanOrEqual(r.hi, 64, "the real notes stay inside the widened range")
        // ghosts carry no pitch, so they don't drive the range
        let g = [EmitterRollNote(onset: 0, length: 1, pitch: nil, lane: 0, riff: true, audible: true, ghost: true)]
        XCTAssertEqual(euclideousEmitterRollRange(g).lo, 54, "a ghost-only row is the empty 60 ± 6")
    }

    // §4 — four rows fill the box; the 16 cells tile the strip exactly; the cell hit-test is the inverse of the draw.
    func testLayoutRowsAndCellsTileTheStrip() {
        let L = euclideousMuteRowsLayout(width: 380, height: 319)
        XCTAssertEqual(L.rowTop(0), 10, accuracy: 1e-9, "first row 10 below the top")
        XCTAssertEqual(L.rowTop(1) - L.rowTop(0), L.rowH + 6, accuracy: 1e-9, "rows are rowH apart + a 6 pt gap")
        XCTAssertGreaterThanOrEqual(L.rowH, 44, "rowH never below the floor")
        XCTAssertEqual(L.cellLeft(0), L.stripX, accuracy: 1e-9, "cell 0 starts at the strip")
        XCTAssertEqual(L.cellLeft(16), L.stripX + L.stripW, accuracy: 1e-6, "16 cells cover the strip exactly")
        for i in 0..<16 { XCTAssertEqual(L.cellIndex(x: L.cellLeft(i) + L.cellW / 2), i, "cell \(i) hit-test is the inverse of the draw") }
        XCTAssertEqual(L.cellIndex(x: L.stripX - 50), 0, "a touch left of the strip clamps to cell 0")
        XCTAssertEqual(L.cellIndex(x: L.stripX + L.stripW + 50), 15, "a touch past the strip clamps to cell 15")
    }

    // §4.6/§3.3 — the pitch axis: the highest pitch sits near the row top, the lowest near the bottom, a ghost (no pitch) on the middle line; x follows the beat window.
    func testNoteYByPitchAndGhostMiddleLine() {
        let L = euclideousMuteRowsLayout(width: 380, height: 319)
        let hiRect = L.noteRect(row: 0, pitch: 72, lo: 60, hi: 72, onset: 0, length: 1, windowStart: 0, window: 4)
        let loRect = L.noteRect(row: 0, pitch: 60, lo: 60, hi: 72, onset: 0, length: 1, windowStart: 0, window: 4)
        let midGhost = L.noteRect(row: 0, pitch: nil, lo: 60, hi: 72, onset: 0, length: 1, windowStart: 0, window: 4)
        XCTAssertLessThan(hiRect.minY, loRect.minY, "the higher pitch is drawn nearer the top")
        XCTAssertEqual(hiRect.minY, L.rowTop(0) + L.notePad, accuracy: 1e-9, "the top pitch sits at the top pad")
        XCTAssertEqual(midGhost.midY, (hiRect.midY + loRect.midY) / 2, accuracy: 0.6, "a ghost is on the row's middle line")
        // x from the beat window
        let late = L.noteRect(row: 0, pitch: 66, lo: 60, hi: 72, onset: 2, length: 1, windowStart: 0, window: 4)
        XCTAssertEqual(late.minX, L.stripX + L.stripW / 2, accuracy: 1e-6, "onset at the half-window sits at the strip's midpoint")
        // a note running past the window end is clamped to the strip's right edge (the clip)
        let over = L.noteRect(row: 0, pitch: 66, lo: 60, hi: 72, onset: 3.5, length: 2, windowStart: 0, window: 4)
        XCTAssertLessThanOrEqual(over.maxX, L.stripX + L.stripW + 1e-6, "a note is never drawn past cell 16")
    }

    // §7 — the row's VoiceOver value: note count + the source lanes of the PLAYED notes (ghosts excluded).
    func testStripSummaryNamesCountAndLanes() {
        let n: (Int, Bool) -> EmitterRollNote = { lane, ghost in EmitterRollNote(onset: 0, length: 1, pitch: ghost ? nil : 60, lane: lane, riff: true, audible: true, ghost: ghost) }
        XCTAssertEqual(euclideousMuteStripSummary(output: 0, notes: []), "Output A roll, 0 notes from no lanes")
        XCTAssertEqual(euclideousMuteStripSummary(output: 1, notes: [n(0, false)]), "Output B roll, 1 note from lane 1")
        XCTAssertEqual(euclideousMuteStripSummary(output: 0, notes: [n(0, false), n(1, false), n(0, false)]), "Output A roll, 3 notes from lane 1 and lane 2")
        XCTAssertEqual(euclideousMuteStripSummary(output: 0, notes: [n(0, false), n(3, true)]), "Output A roll, 1 note from lane 1", "a ghost carries no confirmed lane and is not counted")
    }
}
