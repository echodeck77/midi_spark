# BUILD PAGE — COMPREHENSIVE GIVEN/WHEN/THEN + USABILITY GOTCHAS
# design-side Claude · 2026-08-12 · incorporates the eleven rulings
# ⚠ = a gotcha with its mitigation. This is the wiring contract.

## 1 · SESSION & PARTS
- GIVEN a virgin session, WHEN it opens, THEN it IS Part 1 (zero
  config), the cast empty-but-inviting, staging empty, the perform
  grid STOPPED in edit view.
- WHEN `PART ▾` switches, THEN cast + staging (per-part-retained
  workshops) swap; the perform grid keeps playing.
  ⚠ **Part-switch mid-audition**: staging/machine playback STOPS on
  part switch (else ghost audio of the old part under the new
  workshop). One rule, no exceptions.
- WHEN `+ NEW`, THEN the current part snapshots; a fresh part opens
  with EMPTY staging and **I/O inherited from the previous part as
  editable defaults** (least surprise; changing them is the point,
  pre-filling costs nothing).
- Transport/view states are NEVER in undo (play state doesn't
  undo); all structural edits are (one step per gesture).

## 2 · THE MACHINE (left column + footer chain)
- GIVEN a cast colour selected, WHEN INPUT/chain/OUTPUT edit, THEN
  that COLOUR's machine updates everywhere it sits (colour-owned).
  ⚠ **Live ripple**: edits change the STAGE mid-performance too —
  by design (one machine), but the manual says it once plainly.
- WHEN an R-chip is tapped, THEN it becomes the SELECTED door; the
  source toggle + keyboard + OCT± re-point to it; the keyboard
  shows only when that door is PIANO. Every chip wears its ⌨/⎓
  glyph always.
  ⚠ **Keyboard vanishing** when a MIDI door is selected can read as
  a bug — keep the keyboard's SPACE (collapsed row with "R2 = MIDI
  door" note), never a layout jump.
- WHEN `PLAY THIS MACHINE`, THEN the selected colour auditions
  alone; staging playback stops (one workshop voice, behavioural).
  ⚠ **Silent audition**: a PIANO door with no typed notes (or MIDI
  door, nothing held) = silence. Fallback: audition against the
  REFERENCE CHORD with a small tell ("no input — reference chord").
  Never let the play button appear broken.
- WHEN footer `RANDOMIZE` / `MUTATE`, THEN the selected colour's
  machine re-rolls / nudges (dice §4). Labels carry the selected
  swatch inline (the target visible in the button).
  ⚠ **Provisional selection**: after staging, selecting a rung
  selects a PROVISIONAL colour — footer edits/rolls then target the
  provisional, not the parent. The footer's ID chip MUST show the
  provisional's swatch (dashed ring) so "which machine am I
  editing" is always answered. [Paul's word: keep both mutates or
  one — flag stands.]

## 3 · STAGING (the workshop)
- WHEN `STAGE THE GRID`, THEN the selected colour generates the
  8-variation ladder (simple→complex, provisionals); press again =
  re-stage.
  ⚠ **Re-stage destroys curation**: your picks/mutations vanish
  under a fresh ladder. One undo covers it, AND the button shows a
  subtle "will replace" state when staging is non-empty (a hollow
  ring) — informed, never blocked.
- GIVEN a verb armed (**spring-held is the law**: hold arms, taps
  do, release ends):
  - `PLACE` + tap = fill with the selected colour ·
    `MOVE` + source-then-dest = overwrite-move · `DELETE` + tap =
    clear. All silent (workbench).
  ⚠ **If tap-armed survives the device** instead of spring: armed
  state must be LOUD (filled button + tinted grid border) and
  auto-disarm on leaving the zone — a sticky invisible DELETE is
  the page's worst possible bug.
  ⚠ **PLACE with no colour selected** = no-op + flash the cast
  (the tell teaches the dependency).
- WHEN a row ▸ button, THEN FILL → CLEAR (two-press cycle; the DD
  third state is moot on a silent bench).
- WHEN replay keys toggle, THEN staging playback loops the held
  column set (empty set = full lap) — the shopping trip's scope.
  ⚠ **Empty pick = muted column** (SINGLE law): legal and useful,
  but the column key should DIM when its column has no active rung
  so deliberate rests and accidental deselects both read.
- WHEN staging `MUTATE` / `🎲 RE-ROLL`, THEN the selected rung
  walks / the ladder re-rolls (picks reset on re-roll — the undo
  is the fossil record).
- WHEN `CLEAR ALL`, THEN staging empties (one undo).

## 4 · PERFORM (the stage)
- GIVEN STOPPED (edit view; row buttons in edit dress):
  - WHEN a LEFT merged part button, THEN **COPY ROWS**: staging's
    rows-with-picks land in that band, actives live.
  - WHEN a RIGHT per-row button, THEN **FLATTEN**: the picked line
    lands on that row (ladder rung or lane alike).
  ⚠ **Occupied targets are OVERWRITTEN** (band or row), one undo +
  a flash of what was replaced ("band 2 replaced · 5 cells") —
  silent replacement of performance material is the trust-killer;
  the flash is mandatory.
  ⚠ **Nothing-picked assignment** = no-op + flash the staging
  picks row (teach, don't punish).
  - The workbench verbs (PLACE/MOVE/DELETE) operate here too —
    including row 8 (FREE): stocking the menagerie = PLACE onto
    row 8, stopped.
- WHEN PLAYING (perform dress): side buttons INERT AND DIMMED
  (⚠ live-looking-but-dead buttons breed "it's broken" — the dim
  is the message; tapping one flashes the transport handle: "stop
  to assign").
  - Grid touches follow band law: ladder tap = rung pick
    (boundary-deferred) · lane tap = mute · FREE tap = voice now /
    re-tap = rest.
- WHEN `START/STOP`, THEN transport + view state toggle; the FIRST
  part ever deployed AUTO-STARTS the stage (the spring-to-life).
- WHEN emitter `M`/`S`, THEN perform-output mute/solo ONLY (the
  bench is never gagged by the stage's mixer).
  ⚠ **Forgotten solo** = the classic "where's my sound": a lit S
  is prominent (loud-mute law extends to solo) and the HEALTH
  line can whisper "S on B".

## 5 · CROSS-CUTTING
- ONE WORKSHOP VOICE (machine XOR staging) — behavioural, lamp
  retired; the perform grid is independent.
- DELETE is one verb across all three grids; on a CAST swatch =
  colour + all its cells, no dialog, one undo, the loud flash
  ("−1 colour · 5 cells").
  ⚠ **Cast-tap proximity while DELETE armed**: the flash for a
  colour-delete must look DIFFERENT (bigger, red-tinted) from a
  cell-clear — same verb, two magnitudes, two tells.
- Scenes capture perform state (rung actives, FREE pick, band
  routing) — staging/workshop is never scene state.
- Undo walks everything structural; nothing transport.

## The top-five gotchas, ranked (the pre-wiring checklist)
1. Sticky/invisible armed verbs (esp. DELETE) — spring-held or
   loudly-armed + auto-disarm.
2. Silent PLAY THIS MACHINE — the reference-chord fallback + tell.
3. Overwrite-on-assign without the flash — mandatory flashes,
   sized to magnitude.
4. Provisional-vs-parent editing ambiguity — the footer ID chip
   always answers "which machine".
5. Inert-while-playing side buttons — dim them and teach via the
   transport flash.
— design-side Claude
