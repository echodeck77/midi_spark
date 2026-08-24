# SPEC → Code — RIFF (Paul, 2026-08-19: "what could a riff
# processor look like?" — captured for the shelf, not commissioned)

## THE CONCEPT (thesis-pure: a stencil, never stored notes)
A RIFF is a stored pattern of CHOICES — per step: {RANK (pool
position 1–8) · OCT nudge (±) · accent · tie/rest} — that DERIVES
against whatever is held. The chord answers the stencil: hold Cm,
it's the riff in Cm; hold F, the same riff in F. Zero pitches
stored; the instrument still contains no notes.
**The family line**: ARP computes the walk · RIFF authors it ·
the CLIP (catch) photographs it. Three objects, no overlap.

## THE PANEL (the step-lane grammar, one new lane type)
- **STEPS** (8 | 16) · **RATE** (ArpRate) · per-step lanes:
  **RANK** (1–8 · — rest · ⌒ tie) · **OCT** (−1·0·+1) · **ACCENT**
  (the velocity stroke) · **LENGTH** optional v2.
- **WRAP chip** (rank exceeds the held count — a 5 against a
  3-note chord): **FOLD** (5→2 an octave up · default, musical) |
  **CLAMP** (top note) | **WRAP** (5→2 same octave).
- **★ CAPTURE**: arm, play the line ONCE on the door against the
  held chord — the engine records it AS RANKS (nearest-pool-
  position match). Play it once; it follows every chord after.
  (The riff-capture is the feature; the lanes are its editor.)
- The header window draws the stencil (rank curve + accents) —
  highly legible.

## PLACEMENT (a source-shaper; generative-early per the law)
[RIFF → RATCHET] the riff ratcheted · [RIFF → HARM] harmonized ·
[RIFF → TUTTI] re-voiced per slice · [RIFF alone] = the authored
line, chord-following. LIBRARY-saved riffs are chord-agnostic by
construction — the reusable-riffs idea, delivered without the
seat/figure machinery (which stays parked per Paul).
Manual line: "A riff here isn't notes — it's the shape of a line.
Hold any chord and the shape plays it."
— design-side Claude

## §2 — CAPTURE NEEDS NO SECOND INPUT (Paul's catch, resolved by
## the latch)
- **Arming CAPTURE snapshots the pool as the FRAME** (the LOCK
  mechanism's own move — same tiny machinery). While armed, the
  door's live notes DIVERT to the recorder (they never touch the
  pool); the frame cannot shift under the line being played.
- **The flow**: LATCH the chord → arm → play the line on the SAME
  door → disarm. The latch is the second hand; hands-free holding
  was built for exactly this hour.
- PIANO doors (typed, not played): the line enters via the step
  lanes instead — the editor path; capture is the MIDI door's
  gesture.
- Two-door capture (chord on R1, line on R2) remains POSSIBLE for
  two players, never REQUIRED. One door suffices by design.

## §3 — UNDER CONSIDERATION (Paul, 2026-08-19): the generator ·
## straight capture · the advantage doctrine
- **THE RIFF GENERATOR** — the panel's own 🎲 + a SHAPE chip
  (ARCH · FALL · RISE · Q&A · PEDAL): seeded stencil-rolling by
  contour archetype, density from a step budget. The dice at rank
  grain; the ensemble-roll's lead rows would deal from it.
- **STRAIGHT CAPTURE** — the verbatim cousin (pitches, not ranks).
  Note the kinships: at the EMISSION end this is CATCH (built
  concept); at the DOOR it is the parked PURE-SOURCE RECORDER
  birthstone (capturing what the hands play, pre-derivation).
  **The promotion path is the point: PHOTO → STENCIL** — a
  straight capture converts to a riff (pitches → ranks against a
  chosen frame) and the frozen line learns to follow harmony.
- **THE ADVANTAGE DOCTRINE (positioning, on record)**: vs
  traditional sequencers, captures here win on exactly four
  counts — they JOIN THE RELATIONSHIPS (claim/duck/alt as a
  player, not a track) · they can be TAUGHT HARMONY (the
  conversion) · capture is RETROSPECTIVE (the ring) · they remain
  DERIVATION CITIZENS (polymeter, scenes, replay). For linear
  song-building a DAW wins; captures live here only to join the
  band. The manual and the App Store copy speak it that way.

## §4 — THE FOLLOWING FRAME (Paul's Piano Motifs case, 2026-08-19
## — the amendment his workflow forces)
- **FRAME chip: HELD | FOLLOWING.** HELD = §2 (one snapshot at
  arm). **FOLLOWING = the frame is the pool TIMELINE** — each
  captured note's rank is measured against the chord sounding AT
  ITS MOMENT (the LOCK work's pool-trajectory concept, reused).
  Replay derives each step against the pool at play time: a
  melody captured over C→Am→F→G re-voices over ANY new
  progression, chord by chord as it passes.
- **THE USE CASE, on record (ecosystem pairing + the advantage
  doctrine's live proof)**: Piano Motifs → R1 chords (frame),
  R2 melody (line, two-door capture) → capture FOLLOWING → swap
  the progression → variations on the melody, always consonant.
  8x8 State as the app that makes OTHER generative apps' output
  harmonically portable.
- Caveats, honest: non-chord passing tones snap to chord
  positions in v1 (the rank+offset hybrid = the parked fix);
  mid-riff chord changes are seamless (config never stops the
  engine — the derive law does the work).

## §5 — THE MATRIX EDITOR: the 303 assembles itself (Paul,
## 2026-08-22 — the widget taxonomy completes this spec)
- **THE RANK MATRIX = RIFF's editor**: rows = pool ranks 1–8 ·
  columns = steps (8/16 via SPAN) · radio-per-column · empty
  column = REST. The melody stencil drawn as a grid — Paul's
  "left axis = note number."
- **THE MODIFIER LANES beneath (the x0x grammar, from the two
  ratified widget species)**:
  - **ACCENT** — the slider lane (or a toggle row at fixed
    boost; glass picks).
  - **SLIDE** — a toggle lane: the step plays LEGATO into the
    next → **feeds GLIDE SYNTH mode for authentic 303 slides**
    (CC65/5 + overlap — the two specs interlock).
  - **OCT** — a 3-state row (−1 · 0 · +1).
  - **TIE** — extends the previous step.
- **The differentiator, stated**: every x0x clone sequences
  pitches; **this sequences RANKS — the acid line FOLLOWS THE
  CHORD.** Change the harmony, the riff re-voices. Nothing else
  does this.
- **The free use-case**: hold 8 drum-trigger notes → the ranks
  ARE the kit → the matrix = a drum sequencer whose kit is
  whatever you hold. No new card; a manual chapter.
- What else suits rows×steps: WEAVE DRAWN (rate×rank,
  transposed ✓ noted) · a future OCTAVE-PATTERN mode for any
  driver · TUTTI PATTERN (already converted). CAPTURE (§1's
  play-it-in path) remains the stencil's other door — the
  matrix edits what capture records.

## RATIFIED (Paul, 2026-08-22 — off the shelf)
RIFF is law, whole: the rank stencil (§1), one-door capture (§2),
the generator + straight-capture riders as captured (§3), the
FOLLOWING frame (§4), and the MATRIX EDITOR + x0x lanes + the
GLIDE-SYNTH slide interlock (§5). The chord-following 303 builds.
(If Paul intends CAPTURE/FOLLOWING held back for a later phase,
one word re-fences them; otherwise the spec ships as one.)
