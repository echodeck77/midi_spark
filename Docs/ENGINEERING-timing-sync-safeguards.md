# Engineering note → Code — TIMING & SYNC SAFEGUARDS (the test family)
_Commissioned by the user, 2026-07-30. The architecture's built-ins are
restated for the record; the numbered items are the asks — mostly
tests, per the house method (assurances are bought with green)._

## Already load-bearing (restate in docs, no build)
- **THE ONE-CLOCK LAW**: everything derives from the host's ABSOLUTE
  beat — no wall-clock, no internal accumulators, phase recomputed
  never incremented. Tempo changes/automation and host-wide sync are
  free by construction; there is nothing to drift.
- **Determinism as meta-safeguard**: same beat + state = same output —
  any escaped timing bug is reproducible (and the future dashcam makes
  field cases replayable).

## The asks
1. **BLOCK-SIZE INVARIANCE (the crown jewel)**: render identical
   passages at 64/128/256/512/1024-frame blocks → assert BYTE-IDENTICAL
   emitted MIDI (events + sample positions in absolute time).
   Proves derivation never leans on block boundaries; kills the class.
2. **SAMPLE-OFFSET EMISSION**: assert events land at exact computed
   sample offsets WITHIN blocks (never block-quantized — that's ~5ms
   jitter, an audible flam on 1/32s). Inter-onset test on a fast
   ratchet: ±0 samples.
3. **DISCONTINUITY = A BOUNDARY**: non-contiguous beat deltas (host
   LOOP-JUMP backward · SEEK forward · start mid-bar) run the existing
   transition machinery (reconcile voices, re-derive). Tests for all
   three, each asserting no stuck notes + no double-strikes
   (siblings of transport-stop-leaves-silence).
4. **PUBLISH-BEFORE-DERIVE asserted**: the snapshot-swap ordering at
   the wrap gets its RouterTest (bug 4a's suspect, made a permanent
   guard). Edits never mutate live state; one atomic pointer swap.
5. **THE RENDER-BUDGET WATCHDOG** (promote from the flight-recorder
   family): measure per-block derivation cost; log breaches over a
   threshold — creeping expense caught in dev, not on stage.
6. **INPUT MONOTONICITY**: sort/clamp incoming event timestamps per
   block before pool updates (cheap insurance against host quirks).
Sequencing: the user's call; 1–4 are pure test work and can ride any
quiet moment. — design-side Claude
