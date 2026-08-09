# DESIGN → Code — THE DRAG/DROP PAGE (grid · palette · machinery)
# 2026-08-08 · Paul's discussion captured verbatim + the consolidated
# design. Landscape first. This supersedes prior grid-editing flows
# where they conflict.

## PART 1 — PAUL'S MESSAGES (verbatim, in order)

**[1]** "I need help figuring out how the editing and setting up of
the grid could be fun, easy and flow nicely. I've struggled with
every version of this. Don't spec this let's just discuss. Let's do
landscape first. I'm thinking we need a drag and drop method. Let's
say that each cell plays a colour. The colour can be dragged and
dropped from the colour box onto the grid. When a colour is selected
we also see its machinery. This is the name i'm thinking of for the
flow diagram showing receivers, processors and emitters, which also
allows editing of the machine. The colour grid will be top left,
with the main grid bottom left, and the machinery on the right side
of the grid, plus some verbs we'll figure out as we go. The user
will select a color, drag it onto the main grid for placement. While
selected, its machinery will show and be editable. New colours can
be added by choosing an empty place on the colour grid, and this
will have an empty machine by default (showing the flow diagram in
the machinery tab but with default recievers and emmiters and no
processors (so playing the recievers input straight to the defaulted
emitter). If the user drags a cell from the main grid to an empty
slot on the colour grid then a new colour is created in the grid,
and the source of the drag/drop on the main grid swaps to that
colour. At this point the machinary for the old and new colour will
be the same, but any changes made will be applied only to the new
colour."

**[2]** "Ok, let's call it the drag/drop page, with the grid,
palette and machinery as the three main area. Don't want a stamping
mechanism because it gets confusing I think. I like the idea that
dragging and dropping can go between the palette and grid in both
directions, and into different places on their own grids. We maybe
have row selectors to paint full lines and you'd never want a whole
column to be painted with one colour from the pallate. We would also
want control over what's playing in the main grid. The palette can
be 8x8. A randomize button and a 'play this cell' button can live in
the machinery."

**[3]** "Tap on grid should be mute/unmute, and also a select, so
the palette moves to the matching colour, as does the machinery.
Let's keep the grid at 4x4 for simplicity and the cells will only
have colours initially (nothing else). We can add a box onscreen
with a litter icon, and if a colour is dropped onto that it will be
deleted."

**[4]** "When a cell plays in the grid, a downward playhead runs
down the colour in the pallette, so if the user wants to edit that
machine, the process is to choose from pallette."

**[5]** "I like the refill idea. Please write all of this up in a
document to Claude code, including this section of the
conversation."

## PART 2 — THE CONSOLIDATED DESIGN

### The model (the heart)
**A COLOUR IS A MACHINE.** Cells are placements of colours; you
only ever edit COLOURS, never cells — scope is unambiguous by
construction (the old twin/anchor/group-edit dance dissolves).
"MACHINERY" = the flow diagram (receivers → processors → emitters),
shown for the selected colour, editable in place.

### The three areas (landscape)
**PALETTE top-left (4×4 = sixteen colours)** — swatches are flat
colour v1, nothing else. **GRID bottom-left** — cells are flat
colour v1. **MACHINERY right** — the selected colour's flow diagram
+ **RANDOMIZE** (rolls the selected colour, the dice's unambiguous
target) + **PLAY THIS CELL** (audition the machine on the
live/house pool). Verbs: deferred, figured out as we go.

### The drag physics — six landings, one law
Everything is pick-up-and-place; the landing decides:
1. **palette → grid** = PLACE (a cell of that colour).
2. **grid → EMPTY palette slot** = **FORK**: a new colour is born,
   the dragged cell SWAPS to it, machinery starts identical;
   changes thereafter apply only to the new colour.
3. **grid → OCCUPIED palette slot** = **ADOPT**: the cell becomes
   that colour (recolour-by-drag; the fork's mirror — empty births,
   occupied recruits).
4. **grid → grid** = MOVE (overwrite, per the standing ruling).
5. **palette → palette** = reorganise slots.
6. **anything → THE LITTER** (an on-screen box, litter icon):
   - colour → litter = **DELETE the colour AND all its placed
     cells** (nothing else it can mean). NO dialog; ONE undoable
     step; the litter flashes what it took ("−1 colour · 5 cells").
   - grid cell → litter = clear that one cell.
NO stamping mechanism (rejected: confusing). **Row selectors paint
the row with the selected colour**; no column-paint (a column of
one machine is redundant by SINGLE's own logic).

### Taps
- **Grid tap = MUTE/UNMUTE + SELECT** (palette and machinery jump
  to the matching colour). Known quirk, accepted: inspecting via
  the grid costs a mute-toggle; the palette is the pure path.
- **Palette tap = pure SELECT** (machinery follows, no side
  effect). Empty palette slot tap = a NEW colour with the DEFAULT
  MACHINE: default receiver → no processors → default emitter —
  the passthrough, born audible.

### The palette playhead (Paul's ruling: THE REFILL)
When a colour has a cell in the ACTIVE column, its swatch runs a
**downward FILL-WIPE** lasting the column window (consecutive
columns = repeated sweeps — rhythm becomes visible in the palette;
the workhorse pulses, the accent blinks once per pass). Muted
cells don't sweep (silence is still). FREE mode: each ON colour
sweeps its own looping window. **The edit loop this creates is the
page's soul: hear → glance at the palette → tap the sweeping
swatch → tweak.** Motion lives in the palette; the grid stays calm
(the retired cell playheads' true successor).

### Mode + play control
SINGLE | MULTI | FREE lives on this page (the grid BEHAVES while
you build; FREE turns the page into launcher + workshop).

### Design leans (mine, unratified — Paul confirms on device)
- **Machinery edits go LIVE** (no APPLY/CANCEL): consent is
  structural now (editing the colour = editing all its cells is
  the model's meaning); undo covers. The transaction dance was a
  symptom of scope ambiguity; this model is the cure.
- **Cell residue is minimal**: position + MUTE (+ per-cell trigger
  assignments if/when). The less cells own, the cleaner the model
  stays.
- Palette swatches later gain the identity mark (mosaic) for
  distinguishability; v1 stays flat per Paul.
— design-side Claude

## PART 3 — LAYOUT CORRECTION (Paul, 2026-08-08: TOP/BOTTOM split)
**Landscape = a horizontal split: PALETTE + GRID share the TOP
band; MACHINERY takes the BOTTOM, full width.** (Supersedes the
machinery-right layout in [1].)
- **Top band**: the 4×4 palette (swatches ~48–56pt ≈ 220 square)
  beside the 8×8 grid (cells ~56–60pt + rails ≈ 500–540 wide).
  [LEAN, Paul confirms: palette LEFT, grid RIGHT — matches the
  original top-left instinct, and drags flow left→right, pick →
  place.] The palette's spare vertical below it = the natural home
  for **THE LITTER**, the **SINGLE|MULTI|FREE** toggle, and the
  verbs-to-come.
- **Bottom band: MACHINERY full-width** — and the felicity is
  exact: the snake's chain row is 856pt wide by spec; a full-width
  band is its NATIVE habitat (the side-panel version would have
  cramped it). RANDOMIZE + PLAY THIS CELL sit at the band's right
  edge. Flow height ~208–280 fits the remaining ~280–320 in
  landscape with room.
- The 1024 content cap: this page may use full landscape width;
  if Paul wants the cap held globally, the top band centres and
  the snake still fits (856 ≤ 976). His call at prototype.
