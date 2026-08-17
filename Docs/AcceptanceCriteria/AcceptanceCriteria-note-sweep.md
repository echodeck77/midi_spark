# AcceptanceCriteria — THE NOTE SWEEP (cell animation; ferry-captured 2026-08-17)

**STATUS: NOT BUILT.** Ratified by Paul 2026-08-16 (design-side ferry `SPEC-note-sweep.md`). Build **AXIS = ROTATION
(A)** first; CONTOUR (B) stays one flag away for the glass session.

## The mechanism (Paul's design)
- **One sweep per sounding note**, drawn across the (square) cell face; **travel time = the note's sounding life** —
  a note-off mid-travel kills the line where it was (choke visible; drones creep; LEGATO/GATE differences render).
  Four axes.
- **AXIS ASSIGNMENT (two candidates; Paul's glass picks — build A first):**
  - **A. ROTATION** (his original): each new note takes the next axis (L→R, T→B, R→L, B→T…) — simple, order-encoding;
    simultaneous notes never occlude.
  - **B. CONTOUR**: vertical = PITCH DIRECTION (rising interval sweeps ↑, falling ↓); repeated pitches alternate the
    horizontals — the cell draws its melody's shape. Less separation, more meaning. (Behind a flag.)
- **VELOCITY IS THE STROKE, literally**: sweep weight + opacity = the note's velocity (whisper-thin pp, bold accents).
- **THE DENSITY GOVERNOR (chrome-quiet)**: sweep thickness scales down with event rate; past a threshold (RTC bursts,
  dense ratchets) per-note sweeps collapse to a low BOIL — the cell simmers, never strobes. Readability floor,
  tempo-independent.
- **Colour**: the sweep in the cell hue's BRIGHT tone over the face dimmed one step while sounding — the cell speaks
  louder in its own colour, then rests.

## Plumbing
The per-note peak feed (planned — "one plumbing job, three customers") gains its FOURTH customer: the sweep needs
`{on, off, velocity, pitch-delta}` per cell — same feed, no new taps. GPU cost: lines; trivial at 64 cells.

Manual line: "Every note draws its stroke — weight is how hard, travel is how long, direction is where the line is going."

— design-side Claude (ratified Paul 2026-08-16)
