# AcceptanceCriteria — THE WINDOW (the pre|post note graphic) (captured 2026-08-06)

**STATUS: CAPTURED, NOT BUILT.** Design + Paul (ferry `SPEC-the-window-graphic.md`). ONE parameterized component —
a mini piano-roll with a NOW divider — used everywhere a note stream wants showing. The right side is TRUE derived
schedule (only this engine can do it honestly), not animated guesswork.

## THE LAYOUT
- Horizontal lane · pitch = vertical (auto-fit to the content's range) · time = horizontal. **THE DIVIDER = NOW**
  (a thin bright vertical at ~40% from the left).
- **LEFT of the divider — the INPUT**: the held pool as SUSTAINED BARS (dim, from the left edge to the line — "what
  you are holding"). A chord in = three long quiet bars.
- **RIGHT — the DERIVED FUTURE**: the cell's upcoming emissions as short note rects, SCROLLING LEFT at tempo; a note
  FIRES as its leading edge hits the divider (a brief flash/glow), then vanishes (or a very short fading tail past
  the line). Velocity → rect brightness; pitch → height. Rests = gaps; LENGTH/ties = rect widths — every
  articulation displays for free.

## THE DATA (the honest part)
- **LIVE**: input = the cell's effective pool; future = the REAL derived schedule looked ahead ~2 beats (derivation
  is pure → derive-ahead is free). Budget: only VISIBLE instances derive; one cell's lookahead is cheap.
- **CANNED** (library entries · manual diagrams · empty-pool contexts): the same component fed a reference chord +
  the chain, looping — library entries preview their ACTUAL behaviour, derived not illustrated.
- Silent/paused = STATIC (invisible=frozen; left bars may show, nothing scrolls).

## SIZES + STYLE
- Parameterized: **S** (~120×40, processor-box header strips) · **M** (preview panes — the macro page's MAIN/ALT
  each carry one, so the A/B is auditioned VISUALLY too) · **L** (manual diagrams · the receivers' house-chord
  preview). House style: rounded rects · ink or the cell's hue at low alpha · divider bright · fire-flash brief.
  Chrome-quiet. **LAW: BRIGHTNESS = VELOCITY** (both sides).

## §2 — THE EYE (header-bar inspect toggle)
- An **EYE icon in the header bar**, a toggle. While ON, tapping a cell opens **the window as a POP-UP** for that
  cell (M, LIVE) — the tap INSPECTS instead of performing (armed-mode grammar, like MUTE-arm). Tapping another cell
  re-points; tap outside / ✕ / eye-off dismisses. SINGLE mode: inspecting never switches rungs. Eye lit while armed;
  the popup carries the cell's hue + its seal/name for orientation.

## USAGE SITES (initial)
Processor boxes (S) · the macro authoring page (M ×2, MAIN|ALT) · library entries (M canned) · the manual (L
canned) · the receivers page beside the house chord (M — input half alone: "the door holds").

## §3 — FLAGGED FUTURES (captured, NOT v1)
- **THE LONG WINDOW**: the popup grows stages — pool → door filtering (range/split) → each chain stage → output
  filtering (chop/dest) → the wire; segmented lanes with multiple dividers, or a stage-picker on one lane.
- **THE RACK VARIANT**: per-emitter windows showing the wire's truth — admitted solid · claimed-away hollow ·
  ducked dimmed (the roles drawn in piano-roll form).

## CODE NOTE (feasibility / seams)
- The derived-future lane needs a **derive-ahead** of the cell's schedule (~2 beats) — a pure function over the
  cell's resolved chain + effective pool at future beats (the Router/Snapshot derivation is already pure per-beat;
  factor a `scheduleAhead(cell, pool, fromBeat, beats)` that returns [(beat, note, vel, durBeats)]). Foundation-only
  + unit-testable. The VIEW (a Canvas/TimelineView piano-roll) renders it; ONE `NoteWindow` view, size-parameterized.
- LIVE needs the visible cell's effective pool + the derive-ahead each frame (cheap for ≤ a few visible windows);
  CANNED feeds a fixed chord. The EYE is an armed-mode toggle in the header + a cell-tap interception (like the
  existing verb/mute-arm grammar).
