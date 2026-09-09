# AC — RIFF CAPTURE (SPEC-riff-processor §2/§4 — the headline "play a line in") — build plan

STATUS: BUILT — HELD + MONO v1 (2026-09-09, branch `feature/riff-capture`; iOS builds, macOS green incl. fuzz; the live
recorder + arm gesture are DEVICE-EAR/EYE owed). Paul confirmed HELD+MONO scope. FOLLOWING (§4) + POLY + the §3 generator
are the flagged fast-follows.

Landed: pure conversion (`riffCaptureRank`/`riffCaptureStencil` + 2 DerivationsTests) · Kernel recorder (`armRiffCapture`/
`disarmRiffCapture`/`riffCaptureDrain` — arm snapshots the door's held/latched chord as the FRAME, `handleIncoming`
DIVERTS the capture door's live line into a ring, never touching the pool) · AU `commitRiffCapture` (drain →
`riffCaptureStencil` → write `riffRanks`/`riffOct` onto the colour's RIFF slot, MONO) · UI CAPTURE row on the RIFF editor
(◉ PLAY A LINE IN / ● RECORDING — TAP TO KEEP / CANCEL) · a RouterTest proving capture→playback→FOLLOW-a-new-chord.

## The flow (spec §2, ratified)
LATCH the chord (the FRAME) → arm CAPTURE → play the line on the SAME door → disarm → the line is now the stencil (ranks),
and it follows every chord after. One door; the latch is the "second hand".

## What's built (pure, tested)
- `riffCaptureRank(pitch, frame)` — inverse of `riffResolve`: nearest (rank, oct) so a played frame note round-trips and a
  passing tone snaps to the nearest chord position.
- `riffCaptureStencil(events, frame, steps, rateBeats, startBeat)` — quantize a captured (beat, pitch) line onto the step
  grid → MONO `riffRanks` + `riffOct`; unplayed steps REST; a take past one loop truncated.

## The device-owed remainder (to build on confirm)
1. **Model** — a capture-armed flag + the FRAME snapshot. `PluginState`/box: which RIFF cell is arming (ephemeral, like
   the audition target — never persisted). The captured result writes the existing `riffRanks`/`riffOct` (no new stored
   shape needed for MONO/HELD).
2. **Kernel recorder** (parallels reel/replay capture): while a RIFF cell's capture is armed, its door's live note-ONs
   DIVERT into a recorder ring (beat + pitch) and DON'T feed the grid; the FRAME = the door's latched/held pool snapshot
   at arm. On disarm (main thread), call `riffCaptureStencil` → write `riffRanks`/`riffOct` back to the document (the
   reel's promote-to-document pattern). Record on the render thread, convert + write on disarm on the main thread.
3. **UI** — a CAPTURE arm/disarm button on the RIFF editor + a "recording…" indicator + the "LATCH a chord first" hint
   when no frame is held. Arm snapshots the current held/latched chord as the frame.

## v1 SCOPE (recommended — confirm)
- **HELD frame + MONO line.** One frame snapshot at arm; a single-note line → `riffRanks`/`riffOct`. This is the §2
  headline and the bulk of the value.
- **DEFERRED to a fast-follow:** §4 FOLLOWING frame (each note measured against the chord at its moment — the Piano-Motifs
  case; needs a pool-TIMELINE recording, not one snapshot) · POLY capture (chords → `riffMask`) · §3 the RIFF generator
  (🎲 + SHAPE) + straight-capture (photo→stencil).

## DEVICE-OWED caveats (flag to Paul)
- **Capture needs a RUNNING CLOCK** (host transport playing, or free-run active) — the take is quantized to the RATE grid
  by BEAT, so stopped-with-no-clock would land every note on step 0. The natural flow is: transport running → latch chord
  → arm → play the line in time → keep.
- **The FRAME is snapshotted at ARM** from the door's latched pool (else the live pool). So LATCH the chord first, then
  you're free to release it and play the line — the frame won't shift. If you physically HOLD the chord on the SAME OMNI
  door while playing the line, those held notes also divert into the recording (pollution) — hence "latch, don't hold".
- The recorder + arm gesture aren't unit-testable (live MIDI in), like reel/replay — the pure conversion + playback are
  locked by tests; the feel is yours to verify.

## Tests
- Pure: done (round-trip, quantize). RouterTest: a RIFF cell whose `riffRanks` were set by `riffCaptureStencil` from a
  played line plays that line back and FOLLOWS a different chord (proves capture→playback→derive, off-device).
- The recorder + arm gesture are DEVICE-owed (live-input recording isn't unit-tested, like reel/replay).
