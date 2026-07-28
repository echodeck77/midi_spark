# Design ferry — the user's SIX /btw requirements (2026-07-28)
_Preserved from the accumulator (fork terminal session, ferried as the reliable path). Three captured
VERBATIM; three RECONSTRUCTED from truncated /btw lines and awaiting the user's confirmation of the tails.
These are held requirements — build one at a time on the user's call, not yet greenlit._

## VERBATIM (captured from screen)

### ① COPY/PASTE replaces MOVE/COPY (bottom verb row)
Bottom row becomes **COPY · PASTE**. PASTE is greyed/disabled until something has been copied. COPY captures
the source into a **session-scoped clipboard that PERSISTS after release**; PASTE — enabled once the clipboard
is non-empty — stamps the clipboard cell wherever you tap while held.
- **Design-side consequence:** MOVE **leaves the cluster** — relocation becomes COPY→PASTE→DELETE (or awaits a
  later gesture). The persists-after-release clipboard revises 11b's one-hold copy model (accepted, device ruling).
- **Code-side note:** no implementation blocker — the model already has `moveCellTo`/copy plumbing; a persistent
  clipboard is a VC-held object. MOVE dropping is a UX loss (two-step relocation), not a technical one.

### ② Enlarge the preset window + undo/redo to its right
Bigger preset selector in the header; **UNDO/REDO** buttons beside it, dimmed when nothing is available.
(Undo/redo re-homes here after the GRID CONTROLS reshape — stays visible.)

### ③ "Selected" visual — exactly TWO sources
A cell shows as **selected** only when (a) PLACED while PLACE is held, or (b) via the SELECT verb. In NO other
instance is a cell shown selected. **One shared "selected" look** for both sources.

## RECONSTRUCTED — CONFIRM THE TAILS (truncated /btw lines)

### ④ Mid-hold colour switch re-tints (truncated)
"When PLACE is being used, if the user selects a different colour then the chevrons and all placed ce…"
- **Read:** a mid-hold palette-chip switch re-tints the chevrons AND the cells already placed this hold.
- **CONFIRM:** do placed-this-hold cells **retro-repaint**, or only SUBSEQUENT placements take the new colour?

### ⑤ SELECT scope (truncated)
"One or more cells can be selected when SELECT is held, applied per cell or using the row or …"
- **Read:** SELECT's taps work per-cell AND via the row chevrons.
- **CONFIRM:** do **columns** join rows as selectors, or rows only?

### ⑥ One placement per column (truncated)
"When placing a cell, it can only applied to one cell per column. This will stop two cells from being plac…"
- **Read:** **one placement per column** — a stroke paints one-per-column lines, preventing accidental vertical
  doubles.
- **CONFIRM scope:** per-STROKE, per-HOLD, or ABSOLUTE (never two placed cells in a column at all)?
