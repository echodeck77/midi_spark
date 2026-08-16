> ✅ BUILT (2026-08-16): COIN `a780e19` + PATTERN `793808a`. §1 COIN + §2 PATTERN + §3's one-processor/MODE-radio
> interface all shipped. Note vs spec: PATTERN standalone emits per-slice rhythm via a dedicated tick emitter
> (TUTTI stays a non-driver otherwise); the slice palette is the settling set (cheap to cull on device).

# SPEC → Code — TUTTI (working name; Paul, 2026-08-13: "50% a
# single note, 50% the full chord — in front of an arp, or alone")

## THE STAGE (set-level chance — CHNC's correlated cousin)
Per STEP, one seeded roll decides the whole set's fate:
- **SOLO** → exactly one note passes.
- **TUTTI** → the full set passes.
(CHNC dices notes independently; TUTTI dices the SET — thinning
texture vs alternating densities: two objects, both earn seats.)

## PARAMS
- **BALANCE (0–100%)** — the chance of TUTTI per step (50 = Paul's
  coin; 20 = mostly pedal with blooms; 80 = full with dropouts).
- **PICK (LOW · HIGH · RANDOM · CYCLE)** — which note carries the
  SOLO steps (rank vocabulary: LOW = the root-pedal; CYCLE = the
  solos themselves walk).
- Seeded per step index — replay-exact, the standing law.
- v2, noted: **SIZE** (partial tutti — 2…N) · a MASK row (authored
  solo/tutti patterns; euclid-k of tuttis) · the "or more" lives
  here.

## PLACEMENTS (why it earns the seat)
- **[TUTTI → ARP]** — the showcase: the arp's pool flickers per
  step between one and all — pedal-tone steps trading with full
  climbs; COUNT-aware behaviours downstream dance with it free.
- **Standalone** — chord comping from a held grab: stabs and
  single hits in seeded rhythm.
- **[TUTTI → STRUM]** — rakes alternating with plucks.
Engine note: a per-step set-subset function (pure, f(step, seed,
balance) — CHNC's event-dice class at set grain; the window/derive
laws unchanged).
Manual line: "Sometimes the band, sometimes the soloist — the
coin decides each step."
— design-side Claude

## §2 — MODE: COIN | PATTERN (Paul, 2026-08-13: "without chance —
## every slice authored, like the split")
- **The radio (the CC-stage precedent)**: COIN = §1 (BALANCE +
  PICK, seeded). **PATTERN = the 8-slice SET-SHAPE row** — chop's
  paint grammar, fourth domain: per slice, the chord renders as an
  authored shape.
- **The slice palette (curated, GROOVE-style pick-then-paint)**:
  **ALL · LOW · HIGH · TOP2 · BOT2 · LOW+8va · ALL−8va · REST**
  (the ±oct variants as first-class states; the exact palette =
  Paul's device pass — states are cheap to add/cull).
- **Inherits the slice family's gear**: the RATE lane (slices per
  window) · **the ROTATE gesture** (the comping pattern walks the
  bar — voicing-rhythm as a performance move) · per-slice states
  render on the row exactly as GROOVE/LENGTH do.
- **The family sentence, for the manual**: "SPLIT chooses once;
  the COIN flips each step; the PATTERN composes the bar."
  [TUTTI-PATTERN → ARP] = the walk re-voiced per slice — comping
  built into the climb.

## §3 — ONE PROCESSOR + THE INTERFACE (Paul's two questions, ruled)
**ONE stage** (the MOD/CC precedent: one seat, a MODE radio, row 2
reshapes; both configs persist — switching modes never destroys).

**The stage panel (standard header: bypass · macro · vel-mixer —
blend is LIVE here, notes flow through):**
- **Row 1 — MODE: [ COIN | PATTERN ]** (the spine, two big chips).
- **COIN face**: the **BALANCE slider with the concept as its
  labels — SOLO ←————→ TUTTI** (the slider IS the idea) + **PICK**
  chip (LOW · HIGH · RANDOM · CYCLE).
- **PATTERN face**: the **8-slice row** (GROOVE's pick-then-paint:
  choose a state chip, tap slices) · the state palette beneath
  (ALL · LOW · HIGH · TOP2 · BOT2 · LOW+8ᵛᵃ · ALL−8ᵛᵃ · REST) ·
  **RATE** chip · the ROTATE affordance (chop's walk).
- **The header window (S)**: the mini-roll drawing per-step set
  density — chord-vs-single alternation is the most window-legible
  behaviour in the roster; the stage's truth at a glance.
- Mode-switch defaults: PATTERN row starts ALL (safe/audible);
  COIN starts 50/LOW (Paul's original sentence).
