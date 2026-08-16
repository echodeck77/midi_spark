# Acceptance Criteria — WEAVE (working name): the rank-clocked polyrhythm driver

> ✅ BUILT — phase 1 (2026-08-16, `ff81a15`): the DRIVER + LADDER + HARMONIC modes, BASE/SPAN/GATE, chain-driver
> fold. **DRAWN + EUCLID modes are phase 2** (the per-rank rate widget + per-rank euclidean — the WeaveMode enum has
> room). The two chips (TAPE, DUR-BY-INTERVAL) and FREE/LEGATO phase remain deferred. v1: RETRIG only; audition sustains.

_Captured from the ferry `SPEC-weave-driver.md` (design-side Claude, Paul 2026-08-07, updated 2026-08-08 with the
EUCLID mode §2). SPEC OF RECORD, NOT yet built. A new DRIVER-class processor (joins arp/ratchet/strum) — each held
note ticks on its own rank-derived clock, so one chord becomes an interlocking polyrhythmic ensemble._

## THE STAGE
- **A DRIVER class** (joins arp/rtc/strum in the driver family; the last-driver rule applies): each pool member ticks
  on ITS OWN CLOCK, derived from its RANK. The chord IS the polyrhythm — hold three notes: bass quarters, middle
  eighths, top sixteenths; change the chord and the weave re-derives live (admission-time laws as ever).
- Pure by construction: each note's schedule = f(beat, rank, mode) — no stored state, replay-exact.

## PARAMS
- **BASE** — the slowest clock (the bass rank's rate; musical divisions).
- **MODE (the ratio law)**:
  - **LADDER** — rank n = the next division up (1/4 · 1/8 · 1/16…) — the accessible default.
  - **HARMONIC ★** — rank n ticks at n× base (1:2:3:4…) — pitch ratios AS time ratios; the true blend (rhythm is slow
    pitch).
  - **DRAWN** — a per-rank rate row (the 8×N widget) for authored weaves.
  - **EUCLID (§2, Paul 2026-08-08)** — each rank r plays **E(r, M)** instead of a divided rate — bass on the lone
    downbeat, middle on the tresillo, top dense-even: an interlocking euclidean ensemble from one grab, re-derived
    per chord. (M = the weave's cycle length; SPAN and phase laws unchanged.)
- **GATE %** (shared) · **SPAN** (how many ranks weave; extras join the top clock) · phase laws standard
  (RETRIG/LEGATO on the weave's clocks; LEGATO across twins = the interlock never restarts).

## WHY IT EARNS THE SEAT (and the general "blend" mostly doesn't)
The shape arp keeps pitch and rhythm SEPARABLE by design — coupling is the exception that must pay. WEAVE pays: one
chord → an interlocking ensemble no other stage can state, the pool-aware family's crown (the pool sourcing TIME
structure, not just pitch). COUNT interplay free: more notes = a denser weave, automatically.

## THE TWO CHIPS (couplings worth a param, not a stage)
- **TAPE** (a RATE-trigger option): rate ×2 carries pitch +12 — varispeed feel on the existing rate actions.
- **DUR-BY-INTERVAL** (a LENGTH/GROOVE option): leap size → note length (steps short, leaps long — contour phrasing,
  the singer's rule).

## NOTE (Code, 2026-08-09)
Adjacent to the generators just built (EUCLID/BURST/CASCADE are single-slot; WEAVE is a DRIVER — bigger). The §2
EUCLID mode + the shape-arp "EUCLID MEETS THE POOL" (E(N,M), k follows the held count) both suggest a near follow-up
to the shipped EUCLID: let its PULSES track the live pool size. Deferred.
