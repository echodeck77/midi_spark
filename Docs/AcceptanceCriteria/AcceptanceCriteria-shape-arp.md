# SPEC → Code — THE SHAPE ARP: fixed-length patterns + the OVERFLOW
# law (2026-08-05 — Paul's "fixing the note count rather than just
# iterating," answered)

## THE MODEL
- ARP gains **LENGTH (M): POOL | 2–16**. POOL = today (pattern
  iterates the held set; length tracks N). A FIXED M = the pattern
  is a SHAPE: M steps of pool-indices, independent of what's held.
- SHAPES: the algorithmic set re-expressed as index sequences (RISE
  1..M · FALL · PINGPONG · SKIP 1,3,2,4… · STAIRS 1,2,1,3,1,4…) +
  **CUSTOM = the drawn shape** (the step-sequencer, unified under
  this same law — pool-indices, as ruled).

## THE OVERFLOW LAW (the piece Paul hadn't figured out)
When a step's index exceeds N, one of four policies (chip):
- **LIFT (default ★)** — index mod N, PLUS an octave per wrap:
  8-step RISE over 3 notes = 1·2·3·1′·2′·3′·1″·2″. **The contour
  survives; N sets the register span.** The shape is the melody;
  the pool is its palette.
- WRAP — plain mod (flat; the CUSTOM ruling's original).
- FOLD — reflect at the top (pingpong compression).
- CLAMP — stick at the highest note (pedal-peaks).

## CONSEQUENCES (why this is the count's best payoff)
- **Rhythm decouples from voicing**: fixed M = a constant M-feel
  over ANY chord — polymeter you can trust (M=5 against the column
  is stable whatever you hold).
- **N becomes the GRANULARITY knob**: fewer notes = wider octave
  travel of the same shape; more = tighter. Playable, latched, or
  COUNT-LADDER-driven — the family composes.
- **Shapes are shareable**: a pattern independent of the held chord
  is a library object (the CUSTOM editor's saves gain meaning).
- FIT (constant-cycle, §2) composes: M steps in exactly one column
  regardless of both M and N — fully invariant figures.
- Phase laws unchanged (RETRIG/LEGATO govern the step pointer as
  ever); derive-pure (step = f(tick), pitch = f(shape[step], pool)).
— design-side Claude

## §2 — THE RHYTHM LAYER (Paul: "more rhythmic or sparse sequences")
The shape gains a second, separable layer — WHAT × WHEN:

- **★★ REST and TIE as step values.** Any step may be: an INDEX
  (play) · **REST** (silence; time passes) · **TIE** (the previous
  note extends through this step — no re-strike; the gate stretches,
  same mechanics as GROOVE's slide-tie). Shapes become true rhythmic
  melodies: `1 · 2 · — · 3 · — · 1′ · ~ · 2′`. CUSTOM's drawn grid
  gets rest/tie cells (tap-cycle: note → rest → tie).
- **★★ THE RHYTHM MASK — separable WHEN over any shape.** RHYTHM:
  **ALL | EUCLID k | DRAWN** — a hit-mask over the M steps; masked
  steps rest, the shape's indices only advance on hits [pin: or
  advance regardless — ADVANCE: ON-HIT | ALWAYS, two feels, one
  chip]. EUCLID(k, M) = instant musical sparseness (3-over-8,
  5-over-16 — the whole canon); any shape × any mask = the
  combinatoric win.
- **MASK ROTATE** — the CHOP-ROTATE gesture on the rhythm mask
  (downbeat placement; a TAP action candidate: MASK-ROTATE).
- **★ PER-STEP CHANCE** (drawn shapes): an optional per-step % —
  dice built into the notation, Elektron-style. Sparse by
  authorship, still seeded/replay-safe.
- **POLYMETER, stated as a rhythm tool**: fixed M ≠ column length =
  rolling syncopation by construction (M=5 shapes roll against the
  bar; two cells at M=5 and M=7 = the phase machine, no new
  engine).
- The three rhythm layers, now named for the manual: **CHOP =
  routing rhythm · GROOVE = articulation rhythm · THE MASK =
  melodic rhythm** — each at its own level, all composable on one
  cell.
