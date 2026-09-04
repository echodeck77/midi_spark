# PLAN — SPAN-ONLY part automation (drag-to-draw + default-on-arm)

STATUS: ✅ BUILT (2026-09-04, Paul approved all four ★ recommendations). Phase 1 (step spans, compile-time bake)
landed; Phase 2 (×N passes, render-time) remains deferred + the ×N ladder buttons are greyed. All §7 decisions
resolved to the ★ options: span TILES · DRAG to draw · ×N deferred · 1-D per row. DEVICE-eye owed (the drag feel).

## 1. The decision (what changes)
The AUTO automation model becomes **span-only**: a lane's automation is ONE contiguous SPAN — a run of
steps carrying a FROM→TO ramp — that **tiles** across the part row. This REPLACES the current
"punch an arbitrary set of cells (the extent) + a separate re-anchor number" model. Two consequences:
- **You draw the span by dragging** across the row (press = start, release = end).
- **Arming a lane applies a sensible default span immediately**, so automation is audible at once (the
  root cause of "I picked ARP → LENGTH and heard nothing" was an empty extent — no cells punched).

## 2. Current state (grounded — do not guess, these are the touch points)
- **Model** — `AutoLane` (BuildModel.swift:37): `slot·param·cells: Set<Int>·lo·hi·span: Int?`.
  `PartAutoColour` (BuildModel.swift:51) holds `activeLane` + 5 lanes; `PluginState.partAuto` (Models.swift:1286,
  additive-Optional, keyed by colourID) persists it.
- **Engine** — `BuildSceneLogic.applyAuto` (BuildSceneLogic.swift:135): for a cell in `lane.cells`, ranks it
  in column→row order, `span = (lane.span ?? 0) >= 2 ? lane.span! : ordered.count`, value =
  `autoRamp(lo, hi, rank % span, span)`, writes it via `applyProcessorValues`. `autoRamp` (line 128) is a linear
  `lo + rank/(count−1)·(hi−lo)`. Called in composeScene for the STAGING audition (line 227) AND the deployed
  PERFORM piece (line 208). Byte-identical when no lane armed.
- **UI (punch)** — `roomsPartCell` routes taps through `BuildSceneLogic.partGridTap` → `.punch` →
  `buildAutoToggle` (BuildPage.swift:2435, adds/removes `idx` in `lane.cells`). `buildAutoInExtent` (2439) +
  `buildAutoRampFrac` (2444) drive the amber wash + the "AUTO N" label + the STATE playhead.
- **UI (controls)** — `autoSpanColumn` (the 1–8 / ×2·×4·×8 ladder), `autoSweepEndpoint` (FROM/TO, kind-aware),
  `autoSweepState` (the ramp+playhead preview). `buildAutoSetActive` (2155) arms a lane.

## 3. New model (AutoLane)
Add two additive-Optional fields; `cells` is retained ONLY for old-doc decode + is no longer written:
```
var spanStart: Int? = nil   // the COLUMN the span begins at (nil ⇒ 0)
var spanLen:   Int? = nil   // the span length in COLUMNS (nil ⇒ the part width = one sweep across the whole part)
```
The span is `[spanStart, spanStart+spanLen)` and TILES rightward across the row (period = spanLen).

## 4. Engine change (applyAuto) — small + reuses autoRamp
Replace the extent/rank block with a span-tile fraction:
```
let start = lane.spanStart ?? 0
let len   = max(1, lane.spanLen ?? partWidth)      // partWidth passed into Input (Snap.cols / buildPartCols)
guard col >= start else { return chain }           // before the span → untouched
let rank  = (col - start) % len                    // position within this tile
out[slot] = applyProcessorValues([key: autoRamp(lo, hi, rank: rank, count: len)], to: out[slot])
```
- Applies to EVERY cell of the colour at/after `start` (tiling), not a punched subset.
- `count = len` so `autoRamp` ramps FROM at rank 0 → TO at rank len−1, then repeats.
- Byte-identical when no lane armed (guard unchanged). `composeScene.Input` gains `partWidth`.
- +tests: tile fraction by column (period = len); start offset; len = width ⇒ single sweep; no-lane byte-identity.

## 5. UI change
- **DRAG-to-draw** (★): when a lane is armed, a drag on the interior sets `spanStart` = the press column and
  `spanLen` = |release − press| + 1 (clamped ≥1), filling live. Routed by making `partGridTap` return a new
  `.spanDraw(startCol, endCol)` while a lane is armed (replaces `.punch`); `buildPartGridDrag` tracks the press
  column across the drag. A single tap = a 1-column span at that column.
- **DEFAULT ON ARM** (★): `buildAutoSetActive(i)` — if the newly-armed lane has no span, set
  `spanStart=0, spanLen=partWidth` so it sweeps the whole part immediately (audible on arm).
- **The ladder** (`autoSpanColumn`) becomes a QUICK span-length set: 1–8 sets `spanLen` in steps (tiling from
  `spanStart`); ×2/×4/×8 = passes → see §6 (deferred). Greyed for toggle params as now.
- **Highlight** — the amber wash + "AUTO N" label now mark the SPAN's cells (derived: `col >= start`, the first
  tile brightest / a repeat marker), from `buildAutoInExtent` rewritten to `col ≥ start` (no `cells` lookup).
- **STATE preview** (`autoSweepState`) + its playhead read the span tiling (`buildAutoRampFrac` → column-tile
  fraction) — already the right shape, just re-sourced.

## 6. Phasing (because of a real engine limit)
The automation is BAKED at compose time (applyAuto sets each cell's param — invariant 1). A compile-time bake can
only vary a value by COLUMN within ONE loop. So:
- **Phase 1 (this plan): STEP spans** — `spanLen` in 1…partWidth, tiling within the loop. Fully bakeable.
- **Phase 2 (deferred, flagged): PASS spans (×2/×4/×8)** — a span LONGER than the loop must progress across
  successive loops, which the baked one-loop scene cannot express; it needs RENDER-TIME modulation (the engine
  knowing the current pass). Until then the ×N ladder buttons are GREYED. (Note: today's ×N doesn't truly
  multi-pass either — `rank % 16` on a short extent is a no-op — so this loses nothing.)

## 7. OPEN DECISIONS (need Paul)
1. **Tile vs single sweep.** ★ Recommend: the span TILES (repeats) across the row; setting `spanLen` = the full
   width gives a single ramp (the non-repeating case falls out for free). Alternative: one span, no repeat.
2. **Draw gesture.** ★ Recommend: DRAG (press-start → release-end, fills live). Alternative: two taps
   (start, then end) with a "tap the END" prompt — workable but has order/mode ambiguity + fiddly re-edit.
3. **×N passes now or later.** ★ Recommend: LATER (Phase 2, render-time). Grey the ×N buttons for now.
4. **1-D per-row vs 2-D.** ★ Recommend: 1-D along the colour's row (matches a sweep). Alternative: a 2-D block.

## 8. Migration / persistence / risk
- `spanStart`/`spanLen` are additive-Optional → old docs decode fine (span defaults: start 0, len = width).
  Optional: on load, derive a span from a legacy `cells` range (min→max column) so old automations survive; else
  ignore `cells` (simplest). ★ Recommend: derive (lossless-ish) — one small migration in the loader.
- The punch path (`buildAutoToggle` add/remove, arbitrary `cells`) is REPLACED by the span-draw. `buildAutoInExtent`
  /`buildAutoRampFrac` are rewritten to span math. No render-thread change (still a compile-time bake).
- Byte-identical for any doc with no lane armed; the AUTO Router/BuildSceneLogic tests are updated for the span model.

## 9. Build order (each step compiles + is testable)
1. Model: add `spanStart`/`spanLen` (+ round-trip test).
2. Engine: rewrite `applyAuto` to span-tile; thread `partWidth` into `Input` (+ tests). ← inert until the UI writes spans.
3. UI: default-on-arm + the ladder writes `spanLen`; highlight/STATE re-sourced from the span.
4. UI: the drag-to-draw gesture (`partGridTap` `.spanDraw`), replacing `.punch`.
5. Grey ×N (Phase 2 marker); migrate legacy `cells` on load.
