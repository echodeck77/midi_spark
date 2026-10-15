# Euclideous — open device-verification debt

A running checklist, not a log. `Docs/euclideous-status-log.md` is full of "DEVICE-OWED" flags
(160+ of them as of 2026-10-14) scattered across hundreds of entries with no way to tell which
are still open versus quietly confirmed by a later entry — that's the actual problem this file
exists to fix. Historical backfill into this list is NOT done (deliberately — most of those 160+
are stale, superseded, or already implicitly confirmed by later work touching the same code, and
mining them accurately would mean re-reading the whole archived log). Starting fresh from here.

## The rule going forward

When a ferry/fix ships with something that can only be confirmed on-device, add ONE line below
under the right subsystem — not a paragraph, not a re-explanation, just enough to know what to
go check next time the iPad is in hand. When Paul confirms something on-device, delete the line
(or move it to "confirmed this session" briefly, then delete on the next pass) — this list should
shrink as often as it grows. If it only ever grows, it's not doing its job.

## Open items

### Sequencer panel (LANES/RIFFS tabs, step grid, restart markers)
- Two-finger hold + tap (hold a lane's RESET box, tap that lane's steps with another finger) registers on
  the real panel inside AUM — 2026-10-15 ferry, "per-step restart points."
- The 300ms tap/hold threshold on the RESET box feels right; quick taps reliably open the presets popover
  without ever registering as an edit.
- One-thumb slide-and-lift (press RESET, slide along the row, lift over a step) accuracy near cell gaps.
- Edit-mode legibility: bright restart bars vs dashed "tap here" slots, on both lane20-tinted sounding cells
  and muted cells, across all four lane colours.
- "TAP = RESTART" (replacing "STEP N OF LEN" while a RESET is held) fits without overlapping the RIFFS label
  at the smallest supported panel width.
- OFF and "no mark on step 1" cases audibly run through the LANES lap boundary as expected (engine-proven
  off-device; wants an ear on the real instrument too).

## Subsystem headings to file new items under

- Sequencer panel (LANES/RIFFS tabs, step grid, restart markers)
- Riff grid + riff capture
- Per-lane mask
- Rhythm sliders / gestures
- Layout (portrait/landscape sizing, real panel width)
- Header (RESET SPAN, KEY, CHORDS, MAIN OUT, undo/redo)
- Presets
- Engine/audio (anything that passed its tests but needs an ear, not an eye)
