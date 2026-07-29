# The verbs — behaviour (acceptance criteria)

_Plain-language reference for the five grid verbs (PLACE · DELETE · SELECT · COPY · PASTE), written in
Given / When / Then. This is the agreed target behaviour for the verbs, the grid, routing, and the
receiver/emitter strips. Scope: the verb buttons, the main grid, routing, receivers/emitters, and choosing
colours._

---

## The model in one breath
The five verbs live in a button cluster (PLACE on top, then DELETE · SELECT, then COPY · PASTE). A verb is
**spring-held**: it is active only while you hold its button down. Let go and it's done — there is no armed
mode and no on/off toggle. While a verb is held, tapping the grid does that verb. With **no** verb held, a grid
tap is a performance trigger instead (it flips a cell's ALT state), not an edit. It is therefore not possible
for a cell to show as selected unless applied via the verb buttons.

To the right of every grid row is a **row chevron**; tapping it applies the held verb to that whole row.
PLACE / DELETE / SELECT also show a coloured **banner** across the top with a **CANCEL** button.

---

## PLACE

**Button**
- **Given** nothing is held, **when** you press and hold PLACE, **then** PLACE becomes active, a green banner
  reads "Place cell(s) — tap the grid or a row · choose routing", and this hold's memory starts fresh (it also
  snapshots the grid so CANCEL can undo everything you do this hold).
- **Given** PLACE is held, **when** you release the button, **then** PLACE ends and your placements stay.

**Main grid**
- **Given** PLACE is held, **when** you tap an **empty** cell, **then** a new cell is placed in the current
  brush colour. If any cell above it in the same column is occupied, then the cell's input is wired to that cell above
  (a "downhill" link); if nothing is above, the new cell is pointed at receiver R1
  
  
  
  .
- **Given** PLACE is held, **when** you tap a cell that is **already occupied**, **then** it is replaced with a
  brush-colour cell that keeps the old cell's input wiring, and the original is remembered.
- **Given** you placed or replaced a cell earlier **in this same hold**, **when** you tap it again, **then** it
  is undone — a placed-on-empty cell is removed, and a replaced cell is restored to its original.
- **Given** PLACE is held, **then** every cell you've placed this hold wears a white "selected" border.

**Row chevron**
- **Given** PLACE is held, **when** you tap a row chevron, **then** one cell is placed (or toggled, by the same
  rules above) in each of the 8 columns of that row.

**Routing**
- **Given** PLACE is held, **then** EVERY cell you have placed this hold is a routing **focus** — including a
  whole row placed with a row chevron. Around each focus, its **SRC** candidates (cells above) and **DEST**
  candidates (cells below) light up, and the receiver + emitter strips offer their ROUTE faces.
- **Given** a focus with candidates lit, **when** you tap a lit **SRC** above, **then** the focus is wired to
  read from that row; **when** you tap a lit **DEST** below, **then** that cell reads from the focus — in both
  cases instead of placing a new cell.
- **Given** the receiver / emitter ROUTE strips are showing, **when** you tap a receiver or an emitter, **then**
  it applies to ALL of this hold's placed cells at once (so you can route a whole row in one tap).

**Choosing colours**
- **Given** PLACE is held, **then** new cells use the current brush colour.
- **Given** PLACE is held and you tap a different palette colour, **then** the brush changes and **only new
  placements** take the new colour. (Cells already placed this hold do NOT change today — the desired change is
  the retro-repaint spec below.)

**Cancel**
- **Given** PLACE is held, **when** you tap CANCEL in the banner (with your other hand), **then** every change
  from this hold is reverted and PLACE ends.

- **Given** PLACE is held and you've placed some cells, **when** you tap a different palette colour, **then**
  the chevrons AND **every cell already placed this hold** recolour to the new colour, and later placements use
  it too (the whole hold recolours as one). The processor desk switches to that colour.

- **Given** PLACE is held and you've placed a cell in a column, **when** you try to place a second cell in that
  same column during the same hold, **then** it is blocked (release and re-hold to add another in that column —
  vertical stacks are still buildable, just not in one hold).

**Routing carries to the next cell**
- **Given** PLACE is held and you have placed a cell and chosen its emitters and its receiver (via the strips),
  **when** you place further cells in the same hold, **then** each new cell defaults to the SAME emitters and the
  SAME receiver as the last cell you set up — so you can lay down a run of identically-routed cells without
  wiring each one.
- **Given** you change the emitters or receiver again later in the hold, **then** the cells you place after that
  inherit the new choice (the template is always the most recently set-up cell).

## DELETE

**Button**
- **Given** nothing is held, **when** you press and hold DELETE, **then** a red banner reads "Delete cell(s) —
  tap the grid or a row · links cut", and the grid is snapshotted for CANCEL.

**Main grid**
- **Given** DELETE is held, **when** you tap an occupied cell, **then** it is deleted and any routing to or from
  it is cut — cells that were reading from it fall back to MIDI-IN (they do NOT reconnect to its parent).
- **Given** DELETE is held, **when** you tap an empty cell, **then** nothing happens.

**Row chevron**
- **Given** DELETE is held, **when** you tap a row chevron, **then** all 8 cells in that row are deleted, their
  routing cut the same way.

**Cancel**
- **Given** DELETE is held, **when** you tap CANCEL, **then** the deletions are reverted and DELETE ends.

## SELECT

**Button**
- **Given** nothing is held, **when** you press and hold SELECT, **then** a cyan banner reads "Select cell(s) —
  tap to toggle · recolour with the palette".
- **Given** SELECT is held, **when** you release the button, **then** the selection is **cleared** — the built
  set does NOT survive the hold. (Any recolour or routing you did during the hold stays; the highlight ends.)

**Main grid**
- **Given** SELECT is held, **when** you tap an occupied cell, **then** it toggles in or out of the selection.
- **Given** SELECT is held, **when** you tap an empty cell, **then** nothing changes
- **Given** cells are selected, **then** each wears a white ring (the same "selected" look PLACE uses).

**Row chevron**
- **Given** SELECT is held, **when** you tap a row chevron, **then** every occupied cell in that row toggles
  in or out of the selection.

**Columns**
- **Given** SELECT is held, **when** you press a numbered **column** key, **then** it does NOT select anything —
  the column keys are the separate performance "lap" hold, not a selector.

**Routing**
- **Given** one or more cells are selected, **then** they become the routing focus (sources above / heads below
  light up, excluding the selected cells).
- **Rule — per column:** each selected cell offers **SRC** candidates above it and **DEST** candidates below it
  in ITS OWN column; tapping a SRC/DEST candidate wires the selected cell that shares that column. A column with
  no selected cell shows no candidates; a column with more than one selected cell shows none (ambiguous).
- **Given** cells are selected with candidates lit, **when** you tap a lit **SRC** above, **then** the selected
  cell in that column is wired to read from that row; **when** you tap a lit **DEST** below, **then** that chain
  is grafted under the selected cell in that column — in both cases instead of toggling the tapped cell.

**Choosing colours**
- **Given** one or more cells are selected, **when** you tap a palette colour, **then** every selected cell is
  recoloured to that colour (the chip does NOT change the brush while a selection exists).

**Cancel**
- **Given** SELECT is held, **when** you tap CANCEL, **then** routing edits made this hold are reverted and the
  selection is cleared.

## COPY

**Button**
- **Given** nothing is held, **when** you press and hold COPY, **then** COPY becomes active. (COPY and PASTE do
  not show the top banner.)
- **Given** something has been copied, **then** the COPY button wears a small dot.

**Main grid**
- **Given** COPY is held, **when** you tap an occupied cell, **then** that cell is captured into a
  **session clipboard**. The clipboard **persists after you release** — it stays until you copy something else.
- **Given** COPY is held, **when** you tap an empty cell, **then** nothing is captured.

**Row chevron**
- **Given** COPY is held, **when** you tap a row chevron, **then** nothing happens (row-scope copy is not wired).

## PASTE

**Button**
- **Given** the clipboard is empty, **then** the PASTE button is greyed out and cannot be pressed.
- **Given** the clipboard holds a cell, **when** you press and hold PASTE, **then** PASTE becomes active.

**Main grid**
- **Given** PASTE is held, **when** you tap any cell (empty or occupied), **then** the clipboard cell is stamped
  there. Every tap while held stamps again. (A stamped top-of-chain cell is kept pointed at a receiver so it
  doesn't silently bypass its input.)

**Row chevron**
- **Given** PASTE is held, **when** you tap a row chevron, **then** nothing happens (row-scope paste is not wired).

**Relocating a cell**
- **Given** you want to move a cell, **then** the route is COPY it → PASTE it elsewhere → DELETE the original
  (there is no single MOVE verb).

## Choosing colours (across the verbs)
- **Given** no cells are selected, **when** you tap a palette colour, **then** it becomes the **brush** (the
  paint colour PLACE uses and the colour the PROCESSOR panels edit).
- **Given** cells are selected under SELECT, **when** you tap a palette colour, **then** those cells are
  recoloured instead (the brush is not changed).
- **Given** you want to edit a colour's treatment (its processor type, transpose, morph, A/B), **then** the
  PROCESSOR panels always edit the **brush** colour.

## Routing candidate cells (how the grid looks while wiring)

**Look**
- **Given** a cell is the routing focus (a placed or selected cell whose routing is being changed), **then** it
  draws with the **WHITE** selected ring — never a yellow/amber outline (a yellow ring is invisible on a yellow
  cell). The candidate cells around it look as below.
- **Given** a cell **above** the focus can feed it, **then** it is a **SRC** candidate: the whole cell **body
  pulses** (fades in and out) with a large, prominent **"SRC"** label sitting solid on top (matching the receiver
  ROUTE IN face).
- **Given** a cell **below** the focus can be grafted under it, **then** it is a **DEST** candidate: the whole
  cell **body pulses** with a large, prominent **"DEST"** label on top (matching the emitter ROUTE OUT face).
- **Given** any candidate, **then** its BODY pulses (not just an overlay) and it wears **no outline or ring** —
  the prominent SRC / DEST label (which stays solid) marks it, so a candidate never looks like it is selected.

**Behaviour**
- **Given** candidates are showing, **when** you tap a **SRC** cell above, **then** the focus is wired to read
  from that row (route-in) — no new cell is placed or toggled.
- **Given** candidates are showing, **when** you tap a **DEST** cell below, **then** that chain is grafted under
  the focus — again instead of placing or toggling.
- **Given** candidates are showing, **when** you tap anywhere that is NOT a candidate, **then** the tap does the
  normal verb action (place / toggle) instead of wiring.

## Receivers — the MIDI INPUT strips (above the grid)

**Recievers Look + behaviour while wiring (ROUTE IN face)**
- **Given** a verb is held and a cell is the routing focus, **then** each input strip dims and shows a big
  **ROUTE IN** face in the strip's colour; the input the focus cell currently reads from
  wears a solid ring while the others gently pulse. All recievers display "SRC" prominently.
- **When** you tap an input's ROUTE IN face, **then** the focus cell's input is routed to that receiver.

**Emitters Look + behaviour while wiring (ROUTE OUT face)**
- **Given** a verb is held and a cell is the routing focus, **then** each output strip dims and shows a big
  **ROUTE OUT** face with a **green** glow; an emitter the focus cell already sends to is lit while the others gently pulse.
   All emitters display "DEST" prominently.
- **When** you tap an output's ROUTE OUT face, **then** you toggle whether the focus cell sends to that emitter.

## STROKES — drag to apply a verb across many cells
- **Given** any verb is held, **when** you drag your finger across the grid, **then** the verb applies to each
  cell the finger passes over, as ONE undoable step — PLACE paints a run (one per column), DELETE sweeps,
  SELECT lassos.

## MIXED-SET law — processor panels dim for mixed selections
- **Given** a SELECT selection contains cells of more than one colour, **when** you look at the PROCESSOR
  panels, **then** they dim to a "MIXED" state and disable the colour-level controls (cell-level edits like
  routing, emitters, and delete still apply to the whole set).

## Desk re-point (hard rule) — selecting a colour points the desk at it
- **Given** you select a cell, or cells that are all one colour, **when** the selection is a single colour,
  **then** the COLOUR + PROCESSOR desk re-points to that colour so you're editing what you selected.
  (This is a hard rule: selecting a colour must always re-point the desk.)

## Verb latching — DECIDED: verbs do NOT latch
- **Given** a verb button, **when** you long-press it, **then** nothing special happens. Verbs are
  **spring-only**: a verb is active only while its button is held, and releasing ends it. (Long-press latching
  was considered and rejected.)

## Notes
- **⑤ (SELECT = per-cell + row chevrons, columns never select)** is already how the code behaves today
  (described under SELECT above).
- **① COPY/PASTE replacing MOVE**, **② the enlarged preset selector with UNDO/REDO**, and **③ the single
  shared "selected" look** are all built (described above).
- **HOLD** (a sixth button in some designs) is a performance sustain-latch, not a grid verb, and is not part of
  the cluster today.
