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

## v1 FAILED (2026-09-02) — why it's not a piano roll
The first build reused the wrong feed (`buildCellRoll`), which carries only a wall-clock `born` timestamp + a
compressed 0–1 pitch lane + velocity. Consequences: (a) notes pin to the COLUMN's x, so a chord/arp stacks at one x
(no time spread); (b) onset-only — no note lengths, so no bars; (c) the pitch axis is a squashed lane, not real
semitones. It's a column-activity meter, not a piano roll. The feed fundamentally can't place notes at real beat
positions with real durations, so it cannot be polished into a roll — it needs the right DATA.

## What a PREMIUM piano roll needs — data + craft
**DATA (real note geometry):** each note as `{ startBeat, endBeat, pitch, emitter, cellColour }`. The engine already
proves this shape works — the REEL captures exactly it (`ReelDeck.Note`, via a `ReelTap: MIDIEmitter` that records
every emitted event with a pass-relative beat + `markColour` per note). BUT the reel is gated on the host transport
`playing`, uses a fixed global 8-bar cycle, and doesn't advance/reset during the BUILD free-run audition — so it's the
wrong SOURCE for the part page. The fix is a DEDICATED capture mirroring that proven pattern, cycling on the PART clock.

**CRAFT (what makes it feel premium):**
- A real pitch axis — one lane per SEMITONE across the used range (stable window), a thin PIANO-KEYBOARD gutter on the
  left (white/black keys), octave (C) gridlines labelled, faint black-key row shading.
- Real BARS — each note a rounded bar from startBeat→endBeat at its exact semitone row; EMITTER colour with a subtle
  vertical gradient / soft inner glow; velocity → brightness + a touch of height; a faint drop for depth.
- Per-column CELL-colour backdrop (faint), so the roll still reads which colour owns each column.
- Motion — a smooth playhead; a note BLOOMS as the playhead crosses it (freshly emitted), settling to a resting
  brightness, DIM when no input. 60fps, no flicker (the pitch window doesn't jump as notes come and go).
- Tight, aligned layout — beat/column gridlines line up with the part grid above; a premium dark ground; generous
  but disciplined spacing.

## The source — a DEDICATED live per-part-cycle capture (mirrors the proven ReelTap/ReelDeck)
The engine already records, per cell, the recently-emitted note-ons: `Router.cellNotePitch/Vel` (6/cell) →
`drainCellNotes()` → the VC polls `cellNotePitch/Vel/Count` (`@State`, per cell) → `buildNoteSweep` already DRIFTS
them in the EMITTER colour. The piano roll reads the SAME feed, laid on the pass timeline instead of drifting. So it
is the true live output by construction — it can't diverge from what's sounding. NO reference chord, NO Router re-run.

Per COLUMN `c` (0…buildPartCols−1): the selected rung `buildStagingSel[c]` → the cell index `c*Snap.rows+sel` → that
cell's live emitted pitches (the feed) + its EMITTER (`buildRowEmittersResolved(row)`) + its CELL colour
(`buildRowColour(row)`). A note emitted there is drawn at column `c`'s x, at its pitch lane.

## v1 (BUILT then SUPERSEDED) — the column-activity version
`roomsPartPianoRoll` drew `buildCellRoll` per column (onset marks). Kept building; being REPLACED by the real roll below.

## The premium build (the real roll)
### Increment 1 — the engine capture (Foundation, testable)
- `PartRollDeck` (Emission.swift) — a compact recorder mirroring `ReelDeck`: `record(beat,cable,colour,b0,b1,b2)` into a
  `cur` ring (beat = PART-cycle-relative), `startCycle()` resets it at each part-cycle boundary, `liveRoll(cycleBeats:)`
  pairs on/off (closing still-open notes at `cycleBeats`) → `[Note{cable,note,vel,start,end,colour}]`. +tests (pairing,
  hold-to-end, cycle reset).
- `PartTap: MIDIEmitter` (mirrors `ReelTap`) — wraps the live emitter, records into `PartRollDeck` with pass-relative
  beat, forwards. `markColour` per note (the cell colour), exactly as the reel tap.
- Kernel: while the BUILD PART audition renders, feed the PartTap the PART's cycle (`buildPartCols × partRate`, honoring
  8/16), `startCycle()` at the part-cycle boundary. NOT gated on host `playing` (works under free-run). Off when not on
  the part page (a control-thread flag) so it costs nothing elsewhere.
- AU/VC: `pollPartRoll() -> [Note]` (read-only value copy, benign staleness like the other polls) → `@State`.
### Increment 2 — the DAW-grade renderer (replaces the mock)
- Rewrite `roomsPartPianoRoll` per the CRAFT list above: keyboard gutter, semitone lanes, octave grid, real rounded bars
  (start→end × pitch row), emitter colour + cell backdrop, velocity, a blooming playhead, stable pitch window, 60fps.
### Increment 3 — polish
- Sub-tuning of the bloom/decay, the pitch-window hysteresis, the gradient/shadow, optional note-name gutter labels.

### Original increment-1 sketch
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
