# DESIGN — cell appearance across the three grids (Paul, 2026-09-05, RATIFIED)

Goal: make SELECT · PART · PLAY **instantly distinguishable**, and give every cell a
**stylised face derived from its expected output**. Mockup:
`claude.ai/code/artifact/2b727eeb-6e40-42d4-b1a0-9142ce9d9ba7`.

## The one idea
Every cell paints the **same thing** — its output, as a **CONSTELLATION**: a dot per
note (dot size = velocity), positioned by pitch (y) and time (x), joined by a faint
path. What differs between grids is only **colour** and **motion**.

## The CONSTELLATION face (ratified — replaces the piano-roll bars)
- A dot per note; size ∝ velocity; y = pitch lane; x = onset in the cell's window.
- A faint connecting path in onset order (the "sigil" line). Reads at cell size where
  a piano roll turns to mush.
- Derived from the offline **expected output** (`gridSelRollBars`) on SELECT; from the
  **live strike feed** (`buildCellRoll` / `buildNoteSweep`) on PART + PLAY.

## Per-grid treatment
**SELECT — the blueprint (MONOCHROME).**
- Cell = dark grey stage; constellation in **light grey** ink. No hue.
- **Selected = the INVERSE** (light stage, dark constellation + ring). Inverse is
  **Select-only**.
- Static picture of the expected output; may scroll/pulse on audition.

**PART & part ferries — the assignment (DARK COLOUR + BRIGHT NOTES).**
- Cell = the row's **FIXED colour** (fixed by ROW POSITION, not machine identity),
  drawn **DARK + FLAT** — a solid, no wash/breathe/fade.
- Constellation = the **bright emitter colour**, drifting **LIVE** (kept). Light marks
  on a dark ground — this is the emitter/part separation: **by lightness, not hue**
  (the hues overlap, so light-on-dark is what always reads).
- The ONLY exception to "flat": an **AUTO** lane (amber extent + "AUTO n" + FROM→TO ramp).
- Selected rung = the white ring (NOT inverse).

**PLAY — the performance (BLENDED, unchanged look).**
- Keep today's dusk per-column palette, opacity washes, per-cell playheads, the
  **glow** while playing. Notes drift **live** in emitter colour — now as a
  constellation.
- The one grid allowed blends + motion (it's the surface that's sounding).

## The differentiation (the glance test)
| | Cell (ground) | Notes (marks) | Motion |
|---|---|---|---|
| SELECT | dark **grey** | light grey | static (scroll on audition) · **inverse when selected** |
| PART | dark **fixed row colour**, flat | **bright emitter**, live | live drift |
| PLAY | mid **dusk** + wash + glow | bright emitter, live | live drift |

Colour axis: none → flat-dark → blended. Notes: grey → bright → bright+glow.

## Ratified decisions (Paul)
1. Face = **constellation**.
2. Emitter notes = **the current emitter colours** (bright warm A/B/C/D) — NOT
   lightened globally; the dark part cell makes them pop.
3. Velocity **kept** as dot size / brightness (it's data, not a fade).
4. Part row colour is **fixed by row position** ("row 7 always yellow" was the example);
   any distinct, good-looking 8-colour set is fine — code-side choice.
5. **Inverse selection is SELECT-only**; PART keeps the white ring.
6. Part keeps **live drift** (not a static expected-output face).
7. "No fades/hues" on SELECT + PART **except** the AUTO ramp.

## Build notes
- New reusable constellation renderer (Canvas) taking (pitch, time, velocity) points +
  a tint + a mode (mono/emitter). Replaces the bar rendering in `buildNoteSweep`
  (PART/PLAY live) and `buildGridSelPianoRoll` (SELECT offline).
- A fixed 8-colour row palette (new token); PART cell = that colour mixed dark + flat.
- PLAY keeps its wash/glow/playhead composition — only the note FORM changes to dots.
- Device eye owed throughout (dot size, path opacity, drift feel are tunable).
