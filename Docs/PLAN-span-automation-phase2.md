# PLAN — Span automation PHASE 2 (×N "passes" spans, render-time)

STATUS: PLAN, awaiting Paul's approval + his ruling on §8. Nothing built. Follows Phase 1 (step spans, compile-time
bake — `Docs/PLAN-span-automation.md`, BUILT `ad9fb75`). ★ = author's recommendation.

## 1. Goal
Un-grey the SPAN ladder's **×2 / ×4 / ×8** ("passes"): a FROM→TO ramp whose period spans N part-LOOPS (bars). The
notes still loop every bar; the AUTOMATED PARAM progresses across N bars, then repeats. (Step spans 1–8 are Phase 1.)

## 2. Why Phase 1 cannot do it (the constraint that forces render-time)
`applyAuto` BAKES the ramped param per-cell into the composed one-loop `SceneState` (`SnapCell.procs` = resolved
`SnapParams`; SnapshotBuilder.swift:78). A baked scene is ONE loop → it replays IDENTICALLY every bar. A span longer
than the loop needs the param to DIFFER per bar → it cannot be baked; it must be read at RENDER time from the current
pass. (Baking an N-bar virtual loop is out: N×partWidth > `Snap.maxCols` 16 for ×4/×8, and any ×N on a 16-wide part.)

## 3. Facts (grounded — the render-path reality)
- The box carries RESOLVED `SnapParams`, not the doc `ProcessorSlot` — so a render override must set a `SnapParams`
  FIELD (no re-`resolve()` on the render path; resolve allocates → invariant 3).
- Render-time param overrides ALREADY exist as the precedent: `velOverride` / `chanOverride` (Int16) / `nudgeSamples`
  (Router.swift:84/305/306) — instance vars applied per-emit; plus the AU param-override table (invariant 6).
- `diag.pass` (the pass counter) + `effColumn` + `currentColourIndex` are tracked in `process()`. The pass is best
  DERIVED from the beat (`floor(effBeat / (partWidth·stepBeats))`) so it's replay-exact (invariant 2), not accumulated.
- `applyProcessorValues` (MacroAuthoring.swift:301) sets a `ProcessorSlot` param by key — COMPILE-time only. There is
  NO `SnapParams` key→field setter yet; Phase 2 needs one (bounded to the automatable params).

## 4. Model (AutoLane)
- Add `spanPasses: Int?` (2/4/8) — a PASS span, mutually exclusive with the step-span `spanLen`. ★ Recommend this over
  encoding "spanLen > partWidth" (partWidth-independent, unambiguous, survives an 8↔16 width change).
- A lane is: STEP (spanLen, Phase 1, baked) · PASS (spanPasses, Phase 2, render-time) · default (neither → whole-part
  single sweep, baked). Additive-Optional; migration unaffected.

## 5. Engine
- **Compose (BuildSceneLogic):** if the active lane is a STEP/default span → bake as today (Phase 1). If a PASS span →
  do NOT bake; instead emit a compact RENDER-AUTO descriptor into the box for that colour.
- **SnapshotBox:** add `renderAuto: [ColourAuto?]` sized to the colours (nil = none). `ColourAuto = { slot, field:
  ParamField, lo, hi, spanStart, spanColumns = passes·partWidth }`. `ParamField` is an enum resolved from the param
  KEY at compose (so the render never parses strings). Empty ⇒ byte-identical.
- **Router:** when a cell whose colour has a `renderAuto` descriptor is emitted, compute
  `rank = ((pass·partWidth + effColumn) − start) mod spanColumns`, `value = autoRamp(lo, hi, rank, spanColumns)`, and
  OVERRIDE that one field on a LOCAL value-copy of the cell's `SnapParams` before the tick/hold emit reads it. Apply
  once at the cell's processing entry (where `currentColourIndex` is set). Pure `SnapParams.settingAuto(_ field:
  ParamField, _ value: Double) -> SnapParams` — a value-copy switch over the automatable fields, NO heap (invariant 3).
- One-clock/replay-safe: value is a pure function of (pass, effColumn) from the beat (invariant 2). Byte-identical
  when `renderAuto` is empty. Invariant 1 holds (the lane is read from the box).

## 6. UI
- Un-grey the ×2/×4/×8 ladder row; tapping ×N sets `spanPasses` (and clears `spanLen`); 1–8 sets `spanLen` (clears
  `spanPasses`). Mutually exclusive; the lit chip reflects whichever is set.
- STATE preview: for a PASS span, draw the ramp with a "×N bars" tag; the playhead uses the derived pass so it crawls
  across the N-bar period. Highlight: a pass span automates the whole row (all the colour's cells), like a full step span.

## 7. Risks
- FIRST render-time override of a PROCESSOR PARAM (velOverride/chan/nudge are the precedent, but for vel/channel/timing).
  Kept safe by: value-copy field setter (no alloc), derived value (no accumulated state), lane-in-box (invariant 1).
- The `ParamField` setter must cover exactly the AUTO PARAM row's automatable keys (continuous + stepper) — a bounded,
  tested switch; an unknown field is a no-op (byte-identical).
- Only PASS spans take the render path; STEP/default spans stay baked (zero change to the proven Phase 1).

## 8. OPEN DECISIONS (Paul)
1. `spanPasses` field vs `spanLen > partWidth` encoding. ★ `spanPasses`.
2. Pass index DERIVED from the beat (resets cleanly on transport stop/seek, replay-exact) ★ vs an accumulated counter.
3. ×N option set = 2/4/8 (as the greyed ladder today) — confirm, or add ×16 / a free number.
4. Does a PASS span still honour `spanStart` (start column within bar 1) or always start at column 0? ★ honour it.

## 9. Build order (each step compiles + is testable)
1. Model: `spanPasses` (+ round-trip/migration tests).
2. Box + compose: `ColourAuto`/`ParamField` + the builder routes PASS lanes to `renderAuto` (step lanes still bake).
3. Router: `SnapParams.settingAuto` + apply the ramp per (pass, col) at the emit point (+ RouterTests: ×2 ramps across
   2 passes then repeats; replay-exact; step + no-lane byte-identical).
4. UI: un-grey ×N (mutually exclusive with 1–8); STATE/highlight for pass spans.
