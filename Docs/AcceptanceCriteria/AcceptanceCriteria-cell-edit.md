# AcceptanceCriteria — cell-edit.md
_Given/When/Then, plain language, per the verbs-behaviour.md convention.
Supersedes AcceptanceCriteria-cell-station.md IN FULL — the EDIT verb
formalises and replaces that earlier sketch. Scope: the Cell Edit
surface only (verb behaviour, layout, and every feature living inside
it). [Working name "EDIT" used throughout — a placeholder pending the
user's word.]_

## A — THE VERB
**A1. A sixth control, different in kind**
- Given the five existing verbs (PLACE · DELETE · SELECT · COPY ·
  PASTE) are all SPRING-held, then EDIT is added as a TOGGLE: tap to
  arm, tap again (or DONE inside the station) to disarm. [Its button
  should read visually distinct from a spring verb being held — a
  latched/filled look while armed — so the gesture-model difference is
  legible, not just implied.]
**A2. Division of labour from SELECT**
- SELECT continues to build multi-cell batches (DELETE, recolour,
  scope-apply). EDIT points the station at exactly ONE cell for deep
  editing. They do not overlap.
**A3. Mutual exclusion**
- Given EDIT is armed, when the user engages any of the five spring
  verbs, then EDIT disarms first (one editing intent at a time).
**A4. Pointing**
- Given EDIT is armed, when the user taps an OCCUPIED cell, then the
  station points at it (re-pointing freely between cells without
  leaving EDIT).
- Given EDIT is armed, when the user taps an EMPTY cell, then nothing
  happens (EDIT edits what exists; PLACE creates).
**A5. Grid taps are suppressed while armed**
- Given EDIT is armed, then tapping any grid cell NEVER fires its
  TAP/HOLD trigger (only re-points, per A4). This is the rule that
  makes the TEST CELL (section H) unambiguous — while editing, it is
  the ONLY surface that fires a trigger live.
**A6. Scene changes**
- Given EDIT is open, when the active SCENE switches, then EDIT
  auto-closes (the pointed cell's context no longer applies).

## B — LAYOUT
**B1.** Given EDIT is armed and pointing at a cell, then the CELL EDIT
panel claims the PRIMARY slot (where the sound desk — Colour +
Processor — currently sits).
**B2.** Then the sound desk demotes to a compact strip alongside/below
(not hidden) — only ONE of {sound desk, Cell Edit} occupies the primary
slot at a time; a "jump to Colour" control swaps which.
**B3.** Then the grid, strips, FLOW, and the band/master desk remain
visible and interactive throughout — no modal takeover, no pop-up.
(Exact geometry is device-iteration territory.)

## C — IDENTITY (within Cell Edit)
- Colour swatch, name, grid position. (No separate read-only wiring
  summary — INPUT below is fully live, superseding the prior sketch.)

## D — INPUT
- **Source**: receiver A–D / row n / none — a value chip (tap=picker,
  drag=scrub), per the value-chip grammar.
- **Chord split**: ALL · TOP n · BOTTOM n · KEY RANGE (split point +
  side) — value chips; n and the split point are drag-scrubbable.
- **Velocity window**: floor/ceiling.
- **Octave shift** and **transpose**: existing steppers, unchanged.
- Rewiring by tapping the grid/strips directly (SELECT's spatial
  routing) remains available and edits the SAME underlying fact —
  Cell Edit's picker and SELECT's spatial taps are two doors, one lock.

## E — TRIGGERS
- TAP · HOLD · ARRIVE · LEAVE · SCENE rows, accordion discipline
  (assigned = summary; unassigned = dim ＋; one open at a time).
- **Retrigger style** (TAP only): CUT | LAYER, default CUT.
- **REDIRECT** — a TAP/HOLD action: choosing it reveals ALT DESTINATION
  toggles (A–D) inline.
  - Hold = momentary (springs back on release). Tap = sticky (toggle).
  - Applies at ADMISSION: new note-ons use the redirected set; sounding
    notes finish on their original destination; a LEGATO drone
    re-derives its destination at its next column boundary (the
    existing adoption law, unchanged).

## F — OUTPUT
- Main destination toggles (A–D). [DEFERRED CALL, left open per the
  user: whether this duplicates or supersedes the spatial ROUTE OUT
  tapping under SELECT/PLACE.]
- Alt destination set (A–D) — feeds REDIRECT when defined.
- **Destination sequence** ("chop between outputs"): an 8-slice
  sequence, each slice MAIN · ALT · REST, riding the alt set.
  - Applies at admission; REST forces a note-off at that slice's edge.
  - Inherits PHASE: under LEGATO, an identical adjacent cell's
    destination-mask continues across the boundary.

## G — LOOP (real-engine auditioning)
_Supersedes the earlier "sandboxed audition chassis" suggestion — per
the user's direction, LOOP runs through the SAME Router/Kernel/emission
path as normal performance. Real synths sound; real CLAIM/DUCK/ALT
apply; real voice tables are shared._
**G1. The mechanism — a narrowed wrap boundary**
- Given LOOP is engaged for a cell in column N, then the pass's wrap
  boundary narrows to [N,N]: after column N plays, the next advance
  returns to N.
- This reuses ALL existing per-column derivation and the column-
  boundary transition/adoption laws unchanged — a single-column loop is
  the degenerate case the continuity tests already cover (N repeats of
  one column = identical-adjacent-LEGATO, extended). Low engineering
  risk: no new derivation path, only a boundary parameter.
**G2. Explicit, not automatic** — LOOP is a toggle INSIDE the Cell Edit
station; never engaged automatically by opening EDIT.
**G3. Transport interaction** _[DESIGN CALL — confirm]_
- Given the transport is already PLAYING when LOOP engages, only the
  wrap boundary narrows; playback elsewhere is unaffected.
- Given the transport is STOPPED when LOOP engages, then engaging LOOP
  STARTS playback (visibly — the play indicator lights), looping only
  the edited column. [The conservative alternative: LOOP does nothing
  until the user presses play themselves.]
**G4. Restoring on exit**
- If LOOP did NOT start playback, disengaging widens the boundary back
  and playback continues seamlessly from column N forward.
- If LOOP DID start playback, disengaging returns the transport to
  STOPPED (LOOP restores whatever state it found).
**G5. ARRIVE/LEAVE/SCENE audition for free** — their existing "every N
passes" counters run against the loop's repeats with ZERO new
trigger-execution logic.
**G6. Scope** — loops exactly the edited cell's column (a range is a
possible future refinement, not v1).

## H — THE TEST CELL
**H1.** A dedicated tap/hold surface, visible ONLY while Cell Edit is
open, physically separate from the 8×8 board and visually distinct
(e.g. a dashed/rounded "TEST" pad) — never mistakable for a real cell.
**H2.** When tapped/held, it fires the POINTED cell's LIVE TAP/HOLD
trigger action (including unsaved edits — there is no save step) and
emits through the SAME real engine/emitter path as the real cell would
(not sandboxed) — subject to real CLAIM/DUCK/ALT interactions with
whatever else is sounding, including LOOP's repeats. Intentional:
realistic feedback, not isolated feedback.
**H3.** The test pad is available regardless of LOOP's state — the two
are orthogonal controls (roles are independent, as elsewhere).
**H4.** Because grid taps are suppressed while EDIT is armed (A5), the
test pad is the ONLY surface that fires a trigger live while editing —
no double-fire case exists.
**H5.** Division of labour: TAP/HOLD are tested via the test pad.
ARRIVE/LEAVE/SCENE are tested via LOOP (watch them fire as the column
repeats). The pad does not simulate the latter three.
**H6.** The pad displays the pointed cell's current trigger glyph(s) —
the same glyphs as the cell face — before you press it.
_[Later, optional: a small velocity control on the test pad. Not
required for v1.]_

## I — UTILITIES
- **Apply to…** (twins / all \<colour\> / row) — one undoable step
  (the shipped applyToScope path), covering trigger + input settings.
- **Copy / Paste CONFIG** — distinct from the grid's COPY/PASTE verb
  (whole-cell + placement): this copies just the Cell Edit
  configuration onto another already-placed cell.
- **Reset to defaults.**
- **Delete cell** — same DELETE = SEVER law as the grid verb.

## EXPLICIT EXCLUSIONS (not in this doc)
- Emitter-picker vs. spatial ROUTE OUT (F) — open, deferred.
- Per-cell parameter SEASONING/overrides — separate future.
- CHOP as a Colour-side processor (A/B/REST timbre sequencing) — a
  processor-roster item, documented elsewhere, not Cell Edit.
— design-side Claude, 2026-07-30
