# PLAN — GRID VISUAL REBUILD (clean-slate)

Ratified direction (Paul 2026-09-08): **piano-roll ribbon cells · beat-sweep playing ferries · lift-and-bloom selected
ferry · the ferry-shade palette**, meeting `AcceptanceCriteria-grid-presentation.md`. Reference mock:
`claude.ai/code/artifact/c8369ad5…` (combined). This plan rebuilds the grid's VISUAL layer from scratch and deletes the
inherited face/animation code rather than reusing it.

## Is a brutal strip sensible? Yes — with a SCOPE boundary.
The cell/ferry visual layer only READS engine feeds; it never produces audio or state. So a from-scratch renderer is
low-risk (a mistake is cosmetic, caught by the eye/build, never a stuck note). But "brutal" must be SCOPED:
- **STRIP (the accreted visual layer):** the cell-face drawers + their strobes/animations. Build fresh, do not reuse.
- **KEEP (data, untouched):** the engine feeds the new look consumes — they are correct and hard-won.
- **DON'T TOUCH (out of scope):** the surrounding chrome you haven't asked to redesign — the receiver/emitter strips,
  the machine box internals, the config sheets, the header/transport, the reel. The rebuild is the GRID + FERRY row +
  the cell face + the palette. (If you want the chrome restyled too, that's a separate pass.)

## STRIP list (delete, replace with the new renderer — grep-verified before removal)
- `buildOutputFace` (BuildPage:4608) — the constellation/blueprint face.
- `drawConstellation` (:4585) — the dot/sigil Canvas.
- `buildNoteSweep` ×2 (:4562/:4631) — the drifting-notes face (only live caller is the dead `roomsPlayGrid`).
- `buildGridSelPianoRoll` (:6022) + `buildGridSelDriftFace` (:6028) — SELECT/row-selector faces.
- `buildGridSelStampSweep` (:6092) — the rising-fill/commit "reveal" sweep (a one-shot animation; replace with a quiet static confirm or drop).
- `stagingPulseFraction` (GridUI:1932) — the breathe generator; after the strip its callers are gone.
- The `sweep:` closure param on `roomsGridCellBody` (:2713) — folded into the new cell renderer.
- Retire the grid COLOUR helpers that the new palette replaces: `partPosHex/partPosHue/partPosFill/partPosFrame`,
  `partCellFill/partCellFrame` (already 0-ref per the dead-code survey), `partRowHexes`/`playHexes` usage on the grid.

## KEEP (read-only feeds the new renderer consumes — do NOT change)
- **Sound/notes:** `cellSoundVel` / `cellSoundingVelSnapshot` (256-wide sounding velocity), the strike feed
  (`drainCellStrikes` → `cellHitVel`/`cellHitAt`), and `buildCellRoll` (per-cell emitted-note roll).
- **Static note geometry (the ribbons draw this):** `gridSelRollBars` (offline render → note bars) + the roll caches
  `buildComputePlayColRolls` / `buildGridSelComputeRowRolls` / `buildGridSelComputeCellRolls`. KEEP the DATA; only the
  DRAWING is replaced. (A piano-roll ribbon IS these bars, drawn fresh.)
- **State:** `buildFerryParts` / `buildActiveFerry` (ferry parts + selection), `buildPlayColOn` (playing), `buildStagingSel`
  (active rung per column), the ferry-shade palette (new, from P1).
- **Beat (for the sweep):** `meters.beatAnchor` / `beatAnchorAt` / `tempo` (the standard extrapolation).
- **Playheads:** `roomsPartPlayhead` (the part-grid sweep line) + `roomsCellPlayhead` — KEEP or re-home into the new
  renderer; they're the sequencer playhead, not old ornament. Decide in P3.

## THE NEW VISUAL SYSTEM (the contract)
A single fresh module — `GridSkin` (new file `AUExtension/GridSkin.swift`, added via xcodegen) — owns all grid drawing,
so the old stylings can't leak in. Pure-ish SwiftUI/Canvas reading the feeds above.
- **Palette (P1):** `ferryHexes: [UInt32]` (8 bases) + `func ferryShade(_ base, row) -> Color` (4 differentiable shades;
  steps TBD from the swatch). Bases obvious + referenceable; the SAME base tints the ferry, its part rows (shades), and
  the machine-box echo.
- **Cell (part + select):** a flat shaded tile carrying identity (ferry-shade) + STATE — active rung = crisp white
  keyline; populated-unselected = recessed shade; empty = faint inset; rest column = no fill. Its FACE is the piano-roll
  ribbon (note bars from `gridSelRollBars`), STATIC (no drift/blink). Density thinned to stay calm at cell size.
- **Ferry:** a colour block in its part's base hue with a mini piano-roll ribbon. Four states, all readable at once:
  SELECTED = **lift & bloom** (raised + full-colour + drop-shadow + machine-box header echo); PLAYING = **beat sweep**
  (a bright line swept in time, `meters` beat); POPULATED-idle = flat recessed colour; UNPOPULATED = dashed recess + "+".
  SELECTED+PLAYING shows both (lift + sweep — proven in the mock).
- **Motion law:** animation ONLY on the ferry row (beat sweep). Every non-ferry cell is static. No strobing anywhere.

## PHASES (each iOS-buildable + device-verifiable; commit per phase)
1. **P1 — Palette.** New `ferryHexes` + `ferryShade`. Wire ferry/row colour assignment to it (seed + add-a-row use
   `ferryShade(base, rowIndex)`; the ferry shows its base). Retire the old grid colour helpers. Device: colours read as
   one family per ferry, 8 distinct, 4 shades legible.
2. **P2 — New cell renderer** in `GridSkin`: the shaded tile + active-rung/state + static ribbon face. Swap it into
   `roomsPartGrid` + the SELECT cell + row/side selectors. Old face drawers still present (unused) — deleted in P4.
3. **P3 — New ferry renderer** in `GridSkin`: colour block + ribbon + the four states + beat sweep + lift & bloom +
   machine-box colour echo. Replace `roomsPlayFerry`'s visuals. Decide the playhead re-home here.
4. **P4 — Delete the STRIP list.** Grep-verify each is 0-ref, remove, build. (Data feeds in KEEP stay.)
5. **P5 — Device pass + retune** against the acceptance checks (active rungs · 4 ferry states · sound link · sophisticated);
   tune shade-steps, sweep contrast on the lifted ferry, ribbon density.

## RISKS / WATCH-POINTS
- **SwiftUI perf:** the beat sweep is the only animation — one TimelineView per playing ferry (≤8), beat-extrapolated
  (the house pattern). The cells are static → no per-cell TimelineViews (a big calm/perf win vs today). Keep it that way.
- **Render-thread invariants:** the new renderer only READS the published feeds on the main thread — no engine change,
  so no stuck-note/allocation risk. Do not move any drawing onto the render path.
- **Ribbon data at cell size:** `gridSelRollBars` may overshoot a tiny cell; thin/clamp in `GridSkin`, not in the feed.
- **Two instances:** only this instance is active (Paul 2026-09-08) — but BuildPage is large + shared; commit per phase.

## DECISIONS (Paul 2026-09-08 — RATIFIED)
- **Shade-steps:** DARKEN — the base at row 0, progressively darker down the rows (no lightening). `ferryShade` steps
  ≈ 0% · 20% · 38% · 55% toward black (row 0…3); the base stays vivid at the top.
- **Selection marker:** lift & bloom PLUS a faint **cyan** accent (belt-and-braces) — keep the cyan.
- **Machine-box echo:** the **header bar** only (not a full frame).
- **Ribbon density:** agreed — a calm default, retuned on device.
- **Playhead:** NONE — remove the part-grid sweep line + per-cell playhead; the ferry BEAT SWEEP is the only motion.
