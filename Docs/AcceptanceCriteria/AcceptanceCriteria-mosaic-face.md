# AcceptanceCriteria — THE MOSAIC (cell-face candidate F) (captured 2026-08-05)

**STATUS: PHASE 1 BUILT (2026-08-06, branch `feat/mosaic-cell-face`; iOS builds, macOS green; DEVICE eval owed).**
A cell-face candidate — built so Paul can evaluate it on device against the SEAL. What landed:
- **COMPOSITION** — `Derivations.mosaicLayout(hash:)` (pure/testable): the SAME behavioural hash as the seal →
  4–6 rectangles tiling the unit face (recursive largest-rect split on the long axis at a hash-chosen interior
  ratio; returned largest-first so rank 0 = the biggest block). Twins share the layout (identity law). Tests lock
  determinism · count 4–6 · tiles-the-face (Σ area = 1) · in-bounds · sorted · twin-shared · hash-sensitive.
- **RENDERER** — `GridUI.mosaicFace` draws the tiling on the cell face (a hair-gap inset between blocks reads them
  as a mosaic), tone-on-tone + faint at rest (silent = still). On a strike it BREATHES: brightness = `vel × life`,
  the SAME strike-feed envelope the seal comet uses (hold while sounding · fade ~0.45s on release · ~0.5s pluck).
  Rank tints the peak — bigger blocks glow warmer/dimmer, small ones brighter (echoes "peaks light the small
  ones" at the cell level). Wired in `cellView` behind `useMosaicFace` (the seal code is kept intact for the A/B).
- **DEFERRED (Phase 2, flagged):** the per-NOTE feed — POOL-RANK → rect-by-size, per-note (rank, vel, durBeats)
  with the timed-fade-completes-at-note-off gate. Needs the render-path per-cell feed upgraded to note-grain (the
  emitter-feed pattern), which is engine work. Phase 1 lights the WHOLE mosaic per cell-strike as an honest
  approximation; the identity-plate (edit page) still shows the seal.

From
`SPEC-mosaic-face`. Rectangles that breathe the rhythm — the best tiny-legible face candidate (blocks beat lines at
30px). Sits beside the alien-circuitry study (candidate E): circuits = signature/figure; the mosaic = rhythm/breath.
Could hybridise (circuit ink over a breathing mosaic ground).

## COMPOSITION (identity, static when silent)
- Hash → a layout of **4–6 rectangles, various sizes** filling the face (a quiet Mondrian; sizes/positions/gaps from
  the hash; twins share the layout — the identity law unchanged). At rest: tone-on-tone, very faint (a silent cell is
  perfectly still — invisible=frozen holds).

## LIGHTING (the rhythm made visible)
- **Note-on lights a rectangle**; mapping = POOL-RANK → rect by SIZE (bass lights the biggest block, peaks the small
  ones — register readable at a glance). Velocity → peak brightness (small deltas).
- **THE TIMED FADE (the derive-law gift):** derived notes carry their DURATION at emission; the fade is scheduled to
  COMPLETE AT NOTE-OFF — the fade IS the gate. Long notes breathe slow, ratchets shimmer, LENGTH's phrasing draws
  itself. Live/latched holds (unknown duration) = light-and-hold, quick fade on release.
- Overlaps: a re-lit rect re-peaks (louder wins the peak); echo-era tails light like any note.

## FEASIBILITY
- Strike feed ✓ (velocity, per cell). NEEDS: the per-cell feed upgraded to note-grain WITH DURATION (the derivation
  already knows it — plumb (rank, vel, durBeats) per strike; offs for held notes via the sounding diff, the
  emitter-feed pattern). ×64 cost: alpha lerps on ≤6 rects/cell — cheap.
