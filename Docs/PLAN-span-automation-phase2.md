# PLAN — Span automation PHASE 2 (×N "passes" spans, render-time)

STATUS: APPROVED + PARKED (2026-09-04). Paul took all ★ recommendations (§8), folded in STEP|SMOOTH (§10), and asked
to make CC a FIRST-CLASS automation target (§11). ⏸ HELD until Paul has device time — do NOT start building until he
resumes (the drag feel + the whole AUTO band are device-eye-owed from Phase 1, and he wants to steer Phase 2 on glass).
Follows Phase 1 (step spans, compile-time bake — `Docs/PLAN-span-automation.md`, BUILT `ad9fb75`). ★ = the taken option.

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

## 8. DECISIONS — RESOLVED (Paul 2026-09-04, took all ★)
1. ✅ `spanPasses` field (not the spanLen>partWidth encoding).
2. ✅ Pass index DERIVED from the beat (replay-exact; resets cleanly on stop/seek).
3. ✅ ×N option set = 2/4/8 (as the ladder).
4. ✅ A PASS span honours `spanStart`.
Plus: ✅ STEP|SMOOTH added (§10, default STEP, continuous-only). ✅ CC made first-class (§11).

## 9. Build order (each step compiles + is testable)
1. Model: `spanPasses` + `smooth: Bool` (+ round-trip/migration tests).
2. Box + compose: `ColourAuto`/`ParamField` + the builder routes PASS lanes (and SMOOTH lanes — see §10) to `renderAuto`
   (plain STEP lanes still bake).
3. Router: `SnapParams.settingAuto` + apply the ramp per (pass, col) — or per-NOTE-beat when SMOOTH — at the emit point
   (+ RouterTests: ×2 ramps across 2 passes then repeats; smooth resolves finer than stepped under a dense driver;
   replay-exact; step + no-lane byte-identical).
4. UI: un-grey ×N (mutually exclusive with 1–8); a STEP|SMOOTH toggle (continuous-only, greyed for discrete); the CC
   quick-path (§11); STATE/highlight for pass spans.

## 10. STEP | SMOOTH ramp (Paul 2026-09-04 — DEFAULT STEP, continuous-only, render-time)
The ramp is STEPPED today (one value per column, baked). Add a per-lane STEP | SMOOTH option:
- **STEP (default):** one value per COLUMN (Phase 1 bake). Every note a driver fires within a column shares that value.
- **SMOOTH:** each emitted note is sampled at ITS OWN beat position on the ramp (render-time), so a dense driver
  (arp/ratchet firing several notes per column) gets a finer sweep. Only DISTINGUISHABLE for continuous params + a
  sub-column note rate; for a per-note-onset param at column rate it collapses back to stepped, which is fine.
- **Greyed for DISCRETE params** (option/toggle/stepper) — can't interpolate; only STEP applies. Same gating as SPAN's
  toggle grey-out.
- Implementation: SMOOTH rides the SAME render-time path as pass spans (§5) — evaluate `autoRamp` at the note's beat
  fraction across the span instead of the column rank. So SMOOTH pulls its lane into `renderAuto` even for a STEP-length
  span. No-alloc value-copy field set, derived-from-beat (invariants 2/3).

## 11. CC FRONT AND CENTRE (Paul 2026-09-04 — a first-class target)
CC is the FLAGSHIP smooth-automation target: unlike per-note-onset params, a CC is read continuously, so a SMOOTH ramp
on a CC is a genuine continuous controller sweep across the span — the marquee use case. Make it prominent:
- The AUTO PARAM row should surface the MOD processor's CC controls (MIN/MAX = the CC's swept range, and the CC NUMBER)
  as a clear, early choice — not buried among the note params. A lane automating MOD MIN→MAX with SMOOTH = a CC that
  ramps smoothly over the span (and, with ×N, over N bars). ★ Recommend: when the focused chain has a MOD stage, the
  PARAM row leads with its CC min/max; consider a one-tap "automate CC" affordance that arms a MOD-min/max lane in SMOOTH.
- Engine already emits MOD CC at a 1/16-beat control grid (render-time), so a smooth CC ramp composes with it naturally —
  the AUTO lane sweeps MOD's min/max, MOD emits the CC. No new CC engine; AUTO just drives MOD's range. (Confirm on device
  that the resolution — MOD's 1/16 grid × the AUTO ramp — reads as smooth.)
- OPEN (device): whether "automate CC" is its own prominent lane preset or just PARAM-row prominence for MOD; Paul's eye.
