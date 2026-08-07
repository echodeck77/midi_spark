# Acceptance Criteria — GLIDE (working name): the notes→pitchbend translator

_Captured from the ferry `SPEC-glide-processor.md` (design-side Claude, Paul 2026-08-07). SPEC OF RECORD, NOT yet
built. Paul: "take the first note and bend to the next."_

## THE MECHANISM
- The stage consumes its note stream and re-expresses it as ONE SUSTAINED VOICE + bend motion: the first admitted
  note = the ANCHOR (note-on, bend centred); each subsequent note = **no note-on** — a bend ramp moving the voice
  to the new pitch (target = new − anchor, in semitones).
- **PHRASE END** = a rest gap ≥ threshold or column exit → note-off + bend reset. The cell becomes a mono sliding
  voice; the phrase is the note.

## THE RANGE CONSTRAINT → THE MUSICAL POLICY
- **RANGE (±2 default)** must match the synth (the BEND handshake).
- Out-of-range targets **RE-ANCHOR** (default): a fresh note-on at the target, bend re-centred — so **steps GLIDE,
  leaps ARTICULATE**. The constraint becomes phrasing: small intervals slide, big ones re-strike. (CLAMP available
  as the alternative chip for the pinned-drone effect.)

## PARAMS
- **TIME** — the slide duration per transition (ms or musical division; 0 = instant pitch-jump = last-note-priority
  monosynth emulation).
- **RANGE** (±2…±48) · **PRIORITY (LAST | LOW | HIGH)** for simultaneous input (inherently mono — the MONO
  vocabulary reused) · re-anchor|clamp chip.
- v2: CURVE shapes (linear first; BEND's scoop/exp family later).

## INHERITED LAWS (shared plumbing with BEND)
- The expression scheduler + decimation budget (~150Hz, only-on-change) · **channel ownership while active** (the
  ruled pin) · derive-pure (every ramp = f(beat, transitions, params)) · the tail-class boundary rules if a slide
  crosses the column (ramp completes; phrase-end note-off obeys the envelope).

## THE USES (why it earns the seat)
- **[ARP → GLIDE]** — any synth becomes a sliding acid/theremin lead, no glide knob required; steps slide, octave
  jumps re-strike.
- **[SHAPE-arp → GLIDE]** — drawn melodies as CONTINUOUS PITCH CONTOURS (the shape's LIFT wraps re-anchor
  naturally).
- House chord + GLIDE = typed drone-slides. GROOVE-SLIDE stays for per-step authored slides; **GLIDE = everything
  slides** — the family's third voice: BEND ornaments notes · GROOVE slides steps · GLIDE dissolves notes into
  motion.
