# IMPLEMENTATION PLAN — finish the /btw authoring UX (next-session priority, decided 2026-07-29)

_The user's chosen first focus after this thread. All behavior decisions below are RATIFIED (user, 2026-07-29)
— build to them, no re-asking. Each increment: confirm current code first (I've noted likely homes but they
may have shifted), build, iOS-build-check, commit atomically, tick `pending-tasks.md` + add a line to CLAUDE.md
status. UI files aren't in the unit target, so device-verify is the user's; state exactly what to check._

## Context this plan assumes (the modeless verb model, as built)
- Verbs are SPRING-HELD pills: PLACE · DELETE · SELECT · COPY · PASTE (`Verb` enum in `AudioUnitViewController`).
  Selection is TRANSIENT. PLACE uses `placeToggle(&scene,col,row)` → `placeFresh`/`placeUndo`;
  `placedThisHold = placeFresh ∪ placeUndo.keys`; `lastPlaced`. Row-scope taps go through `doVerbRow` (place/
  delete/select). The palette `onPick`: `selection.isEmpty ? pickPalette(id) : recolorSelection(id)`.
- Colour-level editing lives in the PROCESSOR panel(s) (`ProcessorBox` / the `colourBox` brush).

## The increments (build in this order — small→big, dependency-aware)

### 1. /btw ⑥ — ONE PLACEMENT PER COLUMN, scope = PER-HOLD  ✦ decided
During a single PLACE hold, at most one cell may be placed per column; a tap in a column already placed THIS
hold is blocked (release + re-hold to add a 2nd cell — vertical chains are still fully buildable, just not in
one hold). Applies to taps AND to STROKES (increment 5).
- **Where:** guard inside the PLACE path (`placeToggle` / `doVerb .place`), keyed on whether `placedThisHold`
  already contains a cell in `col`. Re-tapping the SAME cell still toggles it off (the existing undo-place).
- **Acceptance (device):** hold PLACE, place col2/row0 ✓; tap col2/row1 → nothing happens; release, re-hold,
  place col2/row1 ✓. A model-level test on the per-hold column set is worth adding.

### 2. /btw ④ + PALETTE-LIVE-DURING-HOLDS — mid-hold brush switch RETRO-REPAINTS  ✦ decided
While PLACE is held, tapping a palette chip switches the brush AND **repaints the chevrons and EVERY cell placed
this hold** to the new colour; subsequent placements use the new brush too (the whole hold recolours as one).
- **Where:** the palette `onPick` during a PLACE hold (currently just `pickPalette`). On a mid-PLACE-hold pick:
  set `brush`, then `editScene` to recolour every `placedThisHold` cell to the new colourID, and re-tint the
  PLACE chevrons/invite. Keep it ONE undo step with the placements (coalesce), so CANCEL still reverts the
  whole hold via `gridSnapshot`.
- **Acceptance (device):** hold PLACE · place 3 gold · tap cyan chip → the 3 cells become cyan + chevrons cyan ·
  place a 4th → cyan. CANCEL → all gone.

### 3. /btw ⑤ — SELECT SELECTORS = per-cell + ROW chevrons (NOT columns)  ✦ decided
Under a SELECT hold: tapping a cell toggles it; tapping a ROW chevron selects/toggles that whole row. Column
keys do NOT select (they stay the §5b lap-hold). Likely MOSTLY BUILT (`doVerbRow` handles SELECT; the column
keys are the separate `ColumnHoldOverlay`).
- **Where:** verify `doVerbRow .select` toggles the row; confirm the column overlay never feeds selection.
- **Acceptance (device):** SELECT held · tap cells toggle · tap a row chevron → whole row rings · tap a column
  key → does NOT select (lap behavior only). This may be a verify-only increment.

### 4. PALETTE-LIVE completion note
Increment 2 delivers the brush-switch mechanism. Confirm the "paint pots · canvas · brush" model reads right on
device (multi-colour add = hold PLACE · chip · place · chip · place · release). No separate build if 2 covers it.

### 5. STROKES — drag = batch, one undoable step per swathe  ✦ the big one
Every held verb works per-tap AND per-STROKE: dragging across cells while a verb is held applies it to each cell
under the finger — PLACE paints a run · DELETE sweeps · SELECT lassos. The whole swathe is ONE undo step.
- **Where:** a `DragGesture` on the grid (likely in `GridView`/the VC's grid block) active while `heldVerb != nil`,
  mapping the finger location → (col,row) and applying the verb once per newly-entered cell. Respect ⑥ (PLACE
  stroke = one-per-column). Coalesce the whole drag into a single undo (open one `gridSnapshot`/coalesceKey at
  drag start, commit at end).
- **Acceptance (device):** hold PLACE, drag across a row → a clean run (one per column) · hold DELETE, drag →
  sweep · hold SELECT, drag → lassos the swathe · ONE undo reverts the whole stroke.

### 6. THE MIXED-SET LAW — processor panels dim to "MIXED" for multi-colour selections  ✦
SELECT's manual taps may build sets across ANY colours (mixed = legal; move/rewire/delete apply to all). But the
Colour-level PROCESSOR panels go live only when the selection is SINGLE-colour; otherwise they DIM to a "MIXED"
state (a mixed set has no honest Colour-level edit — don't pretend). Cell-level properties (routing, emitters,
delete) still apply to the whole mixed set.
- **Where:** the processor panel(s) (`ProcessorBox`/`colourBox`): when `selection` spans >1 distinct colourID,
  render a dimmed "MIXED" face + disable the Colour-level controls; single-colour (or empty→brush) = normal.
- **Acceptance (device):** select two different-Colour cells → the processor panel dims to MIXED; select
  same-Colour cells → it edits normally; routing/emitter/delete still act on the mixed set.

## Verification & housekeeping
- Off-device: `xcodebuild -scheme MidiSpark -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`
  after each; keep the 329-test unit suite green (add model tests where logic is pure — e.g. ⑥'s column set).
- After each increment: tick it in `pending-tasks.md`, add a commit line to CLAUDE.md "Current status".
- This whole chunk = the modeless-authoring completion; when done, the /btw six are fully closed.
