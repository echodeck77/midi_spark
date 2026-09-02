# PLAN — the part-page PIANO ROLL (true + accurate)

The strip under the part grid must show, as a piano roll, **exactly what the part will play on one pass**.
Today it's a static mock (`roomsPartPianoRoll`). This plan replaces it with the REAL engine output.

## Paul's rules (the contract — REVISED 2026-09-02, LIVE not simulated)
1. **TRUE LIVE output** — driven by the ACTUAL emitted notes as the part plays, **NOT** a simulated/reference chord.
2. **8-view AND 16-view** — the roll spans the part's active width (`buildPartCols`, 8 or 16) at the part's rate.
3. **The selected column's MIDI output, or nothing if no output** — a deselected column / a cell with no emitter
   emits nothing → nothing there (falls out of reading the real live feed).
4. **No input present → the notes are DIMMED** — the roll shows the recently-played notes dim when nothing is currently
   coming out; they **LIGHT** (full, in the EMITTER colour) as the **playhead passes** them / as they're freshly emitted.

## The source — the LIVE emitted-note feed (no offline render)
The engine already records, per cell, the recently-emitted note-ons: `Router.cellNotePitch/Vel` (6/cell) →
`drainCellNotes()` → the VC polls `cellNotePitch/Vel/Count` (`@State`, per cell) → `buildNoteSweep` already DRIFTS
them in the EMITTER colour. The piano roll reads the SAME feed, laid on the pass timeline instead of drifting. So it
is the true live output by construction — it can't diverge from what's sounding. NO reference chord, NO Router re-run.

Per COLUMN `c` (0…buildPartCols−1): the selected rung `buildStagingSel[c]` → the cell index `c*Snap.rows+sel` → that
cell's live emitted pitches (the feed) + its EMITTER (`buildRowEmittersResolved(row)`) + its CELL colour
(`buildRowColour(row)`). A note emitted there is drawn at column `c`'s x, at its pitch lane.

## Increment 1 — the live pass-roll accumulator + draw (replaces the mock)
- A per-pass buffer keyed by (column, pitch): when a column's cell emits a pitch (from the poll feed, stamped with the
  effective beat so it maps to the pass position), record it with a freshness timestamp + its emitter + velocity.
  Persist across the pass; a note re-lights when re-emitted. (Onset-based — the feed is note-ONS; each note fills its
  column's width at its pitch lane, the natural "step" duration. True note-off durations would need the reel/DoorRing
  pairing — a later refinement; onsets are what the live feed gives.)
- Rewrite `roomsPartPianoRoll` to draw it: **x** = the note's column × colW (gridlines aligned to the grid columns —
  rule 2, honoring buildPartCols); **lane (y)** = pitch, auto-fit to the used range; **background** = the source cell's
  COLOUR (faint, per its column); **the note bar** = the EMITTER colour (rule: cell colour behind, emitter colour on the
  note); **brightness** = FRESH (just emitted / playhead crossing) = full, decaying to DIM when nothing's coming out.
- A PLAYHEAD sweeps the roll (reuse `roomsPartPlayhead`'s beat math) — notes light as it passes (they're emitted then).
- No input / nothing emitted → everything dim (or empty). Deselected column / no emitter → nothing (rule 3).
- **Feed check**: the per-cell feed is `Snap.cells`-sized (256) so it already covers 16 columns. Confirm `drainCellNotes`
  is polled while the PART page is visible + playing (it drives the drift sweeps, so it is).

## Increment 2 — polish (optional)
- Stable pitch-range window (avoid lanes jumping as notes change).
- True durations via note-off pairing (a live on/off feed per cell) if onset-fill isn't enough.
- A per-emitter tint legend if a part uses several emitters.

## Decisions (settled, Paul 2026-09-02)
1. **Source** — the LIVE emitted-note feed (`drainCellNotes`), NOT a simulated chord. Reflects real input→output.
2. **No input** — notes shown DIMMED; they LIGHT in the EMITTER colour as the playhead passes / they're emitted.
3. **Colour** — the note bar in the **EMITTER** colour (`emitterHexes[cable]`) over a faint **CELL**-colour background.
4. **Onset vs duration** — v1 draws each emitted note as its column's-width bar (the feed is onsets); true durations later.

## Sequence
Increment 1 (offline renderer + tests) → Increment 2 (wire + draw) → device ear/eye check → Increment 3 polish.
Increment 1 is off-device-testable and is where the accuracy is proven; do it first, with tests.
