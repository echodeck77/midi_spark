# SPEC (UNRATIFIED — Paul is still figuring; capture only, do NOT
# build) — THE MELODY/CHORD SUITE (2026-08-19)
# Three processors + one interface rule. References
# SPEC-riff-processor.md §1–4 (does not restate it).

## §0 — THE INTERFACE RULE (Paul's): receiver controls live IN THE
## PROCESSOR PANEL
Cross-door sources are chosen in-panel via DOOR CHIPS — **THIS ·
R1 · R2 · R3 · R4** (each wearing its glyph/nickname). The
processor picks WHICH EAR; it never rewires the ear (cable/
channel/source stay in the input pop-up). Control-class doors are
excluded from music pickers (the hygiene law).

## A — RIFF: capture + remap (already specced; the rule applied)
As SPEC-riff-processor §1–4, with the door pickers in-panel:
**LINE: [THIS ▾]** · **FRAME: [R1 ▾] + HELD|FOLLOWING**.
Paul's flow: melody on R2 captured FOLLOWING against R1's chords;
new changes on R1 → the melody re-voices chord-by-chord.

## B — TRIGGER (name open): the chords play the melody's rhythm
A stage on a chord-fed cell whose emission clock is ANOTHER
DOOR'S NOTE-ONS.
- **SOURCE: [R2 ▾]** — the rhythm ear.
- **MODE: STAB | CLOCK** — STAB: each source onset voices the
  current pool once (the comping stamp). CLOCK: the source's
  onsets REPLACE the beat clock for this cell's chain — the arp/
  euclid/weave steps land ON the melody's hits (derivation =
  f(state, input, onset-index): pure, replay-safe — onsets are
  input events like any note).
- **LENGTH: TO-NEXT | FIXED n** (ring until the next hit, or a
  set gate) · velocity: inherit source vel | fixed (chip).
- The comping-that-breathes cousin (duck-on-source-activity) is
  NOT this stage — parked separately.

## C — HARMONIZE gains THE SOLI MODE: dynamic block harmony
**VOICES FROM: [FIXED | DOOR R1 ▾]** — in DOOR mode the added
voices are drawn from the source door's CURRENT pool, placed
relative to each incoming melody note:
- **VOICES 1–3** · **PLACE: BELOW | ABOVE | AROUND** ·
  **SPACING: CLOSE | OPEN | DROP-2** (nearest pool tones per
  place+spacing) · range clamp.
- The progression changes → the same line re-harmonises under
  itself (the Glenn Miller soli, derived; fixed-semitone mode
  remains as today). Melody notes outside the pool pass
  untouched, voiced around. Voice velocity = VOICE LEVEL (the
  reconciled macro).

## Status
Held UNRATIFIED at Paul's word — he has figuring to do. Nothing
builds; the suite travels only so the shape is on record. B's
name (TRIGGER) and every chip set are open.
— design-side Claude

## §D — THE SOON-BUT-UNRATIFIED SHORTLIST (Paul, 2026-08-19)
Wanted soon; ratification withheld; capture-grade capsules:
1. **RIFF (the rank sequence)** — as specced §A + SPEC-riff §1–4:
   1st·2nd·3rd… laid out per step; the stencil the chord answers.
2. **GAP INTELLIGENCE** — a stage that speaks only in the source
   line's RESTS (onset-gap detection, threshold chip): phrase and
   response from one hand — the ANSWER idea, monophonic edition.
3. **CONTOUR EXTRACTION** — the line's direction/slope/leap-size
   as live MOD-class signals (a FOLLOW family extension:
   DIRECTION · SLOPE · LEAP · REGISTER) driving CC, accents,
   other parts' octaves.
4. **CANON RAIL** — the line re-emitted at DELAY (beats) +
   TRANSPOSE (±st, or pool-rank shift when a frame exists): a
   round with yourself; the unit-delay birthstone's melodic form.
5. **SELF-ACCUMULATION** — the melody's own recent notes AS the
   pool: a rolling window (last N notes | last N beats, forgetting
   chip) that cells derive from — the tune harmonised by its own
   shadow; a latch with a forgetting rule.
All five: door chips in-panel per §0; nothing builds until Paul's
word.

## §E — PEDAL (Paul, 2026-08-20: "hold the first note of the
## bar/cell" — assessed GOOD + MUSICAL; captured unratified)
The pedal point, extracted live from the melody's own structure
(downbeats carry the harmonic weight; the opener IS the anchor).
A monophonic line accompanies itself — no chord door needed.
- **SOURCE: [THIS | R1–R4]** (the §0 door chips) — listen here.
- **WINDOW: CELL | ROW | BAR** (the span family) — what "first"
  means; the captured note refreshes at each window's first onset.
- **MODE: ADD | REPLACE** — ADD: the opener sustains UNDER the
  passing stream (the melody row: [PEDAL(add) → ornaments]).
  REPLACE: the pool BECOMES the opener (the arp row:
  [PEDAL(replace, src:R2) → ARP] — Paul's exact scenario; ARP's
  octaves make a pattern of the anchor).
- **HOLD: TO NEXT (default — the pedal re-strikes per window) |
  FIXED n beats** · **EMPTY WINDOW: CARRY | REST** (carry =
  the pedal persists through silent bars; musical default).
- Pure by construction (first-onset-per-window = input-derived,
  replay-safe). Sits beside §D's self-accumulation as its
  sharper, structural sibling — likely the better v1 of the two.

## §E-2 — PEDAL: the carry + seed refinement (Paul, 2026-08-20)
- **CARRY is the resting state**: the pool holds the LAST opener
  across windows — arps never stall; a silent bar keeps the
  previous anchor.
- **Replacement lands AT THE STRIKE** (mid-window, immediate):
  the arp re-answers from its next derivation event; never-lurch
  owns the seam. No quantize-wait — the melody speaks, the
  accompaniment turns.
- **SEED: SOUNDING (default) | STRIKE** — Paul's parenthetical,
  made a chip: at each window start, SOUNDING takes the currently-
  ringing note as the opener (a melody held across the barline IS
  the new bar's anchor); STRIKE ignores sustains — only fresh
  onsets re-seed (the stricter reading). The stale-anchor bug of
  strike-only under held notes is why SOUNDING defaults.

## §E-3 — PEDAL: the register fix (Paul, 2026-08-20)
- **REGISTER: FOLD [home] (default) | FOLLOW.** FOLD re-seats the
  captured opener's PITCH-CLASS into a fixed home window (e.g.
  C2–C3): the melody's E5 anchors as E2 — harmonic identity
  preserved, register owned. A bass pedal stays a bass pedal
  however high the line sings. FOLLOW = track the melody's octave
  (the shadow climbs — kept as the option, never the default).
- Downstream OCT (the arp's own octaves) spans FROM the folded
  seed — unchanged, stacking cleanly.
