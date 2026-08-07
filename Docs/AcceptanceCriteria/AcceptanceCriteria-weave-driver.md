# Acceptance Criteria — WEAVE (working name): the rank-clocked polyrhythm driver

_Captured from the ferry `SPEC-weave-driver.md` (design-side Claude, Paul 2026-08-07). SPEC OF RECORD, NOT yet
built. Paul's "blend pitch and rhythm" — "the one design with real worth, plus two chips."_

## THE STAGE
- **A DRIVER class** (joins arp/rtc/strum in the driver family; the last-driver rule applies): each pool member
  ticks on ITS OWN CLOCK, derived from its RANK. The chord IS the polyrhythm — hold three notes: bass quarters,
  middle eighths, top sixteenths; change the chord and the weave re-derives live (admission-time laws as ever).
- Pure by construction: each note's schedule = f(beat, rank, mode) — no stored state, replay-exact.

## PARAMS
- **BASE** — the slowest clock (the bass rank's rate; musical divisions).
- **MODE (the ratio law)**:
  - **LADDER** — rank n = the next division up (1/4 · 1/8 · 1/16…) — the accessible default.
  - **HARMONIC ★** — rank n ticks at n× base (1:2:3:4…) — pitch ratios AS time ratios; the true blend (rhythm is
    slow pitch).
  - **DRAWN** — a per-rank rate row (the 8×N widget) for authored weaves.
- **GATE %** (shared) · **SPAN** (how many ranks weave; extras join the top clock) · phase laws standard
  (RETRIG/LEGATO on the weave's clocks; LEGATO across twins = the interlock never restarts).

## WHY IT EARNS THE SEAT (and the general "blend" mostly doesn't)
The shape arp keeps pitch and rhythm SEPARABLE by design — coupling is the exception that must pay. WEAVE pays:
one chord → an interlocking ensemble no other stage can state, the pool-aware family's crown (the pool sourcing
TIME structure, not just pitch). COUNT interplay free: more notes = a denser weave, automatically.

## THE TWO CHIPS (couplings worth a param, not a stage)
- **TAPE** (a RATE-trigger option): rate ×2 carries pitch +12 — varispeed feel on the existing rate actions.
- **DUR-BY-INTERVAL** (a LENGTH/GROOVE option): leap size → note length (steps short, leaps long — contour
  phrasing, the singer's rule).
