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

## B — LAYOUT (revised: full takeover, not a compact-strip swap)
**B1.** Given EDIT is armed and pointing at a cell, then the CELL EDIT
PAGE replaces the entire working view (grid, strips, FLOW, band desk —
all of it) — not a panel swap within the existing layout. This mirrors
the existing "the surface becomes the tool" principle (INSPECT's
region-takeover, the strips' session-faces during PLACE/SELECT), taken
to full scale, because a compact-strip version left too many surfaces
competing for attention at once.
**B2. The breadcrumb (the anchor back to the grid)**
- Then a slim strip at the top of the page shows: the scene name, the
  edited cell's column number, and a small 8-dot minimap with the
  edited cell lit — so the user always knows where in the arrangement
  they are without seeing the grid itself.
- Given LOOP (section G) is engaged, then the minimap's lit dot shows a
  small looping indicator — this REPLACES the need for any visible
  "other columns are silent" state, since the grid isn't on screen.
**B3. Entry/exit**
- Tapping EDIT + a cell TRANSITIONS to the Cell Edit page (a push, not
  an overlay). DONE, or re-tapping EDIT, returns to the grid instantly
  — no state is lost either direction (the standing no-save-step law).
**B4.** The sound desk (Colour + Processor) lives WITHIN the Cell Edit
page now, not as a separate demoted strip — "jump to Colour" becomes a
section of this page rather than a swap with an external panel.
**B5. Internal structure: ONE ACCORDION, not tabs.**
- NOT tabs — the feature groups (IDENTITY, INPUT, TRIGGERS, OUTPUT) are
  not equal-weight peers; tabs would hide LOOP/the test pad behind a
  click exactly when they're needed mid-edit, and would stack a second
  drill-down on top of the TRIGGERS accordion's own picker.
- Given the page layout, then: the breadcrumb (B2) stays PINNED at the
  top; a PERSISTENT strip directly below it always shows LOOP + the
  TEST CELL (section G/H) — never collapsed, never tabbed, since these
  are "listen while you work" controls, not configuration you visit.
- Below that, IDENTITY · INPUT · TRIGGERS · OUTPUT run as ONE VERTICAL
  ACCORDION (collapsible to a summary line each; one section open at a
  time by default) — the same discipline the TRIGGERS rows already
  use, one level up, so opening TRIGGERS and tapping the test pad never
  requires leaving or switching anything.
(Exact internal geometry is device-iteration territory.)

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
- **Destination sequence** ("chop between outputs") — GRAPHICAL, an
  8×2 grid (one column per slice, matching the main grid's own
  vocabulary — no new interaction language):
  - **Row 1 = MAIN** (tap a column to activate that slice; lit = plays
    normally). Tapping a LIT main cell again toggles a small REDIRECT
    mark on it (a dot/half-fill) — that slice ALSO routes to the ALT
    set below, layering rather than replacing.
  - **Row 2 = MUTE** (tap = this slice is silent regardless of any
    redirect mark; MAIN and MUTE are exclusive per column).
  - **Four ALT DESTINATION toggles (A–D) below the grid** — one shared
    set, not per-slice: every slice carrying the redirect mark routes
    to whichever of A–D are lit here, uniformly.
  - Applies at admission; MUTE forces a note-off at that slice's edge.
  - Inherits PHASE: under LEGATO, an identical adjacent cell's
    destination-mask (both rows + the ALT set) continues across the
    boundary.

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
