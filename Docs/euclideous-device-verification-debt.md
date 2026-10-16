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

### Looper tabs replace the riff tabs (2026-10-16 ferry, §11 — supersedes "loop slots," pruned below, same day before any device pass)
- Recorded timing feels faithful against the live clock's jitter.
- Four buttons sit over their grid columns, landscape and portrait, down to the 24pt cell floor.
- The 16-segment strip is legible at its smallest width.
- Overdub in AUM at several buffer sizes.
- A replaying loop through a host stop and start feels right in performance.
- HOLD NOTES TO PLAY over the grid reads as a message, not clutter.

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

### LISTEN remembers its partner (2026-10-16)
- On each LISTEN row (RHYTHM / PITCH / LEVEL): pick a partner, tap the lit mode off, tap a mode on again — the same partner is
  back with no re-choosing; swapping FOLLOW → WITH → GAPS (and SHADOW ↔ AVOID, DUCK ↔ ACCENT) keeps it too.
- PITCH: choose AVOID + ANY, switch to SHADOW (it shadows the lane you had picked before ANY), switch back (ANY returns).
- A remembered partner that has since become illegal (it now follows something, or lighting it would close a loop) falls back to
  the next valid lane instead of lighting something broken.

### FOLLOW lanes look and feel like their partner (2026-10-16)
- The follower's lit cells are the PARTNER's colour at 75% — faded enough to read as "borrowed", not so faded they look off;
  the comet head is still the follower's own colour; a strike's flash still reads against the faded fill.
- The comet's speed matches what you hear for a follower at ×1/×2/÷2 and against a partner at a different rate; the 4-vs-3
  step grouping follows the partner's feel.
- Dragging a follower's bar moves the PARTNER (hits up/down, offset left/right, pinch for steps), the readout says
  "LANE n · FOLLOWED", and both lanes' bars update together. A two-finger ALL-lanes OFFSET drag moves every lane once.
- The follower's OFFSET *slider* still shifts only the follower (a shifted copy of the partner) — confirm that split feels right.

### Walk tags — GAPS/WITH threads and the footer fix (2026-10-15 follow-ups)
- A GAPS lane (and a WITH lane) now shows a thread to its next SOUNDING hit and the tag departs early, like any other lane;
  it should never fly to a step that then doesn't sound. Check with a partner whose hits overlap the lane's.
- The lane footer under LOCK + ADV STEP on a ROTATED pattern (first hit not on step 1) names the same riff steps the lane
  actually plays.
- A hand-placed restart mask (LANES tab, hold a RESET box and tap steps): the tag still threads and departs early instead of
  falling back to a static tag.
- A FOLLOW lane's step bar now shows the PARTNER's hits (not the lane's own idle pattern) under the colour wash, with one cell
  per partner step (check a partner whose step count differs from the follower's own), the footer bands sit inside the right
  cells, and the lit cells line up with what you hear. The comet's speed on a FOLLOW lane is still the lane's own rate, so
  expect it to look wrong against a partner at a different rate (known, see the status log).

### Header (Fourfold: BRAND / OUTPUTS / NOTES / UTILITIES) — 2026-10-15 ferry
- Header fit in AUM, full-screen and windowed, both orientations: A, B and C switch cleanly with nothing clipped;
  C (floor: page width 373) fits a 375pt-wide windowed panel.
- The header rows are now 44 tall with a 9pt top margin (keeps the spec's 31pt centre line): the lane cards below
  haven't been squeezed, and 44pt targets don't collide in the two-row layouts.
- 300ms tap vs hold on the output rings: a hold never toggles; a cancelled touch (system gesture, app backgrounded)
  never leaves three lanes dimmed.
- Lit vs unlit quarters at 36pt for all four lane colours; the dashed OFF state reads as off.
- Pulse and trace rings noticeable without being noisy; the RHYTHM-tab ring reads as "your OUT toggles are in here";
  the OUT-circle ring (≈6pt outside) overlapping its neighbours at the 3pt circle gap looks acceptable.
- Sounding flares stay in step with the comet bars (they use real strike events, so under swing they can differ by up
  to a quarter step), lit-notes-only lanes flare too, at no noticeable CPU cost.
- The FOURFOLD mark and wordmark at real size.
- Key pop-up anchored under the pill and chord grid anchored under the CHORDS segment: position and clamping in both
  orientations; the chord card fits below the header at 375pt.
- C's 36pt icon targets are still comfortable.
- Holding an OFF ring: the light disc with dashed quarters and an ink letter reads clearly (macOS render looked right;
  confirm at 36pt on the iPad).
- The OUT-circle pulse ring is no longer painted over by its neighbour, and expanding over the 3pt gaps still looks tidy;
  tapping two rings with two fingers toggles both.
- Ring flare vs the comet bar: the ring follows REAL strike events (not the comet bar's pattern+clock), so under SWING
  they can differ by up to a quarter step, and AUTO-rate lanes use the comet bar's `rate ?? 1/16` step. Compare them with
  swing at 75% and with a lane left on AUTO rate at a non-1/16 machine rate; if they visibly disagree, calibrate or share
  one feed.
- VoiceOver on a ring (iOS 17+ speaks "toggle"; iOS 16 speaks "button"): "Main out A, on, fed by lanes 1 and 4" is read
  once, with no trailing duplicate "on".
- A FRESH instance now plays immediately (no ON chip; free-run is always on; default lanes 1–2 use the KEY source,
  which needs no input) — is that acceptable, or should defaults ship with lanes stopped?

### Settings sheet (gear, MIDI IN / MAIN OUT / CLOCK tabs) — 2026-10-15 ferry, "Fourfold settings"
- Sheet fit and position in AUM, full-screen and windowed, both orientations, including a window short
  enough that only the tab content scrolls.
- 32pt channel buttons (MIDI IN) and stepper chevrons (MAIN OUT) are comfortable to hit.
- The 42% dim on the page below the sheet reads as "still playing behind," not "off."
- The 32pt mini output rings (0.8 scale of the header ring) read as the same objects as the header's own.
- A real MIDI controller on one channel, filtered by LISTEN ON; a multitimbral synth fed per-output channels.
- ALL NOTES OFF against a genuinely stuck synth note.
- KEEP PLAYING vs STOP against AUM's own transport, including the disclosed edge case where an 8×8-
  workbench free-run reason (ddSolo/staging/play) is active at the same moment STOP is selected.
- The footer's WORKBENCH link.

## Subsystem headings to file new items under

- Sequencer panel (LANES/RIFFS tabs, step grid, restart markers)
- Riff grid + riff capture
- Per-lane mask
- Rhythm sliders / gestures
- Layout (portrait/landscape sizing, real panel width)
- Header (Fourfold: BRAND/OUTPUTS/NOTES/UTILITIES)
- Settings sheet (gear, MIDI IN/MAIN OUT/CLOCK tabs)
- Presets
- Engine/audio (anything that passed its tests but needs an ear, not an eye)
