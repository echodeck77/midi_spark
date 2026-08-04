# DESIGN → Code — TWO RULINGS: THE OVERLAY RULE + MACRO LANES
# (playhead automation) — 2026-08-03

## PART A — THE OVERLAY RULE (canonized: the user's design law)
**Every section keeps simple, heat-of-the-moment controls on the
surface; its ADVANCED VIEW overlays THE GRID'S RECTANGLE.** The
trade (grid untouchable during depth) is accepted; future hardware
(Launchpad) restores grid hands under overlays.
- **Geometry law**: overlays claim exactly the grid's rect — strips,
  master, macros, scene chips, HOLD stay LIVE around them. You lose
  cell-tapping, never the performance.
- **One at a time**: opening another overlay SWAPS, never stacks.
- **Escape law**: DONE top-right, always; scene-switch closes;
  PERFORM|EDIT stays the header gate for the one sticky view.
- **The simple-surface license**: with depth guaranteed a home,
  strips SHED — new controls default to the advanced view unless
  they pass the heat-of-the-moment test (LATCH passes; curves don't).
- **The depth tell**: one consistent small corner mark on sections
  that open (mitigates depth-blindness; the manual carries the rest).
- Existing conformants: the Edit page ✓ · the emitter page (as
  designed) ✓ · the manual ✓.

## PART B — MACRO LANES: the playhead becomes the automator
**Any macro gains an optional 8-STEP LANE (one value per column).
Lane ON: the playhead drives the macro; the fader thumb follows.**
- **Pure + captured**: value = f(column) — derive-safe, replay-safe;
  lanes are SCENE STATE (per-scene automation curves, free).
- **SMOOTH | STEP per lane**: STEP = jump at column entry; SMOOTH =
  glide across the column toward the NEXT value (the interpolation
  stack + the lookahead gift). Defaults: faders SMOOTH, buttons STEP.
- **BUTTON lanes** = per-column on/off: column-switched rig changes
  (the staged build, sequenced — bypass patterns across the bar).
- **Touch overrides the lane while touching**: spring = release
  returns to the lane; fixed = the override latches until the padlock
  re-engages the lane. The panel stays a performance surface first.
- **Editing v1**: the macro's detail sheet gains the 8-step mini-bar
  row (the house 8×N widget — tap/drag values). **Record-by-riding**
  (arm REC, ride the fader, the lane captures per column) = flagged
  v2, wanted.
- Lane OFF = today's manual macro, unchanged. Chrome-quiet: laned
  macros show a small lane mark; the thumb's motion is the display.
— design-side Claude

## PART C — THE LANES OVERLAY (user, 2026-08-03: the grid shows the
## eight lanes; per-CELL mode supersedes per-lane SMOOTH|STEP)
- **The TIMELINES bank's advanced view = a GRID OVERLAY** (the
  overlay rule's newest conformant): 8 rows = the eight timeline
  macros (name at the row head) · 8 columns = the steps · the REAL
  playhead sweeps it — drawing surface and display are one.
- **Per-cell mode: STEP | SMOOTH | BYPASS**:
  - STEP — jump to this value at column entry, hold.
  - SMOOTH — glide across this column toward the NEXT NON-BYPASSED
    value (bypassed columns are skipped when finding the target).
  - BYPASS — the lane is ABSENT this column: the macro sits at its
    manual/fader position (offset suspended) — sparse, rhythmic
    automation; untouched columns tell the base truth.
    [RESOLVED 2026-08-04 → MANUAL-POSITION. The lane goes absent and the
    fader's own value governs that column — sparse automation with honest
    gaps. Hold-previous-value is retired as the fallback (revisit only if
    device use shows gaps feel wrong).]
- **Rendering**: value = fill-height mini-bar in the cell · STEP =
  flat-top · SMOOTH = ramped edge toward the next · BYPASS = a dim
  dash. Chrome-quiet: the sweep and the bars are the display.
- **Gestures**: vertical DRAG on a cell = set value (auto-activates
  STEP if bypassed) · TAP = cycle STEP→SMOOTH→BYPASS · a horizontal
  STROKE across a row draws the curve (one undoable step, the stroke
  law).
- Entry: the TIMELINES selector's depth / the [AB] popup's timeline
  rows → the overlay; DONE returns; scene-switch closes; lanes+modes
  are scene state as designed.

## PART C AMENDMENTS (user, 2026-08-03)
**① THE MODE RAIL — modes become a side-toggle BRUSH.** The overlay's
side rail carries four dedicated toggles: **ON · OFF · SMOOTH ·
STEPPED**. One is armed; tapping grid cells PAINTS that mode — modes
set dynamically on the grid itself, strokes included (paint a row's
back half OFF in one swipe). Eligibility by lane kind (the mover
rule's echo): continuous lanes take SMOOTH/STEPPED/OFF; discrete
(button) lanes take ON/OFF. Ineligible toggles dim per the pointed
row. [RESOLVED 2026-08-04 → RESERVED TO DISCRETE LANES. ON/OFF apply
only to discrete (button/step) lanes; continuous lanes use
STEP/SMOOTH/OFF exclusively. The dim rule as drawn stands — ON dims on
a pointed continuous row.]
**② PER-LANE RATE — automation at every timescale.** Each lane gains
a RATE chip: from **×8 (all eight steps inside ONE column — the
LFO-fast wobble)** through ×1 (one step per column, the default)
down to **÷8 (one step per pass — the lane arcs across EIGHT
PASSES of the scene: the slow filter sweep).** Step index =
f(absolute beat × rate) — pure, replay-safe, phase beat-locked
across scene switches (values are scene state; phase is the
clock's). The rate chip lives at the row head beside the lane's
name.
