# Fourfold — main-thread performance audit (2026-11-20)

Audit of UI/main-thread inefficiencies, with an eye on **weaker / older iPads** (A9–A12 class) and
accessibility users. The **audio render thread is out of scope and already clean** — the alloc audit
is 0 and the golden harness is byte-identical. Everything below is **main-thread** cost: SwiftUI body
re-evaluation and `Canvas` redraw.

Nothing here is implemented yet — this is for review. Each item has a `file:line`, a risk level, and a
suggested fix. Fixes are **device-owed to verify** (the CPU win can't be measured off-device; the UI
has no macOS test reach), so they should land as small, separate, individually-reviewable slices.

Already shipped (context): the plugin UI now freezes all animations when the view is off-screen
(`e3f22d3`, `fourfoldViewAppeared`) — that fixes the "non-frontmost 93% CPU" watchdog report. The
items below are the *steady-state, visible-and-playing* cost.

---

## Two root causes

1. **No frame-rate relief valve.** Neither **PULSE = OFF** nor **Reduce Motion** lowers the redraw
   rate. ~27 `TimelineView(.animation)` run at 60 fps while playing; 3 are *unbounded* (up to 120 fps on
   ProMotion). A weak-iPad / motion-sensitive user has no way to shed that load.
2. **The whole page body re-evaluates at hit rate.** `EuclideousPage.body` is a ~7,000-line view whose
   ~60 inputs are plain `let`s. ~10 hit-rate `@Published` fields are among them, so every hit/step while
   playing re-runs the entire body — and each eval does avoidable per-frame allocation.

---

## Priority 1 — frame-rate relief valve (LOW risk, HIGH leverage, weak-device-specific)

- **Reduce Motion changes only *visuals*, never the frame rate.** Only `ReelHeaderIcon.swift:17`
  actually pauses on `reduceMotion`; everywhere else (`LaneStripPainter`, `MixPadPainter.swift:296`,
  `RiffArrowPainter.swift:99`, `RestartTilePainter.swift:77`, …) it only changes *what* is drawn — the
  Canvas still re-rasterises at 60/30 fps. A Reduce-Motion user on a weak iPad pays the full cost.
- **PULSE = OFF pauses nothing.** `pulseLevel == 0` zeroes the *draw math* only; no `paused:` flag reads
  it. Every pulse-gated TimelineView still runs 60×/s drawing the resting state. Example:
  `mixPulseOverlay` (`EuclideousPage.swift:8997`) allocates `pads = []` each frame to draw nothing.
- **3 TimelineViews have no `minimumInterval`** → display-max: header status (`EuclideousPage.swift:2219`),
  `CCPanelViews.swift:349`, `RandomModePainter.swift:304` (the last also has no `paused:`).

**Fix:** feed `reduceMotion` (and, if wanted, a new "Low power" preference next to PULSE) into the
TimelineView `minimumInterval` so these users get a 15–30 fps cap; add explicit intervals to the 3
unbounded ones; OR `pulseLevel == 0` into the `paused:` of pulse-*only* overlays (not the ones that also
carry playhead motion). `pulseLive` is at `EuclideousPage.swift:8385`.

## Priority 2 — full-page re-eval at hit rate (MEDIUM risk, HIGH value, helps ALL devices)

~10 `@Published` on `FourfoldModel`, written by the 30 Hz `fastPoll`, are consumed by `EuclideousPage`
as plain `let` inputs, so each change re-runs the whole body several times/sec while playing — though
each feeds only one leaf:

- `euclideousRiffPositions` `FourfoldRootView.swift:1007`, `euclideousRiffWalkState` `:1009`,
  `euclideousMaskPositions` `:1011`, `euclideousRiffLivePool` `:1013`, `euclideousSourceStatus` `:1020`,
  `euclideousLanePools` `:1025`, `euclideousAnswerPhases` `:1027`, `euclideousLanesSeqStep`/`RiffsSeqStep`
  `:1031`/`:1033`, `euclideousWipeEvent` `:1056`, `euclideousStrikeEvent` `:1057` (decls `:1221-1231`).

**Fix:** move this live-position/strike cluster into a dedicated `ObservableObject` observed only by the
comet/arrow/NOTES-key leaf views — the exact pattern `meters` (`HocketLive`/`AnswerLive`/`PulseFeed`)
already uses successfully, so telemetry mutations don't touch `EuclideousPage.body`. **Highest-value
structural change** — shrinks the invalidation unit from the whole page to a few leaves.

## Priority 3 — per-frame heap churn in the always-on TimelineViews (MEDIUM risk)

While playing, these run every frame regardless of PULSE level:

- **Lane strips ×4** (`EuclidLaneUI.swift:461`, Canvas at `:480`): per frame each lane allocates a
  `[Bool]` pattern buffer (`:481`), box x-positions (`:512`), `xs` (`:534`), a hit-step list (`:547`) +
  escaping closures (`:544`) → ~1,000+ allocs/sec across 4 lanes. All are pure functions of width/`n`,
  changing only on edits.
- **STACK grid** (`EuclideousPage.swift:8282`): rebuilds up to 44 `stackCell` leaves/frame, each
  resolving note-name strings (`:8214`) that change only on edits; `(0..<4).map { riffGhost }` per frame.
- **Riff overlay** (`EuclideousPage.swift:8095`): rebuilds a `ForEach` arrow view-tree + O(n²)
  `first(where:)` lookups (`:8102`, `:8118`) every frame.
- **MIX strips** (`MixPanelViews.swift:186/494`, `MixPanelV2Views.swift:266/696`): per frame build step/
  roll arrays, `ctx.resolve(Text)` + `.measure` for static HITS/STEPS labels (`MixPanelV2Views.swift:302`),
  and `Color(hex:)` per cell.
- **`partPlayButton` ×8** (`EuclideousPage.swift:3099`, 30 fps): `partNoteChip` builds a filtered array +
  closures per tick.
- **Supporting:** `laneStripPlan` (`EuclideousPage.swift:2516`) is heavy and runs 4–8× per eval uncached
  (the `lightweight` flag helps, keep it); `phaseLines` (`:1683`) reallocates at ~20 sites/eval during
  ANSWER; `Color(hex:)`/`Color(h:)` constructed inside 60 fps loops across the strip/mix painters.

**Fix:** hoist static geometry/strings out of the TimelineView closures (compute once per eval, as the
comment at `:8093` already does elsewhere); memoize `laneStripPlan`/`phaseLines` per body pass; promote
fixed palette `Color`s to `static let`. Defer `fastPoll`'s eager `.map` allocations
(`FourfoldRootView.swift:1024/1026/1043`) until the change check passes.

## Priority 4 — animated GPU blur (MEDIUM risk, GPU-specific — the old-iPad killer)

- `RiffArrowPainter.swift:131` re-rasterises `.blur(radius: … × flare)` **every frame** as the pulse
  envelope changes; also `EuclidLaneUI.swift:671` `addFilter(.blur(radius:3))` in a Canvas,
  `StackGridViews.swift:26`, `RandomModePainter.swift:440`. Animated blur melts an A9/A10 GPU.
- No `thermalState` / `isLowPowerModeEnabled` / frame-rate accommodation exists anywhere.

**Fix:** quantise/cap the animated blur radius, or swap the glow for a cheaper non-blur falloff under
Reduce Motion / low power.

## Not a bug (reported for completeness)

145 `AnyView` wrappers in `EuclideousPage.swift` defeat SwiftUI structural diffing, densest in the
per-lane tab bodies (`3000–4999`). This is the **deliberate** tradeoff to keep the AUv3 extension's 1 MB
main-thread stack from overflowing (`EuclideousPage.swift:175`). Leave it unless the stack budget frees
up; Priorities 1–3 are the wins that don't touch this tradeoff.

---

## Recommended sequence

1. **P1 relief valve** — Reduce Motion / PULSE-off / unbounded-interval. Low risk, directly serves weak
   & accessibility iPads.
2. **P2 re-eval isolation** — dedicated live-state `ObservableObject`. Biggest all-device win.
3. **P3 allocation hoisting** + **P4 blur** — steady-state churn and GPU.

P1 + P2 deliver most of the benefit. Verify each on device (watch CPU with the plugin playing, open,
on a weaker iPad; confirm no visual regression and animations resume correctly).

---

## Implementation status (2026-11-20)

- **P1 — DONE** (`7d797d2`): `euclideousAnimInterval(base, reduceMotion)`; Reduce Motion caps every
  TimelineView to ≤20 fps; the 2 unbounded sites got a 1/30 interval; the PULSE-only mixPulseOverlay
  pauses when PULSE is OFF. `PerfTests` covers the helper. **Device-owed:** confirm the capped rate looks
  right under Reduce Motion and the CPU drops.
- **P4 — DONE** (`d708d0f`): RiffArrow + StackGrid glows blur a CONSTANT shape and fade with `.opacity`
  (no per-frame blur-radius re-rasterise). (EuclidLaneUI's constant-radius Canvas trail blur left — can't
  decouple without redrawing the trail.)
- **P3 — PARTIAL** (`ea5cf9e`): the lane-strip step pattern (`stripBuf`) hoisted out of its 60 fps Canvas.
  **NOT done** (higher blind-risk, needs device verification): the STACK-grid 44-string-resolve split and
  the MIX-strip text-measure/`Color(hex:)` caching — both restructure hot draw code with no test reach.
- **P2 — NOT done; it is a large walk-trail-subsystem refactor, not a 10-field move.** Deeper trace:
  the page re-evaluates every hit not only from the ~7 hit-rate `@Published` fields but from the
  `walkTrails` **`@State`** chain — `updateWalkTrails()` (driven by `.onChange(of: riffWalkState)`,
  `EuclideousPage.swift:5368`) mutates `@State walkTrails` (`:1041`), which the trail TimelineView
  (`:5279`) reads, so the mutation itself re-evals the body every hit. To actually stop the hit-rate
  re-eval, ALL of these must move to the pull-model together: the 7 fields AND the whole walk-trail state
  (`walkTrails`, `walkPrevStep`, `walkPrevBeat`, `walkTickAt`, `walkTagLog`) plus `updateWalkTrails` /
  `logWalkTagHits` re-driven from a non-SwiftUI 30 Hz poll. That is a high-regression-surface refactor of
  the walk trails / arrows / markers / key-flash — all live indicators with ZERO macOS test reach — so a
  mistake silently freezes one and I cannot see it. **Recommended: do this with the app running** (change
  → device spot-check → iterate). Given P1 already removed the dominant 60 fps load, P2's marginal benefit
  (a few full-body re-evals/sec → edit-rate) does not justify shipping it blind.
