# SPEC → Code — THE POOL-AWARE FAMILY (set-awareness dividends across
# the roster) — 2026-08-05, from Paul's "what else can know the pool?"
_The engine carries sets, not streams — these are the stages that
should exploit it. All derive-pure (the pool is known every beat);
all re-rank live at chord changes per the split's admission-time
law._

## ★★ HARM: MODE FIXED | POOL
POOL counts intervals in POOL-STEPS: +1 = the next held note up, −1
= the next down, +2 two chord-tones up (octave-wrapping past the
top). Harmony that CANNOT clash — the added voices only ever speak
held notes, re-voicing with every chord. FIXED (semitones) remains
for deliberate colour. Chip: MODE; the interval param re-labels
(st | steps) with the mode.

## ★ SPLIT: OUTPUT POLICY BLOCK | TO-ALT
TO-ALT sends the SUBSET to the cell's ALT destination set and the
REMAINDER to MAIN — the divider: [ARP → SPLIT TOP 1, TO-ALT] =
crown to the lead synth, body to the pad, one stage, rank-live.
(BLOCK = the shipped filter behaviour.)

## FENCE: FOLD OCTAVE | POOL
POOL folds strays to the NEAREST HELD NOTE — trespassers re-voiced
into the chord instead of the octave. (Rack detail chip.)

## CHNC: WEIGHT FLAT | FAVOR-TOP | FAVOR-BOTTOM
The dice learn the chord's shape: probability tilted by rank — the
bass survives, the sparkle thins first (or inverted). One chip.

## CURVE (rack) + velocity generally: RANK-TILT
A bipolar tilt-by-rank (peaks accented ↔ bass grounded) — STRM's
tilt generalised. Rack detail param on CURVE.

## Honorable: STRM SPREAD NORMALIZE (by pool size)
Three notes or six, the rake spans the same width — a small toggle,
tasteful. Low priority.

## Kinships on record (no build): the MAGNET (parked wire jewel) ·
## FOLLOW-echo · the CC lane's future pool-centroid — same family.
— design-side Claude

## §2 — THE COUNT FAMILY (Paul, 2026-08-05: the pool's SIZE as a
## signal). All pure — N is known every beat; changes reconcile at
## admission per the standing laws.

### The count as a controller (the headline pair)
- **★★ THE COUNT GATE** — a stage (or SPLIT param): the cell speaks
  only when N is within [min,max]. Voicing size becomes ARRANGEMENT:
  one finger wakes the solo-line cells, a fist wakes the wall —
  the held chord's size selects the orchestration (live OR latched). Nothing
  else does this; it costs one comparison.
- **★★ THE COUNT LADDER** — LADDER gains AUTO: BY COUNT (per column
  or global): activeRow = f(N) — one key rides rung 1, eight keys
  rung 8. The bigger the held chord — played or latched — the higher
  the rung. Demo gold; opt-in; arm/blink rules unchanged (the
  switch still lands at column entry).

### Texture invariance (the constancy workhorses)
- **★ FIT mode on ARP** — the constant-cycle arp: RATE derives so
  one full pool traversal = exactly one beat (or one column),
  whatever N is. Three notes = triplets, four = sixteenths — adding
  a note SUBDIVIDES instead of lengthening; the figure breathes
  with the voicing and the harmonic rhythm never drifts.
- **★ CONSTANT-DENSITY on CHNC** — probability auto-compensates
  (p = target/N): the texture keeps one weight whether you hold a
  dyad or a fistful. The crowding problem, solved at the die.
- **HARM: THICKNESS BUDGET** — added voices fill up to a total
  (pool + added ≤ budget): small chords bloom wide, big chords add
  little — constant mass.
- **CURVE: COMP-BY-COUNT** — per-note velocity eases as N grows
  (the string-section law: one bow's weight, divided) — big grabs
  stop blowing out velocity-sensitive patches.
- RTC: BURSTS = N (the ratchet mirrors the hand) + STRM
  spread-normalize (§1) — the small siblings.
- Future kinship: N as a FOLLOWER source for the CC lane (pool size →
  expression out) — two-lane era.
