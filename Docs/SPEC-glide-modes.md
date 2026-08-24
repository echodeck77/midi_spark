# SPEC → Code — GLIDE: MECHANISM + THE MODE SET (Paul's question,
# 2026-08-22 — the explainer is canon for the manual; the modes
# are captured, not ratified)

## The mechanism, for the record (manual-grade)
MIDI has no slide message. GLIDE = one sounding voice + pitch-
bend: when the chased note changes, the old note holds and BENDS
to the new pitch over TIME. Pitch-bend is CHANNEL-WIDE — hence
one voice, one emitter (physics, not policy). Controls: TIME
(slide length) · BEND RANGE (must equal the synth's PB range —
the one required handshake) · FOLLOW (which held note the voice
chases: low/high/latest) · TOO FAR (target beyond bend reach:
JUMP = re-strike at target · HOLD = park at the edge).

## THE MODE SET (captured — Paul rules)
- **BEND** — today's mechanism (above). The precise-but-fussy
  one; the bend-range handshake documented loudly.
- **SYNTH** ★ — drive the SYNTH's own portamento: CC65 on +
  CC5 = time, notes sent LEGATO (overlapping on/off). The synth
  glides itself — perfect curves, POLY where the synth allows,
  ZERO range config. Arguably the better default where
  supported; the panel says which CCs it sends (truth law).
- **STEP** — the chromatic zipper: a rapid semitone run from
  source to target (rate chip). Stepped character, note-hungry
  (the governor applies), works on ANY synth — the universal
  fallback and its own effect besides.
- **MPE (v2)** — per-note PB on rotating channels = polyphonic
  BEND mode for MPE synths; rides the existing MPE global.
Standing commission unchanged: [mono driver → GLIDE] (the 303
line) applies to BEND and SYNTH modes alike when it lands.

## RATIFIED (Paul, 2026-08-22) — with ON-SCREEN EXPLANATIONS
The mode set is law: **BEND · SYNTH · STEP** (+ MPE as v2). Per
Paul: the explanations go ON-SCREEN (the §7 teach-in-place law —
GLIDE's panel is a teaching surface):
- The MODE row carries a one-liner per selection:
  - BEND — "Slides by pitch-bend. BEND RANGE must match your
    synth's setting."
  - SYNTH — "Your synth does the gliding — sends CC65 on +
    CC5 time, notes legato. Polyphonic if the synth allows."
  - STEP — "A fast chromatic run between notes. Works on any
    synth; sounds stepped."
- TOO FAR keeps its pair explained in place: "JUMP — re-strike
  at the target · HOLD — park at the bend's edge."
- The panel's sub-header (the storefront line): "One sliding
  voice — small steps bend, big leaps jump."
Default stays BEND for now; SYNTH nominated as future default
once device-proven. The [mono driver → GLIDE] commission stands.
