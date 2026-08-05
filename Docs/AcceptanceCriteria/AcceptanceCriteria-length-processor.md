# AcceptanceCriteria — LENGTH (working name): the per-slice GATE-OVERRIDE processor (captured 2026-08-05)

**STATUS: CAPTURED, NOT BUILT.** From `SPEC-length-processor`. The articulation family's DURATION axis (CHOP routes ·
GROOVE touches · LENGTH decides how long notes live). Kin widget: the shipped CHOP 8×3 grid, reused wholesale.

## CONTROLS
- **8×3 paint grid** — 8 slices of the cell's window × 3 rows: **SHORT · LONG · MUTE** (radio per column; tap sets,
  re-tap clears). **UNLIT = PASS** (default 4th state — the incoming gate untouched; the stage speaks only where
  painted, per the deviation law).
- **Slider SHORT** — the short gate: 5–95% of the slice.
- **Slider LONG** — the sustain: 25% … **COLUMN END** (may run past the slice boundary — notes ring across
  subsequent slices; capped at the column envelope, so no tail-class dependency; "to end" = the sustained pedal).
- Two lengths + mute + pass = Paul's "two or three defined lengths applied via the box."

## BEHAVIOUR
- Each note ADMITTED in slice s gets its gate REPLACED by that slice's state (SHORT/LONG value · MUTE = dropped ·
  PASS = original gate). Works after any driver; on hold-class chains it carves a drone into long/short phrasing
  (the trance-gate's musical cousin — CHOP switches on/off, LENGTH shapes breath).
- Window-relative like CHOP; PHASE laws unchanged (LEGATO carries the pattern across identical cells = 16-slice).
- Gate-affecting stages compose **LAST-WRITER downstream** (a later GROOVE-slide or LENGTH wins per note) — chain
  order is the law.
- **LENGTH-ROTATE** joins the rotate family (a TAP action: the phrasing walks).

## FAMILY NOTES (honest)
- MUTE here overlaps CHOP's mute row — kept for one-stage convenience; the manual says so in one line.
- GROOVE (pending) keeps ACCENT·SLIDE·OCT±·REST; LENGTH owns duration. Separable, both slice-grammar, both stack.
- Naming candidates: LENGTH (working) · TOUCH · PHRASE · SUSTAIN (GATE collides with the param + PASSGATE).
