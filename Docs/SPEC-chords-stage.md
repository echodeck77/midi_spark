# SPEC → Code — CHORDS (Paul, 2026-08-29: deriving progressions
# from a key — captured, awaiting his word)

## The thesis trick (why it's cheap)
A diatonic chord = RANK ARITHMETIC on the scale pool: degree n =
pool-steps {n, n+2, n+4} (stacked thirds; quality falls out of
the key). No chord is ever stored — progressions are DERIVED.
Requires a scale-class pool upstream (the SCALE door, or KEYS).

## The stage — CHORDS (name open: DEGREES / PROGRESSION)
**MODE (which degree, when):**
- **FOLLOW [door ▾] — ★ the bounce**: the source door's note
  NAMES the degree (its rank in the scale); the chord = thirds
  stacked on it. Play a bassline on B → harmony blooms on A.
  One-finger progressions. Rides the PEDAL machinery
  (first-note-per-window · SEED SOUNDING|STRIKE · CARRY across
  silences · the register FOLD for the bass's octave).
- **PATTERN — the drawn progression**: the state matrix — rows =
  degrees I–VII · columns = steps · radio-per-column. Paint
  I–vi–IV–V; it plays in ANY declared key. ROTATE · SPAN as
  everywhere; the e-brush legal.
- **WALK — the gravity dice**: seeded random walk with
  functional weights (tonic pulls home · dominant resolves ·
  subdominant wanders). The progression casino that always
  lands. RE-ROLL = new seed.
**VOICING**: TRIAD | 7TH | ADD9 (one more third) · SPREAD:
CLOSE | OPEN (an octave lift on the middle) · INVERT toward the
previous chord (voice-leading lean: nearest inversion — smooth
by construction).
**WINDOW**: CELL | ROW | BAR (when the degree refreshes; the
span family).

## Kinships (no dupes)
- HARMONIZE SOLI (unratified §C) = per-NOTE voicing of a line;
  CHORDS = per-WINDOW harmony from a degree. Siblings.
- Downstream everything composes: [CHORDS → STRUM] = raked
  progressions · [CHORDS → ARP] = the progression arpeggiated ·
  [CHORDS → drone/span-sustain] = the pad bed that follows your
  bass finger.
- The bounce + the complement: B names the chords on A while
  B's own line dances in A's gaps — two doors, a whole band.
— design-side Claude

## STATUS — ✅ RATIFIED (Paul, 2026-09-01)
All three modes (FOLLOW · PATTERN · WALK) + voicing (TRIAD|7TH|ADD9
· CLOSE|OPEN · invert-toward-previous) RATIFIED for build. §2 degree
matrix is canon. Build order: C1 pure core → C2 PATTERN → C3 FOLLOW
→ C4 WALK. Plan: `Docs/PLAN-incoming-2026-09-01.md` §B.

## §2 — THE DEGREE MATRIX, DETAILED (Paul, 2026-08-29 — the
## PATTERN mode's panel, canon; CHORDS is ratified)
- **EIGHT ROWS = the seven degrees + REST** (the house geometry).
  Columns = steps; radio-per-column; **empty column = CARRY the
  previous chord** (progressions hold by default); REST = the
  explicit silence row.
- **QUALITY-AWARE HEADERS**: the rows label themselves from the
  DECLARED key — I · ii · iii°… with the right maj/min/dim
  glyphs for the actual scale, self-updating on key change
  (teach-in-place doing the theory).
- VOICING chips beneath (§1's set: TRIAD|7TH|ADD9 · CLOSE|OPEN ·
  invert-toward-previous) · WINDOW = the hold span · ROTATE
  ◀n▶ · the e-brush legal on the matrix as everywhere.
- The setup named: receiver D = SCALE → a D-fed chain →
  [CHORDS → STRUM/ARP/DRONE…] — the progression drawn once,
  playing in whatever key D declares.
