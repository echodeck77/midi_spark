# OPEN → Code — THE PLAY GRID AS LANES (the redesign
# conversation, Paul + design, 2026-08-27)
# ⚠ STATUS: NOTHING RATIFIED. A design-in-progress record; no
# build orders. This conversation ABSORBS OPEN-multi-row.md's
# territory (the two ideas unified — noted in §4).

## §1 — THE SHAPE (as it stands tonight)
The play grid becomes **EIGHT TYPED LANES**, mute-performed:
- **RECORDED lanes** — passes exported from THE REEL (one or
  several; each lane = a pass or a slice of one).
- **FLATTENED lanes** — parts promoted from THE PART GRID (the
  existing PROMOTE path = this route already).
**THE PROVENANCE LAW (Paul's)**: type = source. Recorded comes
ONLY from the recorder; flattened comes ONLY from the part grid.
No third path, no ambiguity. Typed PER LANE (no fixed 4+4 —
sessions choose their mix).

## §2 — ★ REVERT-TO-MACHINES (Paul's, the profound half)
**Any recorded cell can revert into the machines that made it** —
even one cell of a multi-pass export.
- Mechanism (rides planned/existing infra): the reel's per-pass
  STATE SNAPSHOTS (the REVISIT machinery) + the roll's per-note
  COLOUR attribution → "which machines made this cell" is
  answerable. Revert = filter the pass's snapshot by the cell's
  contributing colours and RE-MATERIALIZE those chains **in the
  PART GRID** (the workshop — never disturbing the stage), for
  editing and re-export.
- Consequence: **a recording here is never a dead photo — it
  carries its recipe.** The freeze objection softens twice over:
  FOLLOWING converts the photo; REVERT reopens the camera. Both
  may coexist (import chip VERBATIM|FOLLOWING still on the
  table; revert applies regardless).
- Naming flag: "REVERT" collides with scene-REVERT — UNPACK /
  TO MACHINES / candidates for the no-metaphors pass.

## §3 — THE TWO-GRID STORY (the frame this completes)
**PART GRID = THE WORKSHOP** (machines, chains, banking, the
ladder — multi-rung lives HERE, where Paul enjoys it).
**PLAY GRID = THE STAGE** (lanes, mutes, scenes, performance).
**THE REEL = the tape between them.** Round trips: machines
→(promote)→ flattened lanes · playing →(reel)→ recorded lanes ·
recorded →(revert)→ machines. The full circle.

## §4 — STANDING QUESTIONS + THE ABSORBED THREAD
- **ROW 8's fate** — design-side position from the discussion:
  RELOCATE, don't drop (the verbs — stutter/freeze/halftime/
  broadcast/the drop — are GESTURES a mute-board can't replace;
  and row 8 is the ratified CONFIG HUB). Candidate homes: a
  rail, the header band, the spacious view. Paul deciding.
- Export semantics: copy (the reel keeps history)? per-lane
  stems vs the mix? lane type convertible in place?
- The MULTI-ROW thread (OPEN-multi-row.md) is ABSORBED here:
  its decided answers (session-persistence · mute-taps ·
  freeze-at-park I/O · copy/paste traffic · all-8 playable ·
  scenes option leaning scene-captured) carry INTO the lanes
  model where applicable; its select-grid top-row export path =
  a third source question to reconcile with §1's provenance law
  (chains parked from browsing = flattened-class? Paul rules).
- The speaker question (what makes a lane "playing" under the
  passage law) stands — still the shaper.
— design-side Claude, recording; nothing ratified.

## §2b — MID-PASS RECONFIGURATION (Paul's probe, 2026-08-27 —
## answered by composing two planned artifacts)
**The snapshot-plus-log law**: state at any moment inside a pass
= the pass-start SNAPSHOT (REVISIT's infra) ⊕ the ACTS LOG's
entries up to that moment (the labels' infra — acts are stamped
at commit). So:
- Revert a cell from AFTER a mid-pass tweak → the machine
  returns WITH the tweak; from before → without. Per-cell
  accuracy, exactly.
- The brutal edge holds: a machine DELETED mid-pass still
  reverts from earlier cells (the snapshot has the deceased).
- Cheap + pure: acts are few, are param-sets, and replay
  deterministically — the derived-never-accumulated law paying
  out (any moment = a boundary + a diff).
**The two anchors, pinned**: whole-pass REVISIT restores
AS-THE-PASS-BEGAN; per-cell revert restores AS-OF-THAT-CELL'S
MOMENT. Same machinery, two anchors; the UI says which it's
doing.

## §5 — STATUS UPGRADE + THE EMITTER RULINGS (Paul, 2026-08-27)
**STATUS: TO BE IMPLEMENTED, WITH PAUL'S GUIDANCE** (supersedes
the header's nothing-ratified line for the LANES MODEL as a
whole — the shape is his intent; he walks the build with Code;
device steps outrank every line, per the door-loop precedent).

**The emitter rulings (his question, resolved):**
- **A LANE = A MUSICAL UNIT, never an emitter's stem.** Parts
  were never emitter-exclusive (TURNS · TAP · DEST spray wires),
  so a recorded pass is inherently multi-wire. One-lane-per-
  emitter would shatter one gesture into unmutable fragments.
  Refused as the structure.
- **Notes carry their recorded wires; playback honours
  addresses verbatim** (the wire-identity law at replay grain).
- **SPLIT BY EMITTER = an EXPORT OPTION, not a law** ("WHOLE |
  SPLIT" on the export; whole is the one-tap default) — for the
  legitimate stem-as-lane want.
- **DECOMPOSITION IS BY COLOUR, not by wire**: revert finds
  machines via per-note colour attribution; each machine's
  wire behaviour returns INSIDE its restored config (a TURNS'd
  machine recorded across three wires reverts as ONE machine
  that deals across three). The emitter axis never enters the
  revert.
- **The clunk cure = defaults**: one pass → one lane, whole,
  one tap; options fold behind. The export dialog stays a
  button until asked to be more.

## §6 — THE TWO DECOMPOSE VERBS (Paul, 2026-08-27 — his in-place
## alternative adopted alongside §5's workshop path)
- **FLIP LIVE (in place — the performance move)**: a recorded
  cell becomes LIVE where it stands. The machine restores UNDER
  THE HOOD (wiring internalized — its door/emitter config
  honoured but hidden; no config ceremony on the stage) and is
  fed **the CURRENT MIDI IN state** — yesterday's machine
  answering today's chord. The frozen-lane objection's final
  cure: any photo, one gesture, alive.
- **UNPACK (to the workshop — the editing move)**: §5's full
  materialization — machines visible in the part grid, guts
  editable, re-export when done.
- **Provenance stays honest**: a flipped cell's source is now
  the machine → its type updates to the LIVE class (the
  provenance law updated, never violated). Flipping "back" is
  free — the reel records the live version as it plays; export
  the new pass.
- Entry lean: hold a recorded cell → FLIP LIVE | UNPACK (the
  two-depth grammar); Paul's glass tunes.
