# INSTRUCTIONS → Code — THE ROW-BUTTON VALVE: flatten ⇄ restore
# (Paul, 2026-08-12 — un-flatten answered; deployment is a MOVE)

## The mechanic
- **Pressing a row button on an EMPTY play-grid row**: the parts
  grid FLATTENS onto that row AND the workshop CLEARS — staging,
  the left column, the footer chain, all of it. The row button
  enters a **SET state**. The part is christened (PART n; ADD PART
  glows) — deployment and christening are one act.
- **Pressing a SET row button again**: the row UNLOADS and the
  stashed workshop RESTORES whole — staging, column, footer, picks.
  The material moved home. **One place at a time, always; the set
  state says where it lives.**

## The stash model (what makes the B-line survive)
- **Each set button stores the workshop state that made it** — the
  play grid's rows double as per-part workshop snapshots. Flatten
  A (row set, workshop clears) → press it (restore) → re-pick →
  flatten to another row: each row keeps its own stash. The
  earlier "staging persists after apply" refines to: **it persists
  AS THE STASH behind the button**, not on the surface.
- Restoring while another (unassigned) part is mid-build = a PART
  SWITCH: the current workshop retains under its own part (the
  standing per-part retention); the pressed part's stash loads.
  Nothing is ever lost by pressing a button.

## The exception, held open (Paul: "to be defined")
Flattening onto a SINGLE RUNG of a multi-rung part (the right
per-row buttons on ladder bands) — the valve semantics there are
TBD: does a rung-flatten stash/clear the workshop, or is it a
lighter copy? **Do not wire the ladder-rung case beyond the
current behaviour until Paul defines it.** Lane rows + whole-band
deployments follow this file now.

## The lifecycle, updated one-liner
Build (unassigned) → flatten (christened · stashed · workshop
clears · ADD PART glows) → press again anytime = the part comes
home to be rethought. The stage and the bench trade material
through one button, and the button always tells the truth about
who holds it.
— design-side Claude

## §2 — PER-PART RATE (Paul, 2026-08-12: the multi-playhead
## birthstone's v1, ruled buildable)
- **A RATE chip on the parts grid** (workshop-level): {÷4 · ÷2 ·
  ×1 · ×2 · ×4} (musical set; ×3/2 optional later). Flattening
  CARRIES the rate — the deployed row/band runs its own clock:
  `rowStep = floor(beat × rate) % 8`, pure, replay-safe (the
  birthstone's own law: heads are functions of beat).
- **One rate per PART/band** — multi-rung ladders share one clock,
  preserving the column-as-shared-question grammar. The play grid
  may host many rates at once (polymeter arrives).
- **Tells**: a rate badge on the band rail (tappable; changes land
  boundary-deferred — config never stops the engine) + the
  position light goes per-row. Loop keys select column INDICES;
  each row interprets them at its own rate.
- **Per-rung rates: RESTRICTED v1, birthstoned with its analysis**:
  (i) rate-as-content-multiplier = already exists (chain rate
  params, per colour — nothing to build). (ii) TRUE per-rung
  clocks = picking between drifting timelines — Reich's PHASING
  as a performance surface (pick-between-phases: a real future
  instrument) — but it dissolves the ladder's column grammar, so
  it waits as a named birthstone, not a v1 casualty.

## §3 — LENGTH BY LOOP SET (Paul, 2026-08-12: fewer than 8 looped
## columns promote a SHORTER row — polyrhythms)
- **At promotion, the staging LOOP SET defines the deployed row's
  LENGTH**: N looped columns → an N-step row (contents = the
  looped columns' picks, COMPACTED in order — non-contiguous sets
  compact: loop 1·3·5 = a 3-step row of those columns). No loops
  held = the full 8, as today.
- **The clock generalises by one character**: rowStep =
  floor(beat × rate) **% N** — pure, replay-safe; length × rate =
  the full polymeter space (5-step ×1 against 8-step ×1 re-aligns
  every 40; rates compound it further).
- **Rendering**: the row shows N cells + a subtle END-CAP; the
  remainder is absent/dark — length readable at a glance. The
  per-row position light and the row's own loop keys operate
  within N.
- **One length per band** (as one rate per band): whole-band
  promotions carry the loop set to every rung — the ladder keeps
  one clock, one cycle.
- **Editing length = the valve round-trip** (no new UI): press the
  set button (restore — the stash includes the loop set), adjust
  the loops, press again (redeploy). The un-flatten mechanic IS
  the length editor.
- Manual line: "Loop five columns and promote — the row plays
  five against the world's eight."
