# Acceptance Criteria — GRID PRESENTATION

Status: **REQUIREMENTS RATIFIED (Paul 2026-09-08).** The visual direction (from the six-option gallery) is chosen
separately; whichever direction is built MUST satisfy every requirement below. Device-verified (the whole thing is UI).

## The three requirements
1. **The active rungs must be clear.** On the part grid, each column has one SELECTED rung (`stagingSel[c]`) — the cell
   that actually sounds on that column's step. At a glance the user must be able to read the sequence: which cell is the
   active rung in each column, told apart unmistakably from (a) populated-but-unselected cells, (b) empty cells, and
   (c) columns with no selection (a rest). The active rung reads as "this one plays here."
2. **The play-ferry states must be clear.** Each of the 8 ferries is in exactly one of four visual states, and all four
   must be unambiguous side by side:
   - **SELECTED** — the ferry whose part is loaded on the bench (`buildActiveFerry == t`).
   - **PLAYING** — the ferry's part is sounding (`buildPlayColOn[t]`).
   - **POPULATED (idle)** — holds a part, not selected, not playing.
   - **UNPOPULATED** — an empty ferry (`buildFerryParts[t] == nil`) — reads clearly as "empty / tap to browse".
   SELECTED and PLAYING can co-occur (a ferry can be both) — the design must show BOTH at once, not collapse them.
3. **It must look sophisticated.** Restrained, considered, premium — not busy, not toy-like. Motion (if any) stays on the
   play ferries only (per the calm-cells ruling); the non-ferry cells are static. Legibility is not traded for polish —
   the clarity in (1) and (2) must survive the aesthetic.

## Model terms (so the design targets real state)
- **Active rung** — for column `c`, the cell at `(c, stagingSel[c])`; `stagingSel[c] == -1` = no active rung (a rest column).
- **Ferry state** — SELECTED = `buildActiveFerry == t` · PLAYING = `buildPlayColOn[t]` · UNPOPULATED = `buildFerryParts[t] == nil`
  · POPULATED-idle = the remainder.
- **Palette** — the ferry-shade scheme (8 base hues, 4 shades per part row) is the identity carrier; the state cues below
  ride ON TOP of it and must stay legible against every shade.

## Acceptance checks (device-verifiable, "at a glance")
- **Rungs:** looking at a part, the user can trace the active rung across all 8 (or 16) columns without hunting; an
  unselected populated cell is visibly NOT the active one; an empty column reads as a rest.
- **Ferry SELECTED:** exactly one ferry reads as "this is the one on the bench" (currently the cyan ring — Paul 2026-09-08).
- **Ferry PLAYING:** every sounding ferry reads as playing, distinct from selected; a selected-and-playing ferry shows both.
- **Ferry UNPOPULATED:** an empty ferry is obviously empty (not a dim populated one) and invites a tap.
- **Sophistication:** no strobing; non-ferry cells static; the whole reads considered — a pass on device confirms "feels
  premium," not busy.

## Notes
- These are REQUIREMENTS, not a mechanism — the chosen presentation direction (Solid shades · Constellation · Piano-roll ·
  Glass pads · Neon flow · Signal bars, or a pairing) is built to meet them, then device-verified against the checks above.
- Behaviour is unchanged; this governs how the existing state is DRAWN.
