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

### Page layout — six equal boxes (2026-10-19 ferry)
- Both orientations in AUM on the 11-inch iPad Pro: six equal boxes (landscape 3 × 2, portrait 2 × 3), 8pt apart, 16pt margins, nothing clipped, the header's gear visible in portrait, MIX | LANES | FX all showing.
- THE 885 CHECK: run a DEBUG build from Xcode in portrait and read the console — `EUCLIDEOUS root view size` (AUVC) and `EUCLIDEOUS page size … box …` (page) should both say ≈814 wide. If the root says 885 the cause is above DiagView (AUM's container), not the ZStack — say so and the fix moves.
- THE 9PT BOTTOM: the boxes should end 16pt above the bottom edge. If you see 25 (as in the old screenshots) the page's height is 9pt short of the view (a bottom safe-area inset?) — the boxes are then ≈4.5pt (landscape) / 3pt (portrait) shorter than the ferry's 319 / 319.67; decide whether the page should extend into that inset.
- MIX in portrait: all eight pads, the OCT steppers and the four OUT rows; pads ≈ 87 × 82 (landscape) and 89 × 82 (portrait), OUT buttons ≈ 42 wide, comfortable to use; the VEL strip reads "VEL".
- Riff cells ≈ 38 × 30 comfortable to tap and paint, with the walk-tag markers still legible (their glyph scales to ≈0.89× at this width).
- LANES cells ≈ 18 wide comfortable to tap and drag-paint; blocks ≈ 55 tall.
- FX in portrait: columns sit exactly under the riff grid's (same width, same offset); the strip's descriptions and the hint row truncate (a few letters) but stay readable; rows ≈ 32 tall.
- Rotate the iPad / resize AUM's plugin window: the page re-lays at once, nothing clipped.
- Any other size you can try (an iPad mini, a windowed AUM panel): note which floors the DEBUG `page size` line lists.

### Legato removed from a lane's gate (2026-10-19)
- The MIX pad's gate axis stops at 99% (far right) and its strip never says LEGATO; every hit re-strikes, including a repeated pitch. A session saved with a lane at 100% loads at 99%.
- Nothing else about the pad changed: puck, ticks, double-tap reset (90%), the VoiceOver "longer gate" step (now stops at 99%).

### CHORDS source — hits on a chord change (2026-10-19 fix)
- With the CHORDS source and a chord that changes on the bar line, a lane with a hit ON the bar line plays the NEW chord's note there (it used to play the old chord's, or — on a
  GATE-100 lane — nothing). Re-check the yellow-lane video setup: step 5 should now sound the new chord's root; step 3 stays silent under GATE 100 (same pitch, held).

### RIFF tab rebuilt / WALK strip (2026-10-19 ferry — §13)
- The WALK strip at real size: 13.4pt slots with their numbers, dashes, EVERY pips, ring and 42% dims, in all four lane colours.
- The readout's longest kind ("LINES UP EVERY 1312 PASSES · 4 NEVER PLAY") shortens as §3.2 says and stays legible, in landscape and portrait.
- The 5.6pt mini-grid cells and their 32% dims on all four lane colours.
- The 45.7 × 40 direction buttons and the 76 × 38 EVERY stepper are comfortable to hit.
- The header row and tab row hold still when switching between RHYTHM and RIFF (the real contentAreaH-derived row-A height is 76pt, not the ferry's own assumed 82 — confirm this doesn't read as a visible height jump against RHYTHM's own zones).
- EVERY 2-4 sounds like the riff holding each note for 2-4 hits (or steps), and a melody restart regroups cleanly.
- REPEAT sounds like the riff's previous note again, and at GATE 100% like one held note.
- The strip's ring keeps pace with the riff, and agrees with the riff-grid marker under ADV HIT.
- A long PING tie (test 6: 56 hits at EVERY 4) holds as one note.
- The TIE lookahead's wider bound (P × EVERY, up to 64 hits, vs the old ≤8/4-laps) doesn't audibly change any of the 20 factory presets beyond what the golden diff already predicts.

### RHYTHM tab rebuilt / restart chains (2026-10-19 ferry — §16)
- The STEPS stepper: the 81 × 36 +/− buttons, and tap versus drag on the value box at 12pt per step.
- The picker's 4.6 × 6 preview bars at real size, in all four lane colours.
- Restart tiles: the 8pt name and unit, and a four-link chain without its unit.
- Restart editor: the 49 × 38 link buttons, the 7pt axis label, the 14.5pt timeline cells and their marks, and every hint line fitting.
- TILT's EARLY and LATE end labels: legible, and the slider still feels the same.
- MIX at padH 76: pad legibility, VEL (not VELOCITY — confirm the word choice reads right, not just that it fits), the 24pt OCT buttons, and the 46 × 20 OUT buttons being comfortable to hit.
- The dashed OUT button on MIX reads as "routed, main out off" (same look `laneOutRow` used to draw as a circle, now a rounded rect).
- The pulse and trace rings on the MIX OUT buttons and the MIX tab: noticeable without being noisy; a ring on an OUT button and the tab's own selected-state underline don't visually clash.
- Restarts sound as the footers and timelines predict, including TIE across a melody restart (DRUNK/RAND don't apply to Euclideous's own riff walk — confirmed hard-mapped to FWD at the model layer).
- The 42% dim of a cut-short pass (a rhythm restart about to cut a lap) reads as "this lap won't get here."
- The restart editor's "current bar/pass" ring on its timeline: confirm it doesn't visibly lag behind the real beat (it updates on the page's existing re-render cadence, not a dedicated timer).

### FX tab (2026-10-18 ferry — six fixed effect rows on the riff's steps)
- 29pt rows and 24pt strip controls are comfortable to tap, paint and drag inside AUM.
- The 8pt axis lock separates painting from value drags reliably, and the step sizes (RATCH 18, GATE 5, VEL 2, NOTE 14, CC 2 pt/step) feel right.
- The 320 ms double-tap window doesn't misfire on quick taps (it runs lift → touch-down), and a double-tap undoes as ONE step.
- FX columns sit under the riff grid's columns in landscape (portrait has no FX tab: its panel sits beside the grid and is 248pt tall).
- RATCH, GATE 100 and TIE sound as described at fast and slow lane rates (incl. RATCH after a GATE-100 hit, a TIE after a ratchet, TIE as the first hit after a start).
- NOTE passes on a FREE 3-hit lane and on a LOCK lane sound as the strip's preview says (C4 › E♭4 › G4 › C5 with a C minor triad), and a melody restart sends them back.
- CCs arrive at their notes' sample, ahead of the note-ons, on the right channel, on a hardware synth and in AUM's MIDI monitor (and FOURFOLD ALL's cable 0).
- The firing flash keeps up at fast rates and reads in all four lane colours (TIE cells never flash; two hits in one poll flash only the later).
- The four strip descriptions and the hint row fit at the smallest supported width; the NOTE preview truncates by design and still reads when cut.
- RATCH ticks (2.5 × 12, 4pt gaps), the GATE/VEL/CC bar, the tie arc and the bubble with its notch read at real size; a rest column and a lane-less row dim to 42%.
- The legato re-strike now closes at the hit's own sample: a lane at 80% with GATE 100 on one hit, then a different pitch, then the same pitch, never overlaps a pitch with itself.
- VoiceOver reads the rails, cells, lane buttons and steppers as §14 says (the tab is read "FX").

### MIX tab (2026-10-18 ferry — gate, velocity and octave for every layer)
- NOTES layer on/off follows the selection: a fresh lane's NOTES strip is grey, its card dot is hollow and its MIX notes pad/stepper are grey;
  select one key (or TOP / TOP 2) and all three come on together; de-select the last one and all three go grey again. With the switch itself
  off but notes remembered, selecting a note switches it back on.
- The MIX pads' turned label reads "VELOCITY" and doesn't touch the velocity number at the reference size; on a short (portrait) pad it
  truncates to "VELO…". Say if you want it lower-case.
- Pad legibility at 96 × 96: the 8pt names, the 11pt values, the puck and lines. (The portrait panel's pads are only ~66 tall — check those too.)
- Touch-to-value feel: the puck sits under the finger, no stray edits from a plain tap, and two pads dragged at once stay independent.
- The 28pt OCT buttons are comfortable, and the end button dims at −2 / +2.
- The grey off state reads as "off, still editable" (turn the riff card / NOTES off and drag its pad; tapping a notes OCT button on an off layer switches it on).
- Per-layer gate and legato against a real synth: riff at 60% while notes sit at 100% (and the reverse) — held vs retriggered, no stuck notes.
- The tab row without its readout or the ring beside LANES: MIX / LANES split it evenly and nothing else sits in it.
- One undo per touch: drag a pad, lift, drag another, undo twice; double-tap a pad and undo once returns it to before the first tap.
- The RHYTHM tab's GATE/VEL follow the riff pad; the NOTES VEL bar follows the notes pad's velocity; dragging a notes pad never moves its riff pad.
- A lane's VEL now survives closing and reopening a session (it used to reset to 100).

### Four riff tabs restored, loop dropped (2026-10-18 ferry — DROPS the looper tabs entry below entirely; its own device checks never happened before the feature was retired)
- The 4 riff tabs (over the shared grid, in the standalone riff panel) read clearly at real size: the
  selected tab's flat fill, each tab's `riffMiniIcon` glyph legible across all 4 lane colours.
- Tap a tab switches which riff is both edited and sounding, audibly, with no gap.
- Long-press a tab opens COPY/PASTE/CLEAR; the card is readable and doesn't block unrelated page gestures.
- HOLD NOTES TO PLAY over the grid still reads as a message, not clutter (unchanged, but re-check with the
  loop row gone from above it).

### Timing — the "odd timing" / gate investigation (2026-10-18)
- **The buffer-size test.** Set a lane to 16 hits on 16 steps at 1/16, record, then repeat at different AUM buffer
  sizes. The engine is proven sample-accurate off-device (`RouterTests.testEuclideousOnsetsAreSampleAccurate…`), and
  every displacement measured so far is a whole number of render blocks, so the limp should shrink in proportion to
  the buffer: 2048 → 4,3,3,3,3 · 1024 → 7,6,7,6,6 · 512 → 13,13,13,13,12 · 256 → inaudible. If it shrinks, it is the
  host's MIDI delivery granularity and nothing in the plugin can fix it. **If it does not change with buffer size,
  the whole diagnosis is wrong and this reopens.**
- Whether the same limp is audible when the plugin drives a synth INSIDE AUM vs routed to another app (different
  MIDI paths, possibly different timestamp handling).

### LANES tab (2026-10-18 ferry — per-lane mute grid, live roll, rhythm + melody restart rows)
_(Replaces the old "Sequencer panel" items — the hold-RESET gesture, the presets popover, "TAP = RESTART" and the step grid are gone.)_
- 20 × 24pt restart cells and 20 × 50pt mute cells are comfortable to tap and drag-paint on the real panel inside AUM (the stroke starts on the
  cell you touch and paints its opposite; dragging down a column across both RESTART rows sets or clears the pair; a plain tap toggles).
- The roll's legibility at 45% on the RESTART tab behind the marks, run outlines and dashed "tap here" slots, in all four lane colours; on MUTE the
  bars (lane colour when audible, grey when muted) read over both sounding and muted cells.
- Playhead speed and position agree with what is heard, for each unit (STEP / 4STP / PASS / 2PASS) and on all four lanes; tap a lane's RATE box
  through the units and confirm the cells keep their pattern while the roll rescales and the playhead speeds up or slows down.
- The 2pt gaps and the playhead's jump over them look right at real size.
- The legend and the hint text fit without truncating at the smallest supported width (the hint is allowed to truncate; the two legend labels are not).
- RHYTHM-only restart: set a mark on cell 8 of the top row — the hits re-phase there while the riff's pitches carry straight on. MELODY-only: every hit
  stays put and the riff goes back to its first rank at the mark. Both on one cell: exactly the old single restart. (Engine-proven; wants an ear.)
- A mark on a MUTED cell still restarts the lane; the next audible hit is a fresh restart there.
- A lane going muted closes its held (100% gate) note at ITS OWN cell boundary, with two lanes on different cell sizes.
- A muted lane's card dims at that beat (cells, comet and hit flashes stop, the riff-grid tag dims to 42%) and the header ring does not flare for it.
- The comet and hit flashes on a lane card follow a RHYTHM restart (they used to ignore restarts); the lane footer's predicted riff steps stay right
  after a MELODY restart (they cannot foresee a restart inside the lap — that is by design).
- A pre-feature session (sequencer ON, a reset) loads with the same sound: its migrated cells/units/marks appear on the tab, and a lane whose lap is
  not a bar sounds slightly different (nearest unit, see the status log). A NEW instance now has no restarts: the riff counts straight through.
- VoiceOver reads "Lane 1 cell 5, sounding", "Lane 2 cell 3 rhythm restart, set", "Lane 3 cell size PASS" (action "Next size"), and the sub-tab chips announce
  selected state.
- Portrait panels: the lane blocks scale to the height the 248pt panel leaves (≈37pt); check the cells are still comfortable.

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
- A hand-placed restart mark (LANES tab, RESTART sub-tab): the tag still threads and departs early instead of falling back to a static tag.
- A FOLLOW lane's step bar now shows the PARTNER's hits (not the lane's own idle pattern) under the colour wash, with one cell
  per partner step (check a partner whose step count differs from the follower's own), the footer bands sit inside the right
  cells, and the lit cells line up with what you hear. The comet's speed on a FOLLOW lane is still the lane's own rate, so
  expect it to look wrong against a partner at a different rate (known, see the status log).

### Header (Fourfold: BRAND / OUTPUTS / NOTES / UTILITIES) — 2026-10-15 ferry
- SWING icon (2026-10-17, UTILITIES' 3rd icon): the popover anchors correctly under the metronome icon in all three
  layouts (A/B/C), at both the smallest and largest panel widths; the tint change at swing≠50 reads clearly at 18pt;
  dragging the slider to 50 reads as "STRAIGHT" not a bare "50"; the wider UTILITIES group didn't visibly crowd NOTES
  or the output rings on a real device at the layouts this ferry only checked by formula.
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

- Sequencer panel (MIX / LANES tabs; LANES = MUTE + RESTART sub-tabs)
- Riff grid + riff capture
- Per-lane mask
- Rhythm sliders / gestures
- Layout (portrait/landscape sizing, real panel width)
- Header (Fourfold: BRAND/OUTPUTS/NOTES/UTILITIES)
- Settings sheet (gear, MIDI IN/MAIN OUT/CLOCK tabs)
- Presets
- Engine/audio (anything that passed its tests but needs an ear, not an eye)
