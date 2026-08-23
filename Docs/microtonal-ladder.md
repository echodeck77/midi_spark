# ANALYSIS → Paul + Code — MICROTONAL, THE FULL LOOK (2026-08-22;
# expands the earlier §4 position into the real ladder)

## 1 · The landscape (where iOS microtonality actually lives)
Three mechanisms, in adoption order:
- **MTS-ESP (ODDSound)** — the de-facto master-tuning standard: a
  host-wide tuning table; synths that subscribe retune every note
  number. Strong iOS/AUM adoption among the microtonal crowd.
- **Per-synth tables/scala** — the synth loads .scl/.kbm itself.
- **MPE/pitch-bend tricks** — per-note bends to hit targets
  (fragile, mostly legacy).
In the first two — the mainstream — **note numbers stay the
currency; the SYNTH decides the pitches.** That fact is our whole
story.

## 2 · What 8x8 State already is: tuning-agnostic by construction
We emit note numbers and never synthesize pitch. Under MTS-ESP or
synth-side scala, every 8x8 feature — derivation, arps, weaves,
euclid, ratchets, scenes, the reel — is microtonal TODAY with
zero build. The claim ships now (manual + one marketing line):
**"We send the notes; your synth's tuning decides the pitches."**

## 3 · The 12-TET audit, itemised (where "12" is baked in)
- **CLAIM's pitch-class filter** — mod-12.
- **OCTAVE (the new card) · door OCT± · PEDAL's FOLD** — ±12.
- **HARMONIZE / TRANSPOSE** — semitone offsets (= "scale steps"
  under an EDO mapping — usually fine).
- **GLIDE** — bend math assumes 100¢ semitones vs the synth's
  bend range (microtonal + glide = the shakiest pairing; document).
- **The KEYS door** — a 12-key octave drawing.
- Everything else — ranks, sets, rhythm, dynamics, routing — is
  pitch-class-agnostic already ✓.

## 4 · THE LADDER (each tier independently shippable)
- **TIER 0 — CLAIM IT (now, free)**: the §2 sentence in the
  manual/marketing; a support-page note on GLIDE's caveat.
- **TIER 1 — ★ ONE SETTING: NOTES PER OCTAVE (the EDO unlock,
  small)**: a global (cog) setting, default 12. CLAIM's mod,
  OCTAVE/OCT/FOLD's ±N, and the KEYS door's key-count all read
  it. Because the rest of the engine is rank/set-based, **this
  one number makes the whole instrument EDO-native** (19-EDO,
  24-EDO, 31-EDO…) — a derived microtonal sequencer, which
  essentially nothing else on iOS is. Cheap, safe (default = 12
  = today), and it makes Tier 0's claim robust instead of lucky.
- **TIER 2 — READ THE TUNING (MTS-ESP client)**: subscribe to the
  host tuning for DISPLAY honesty (the KEYS door and rolls
  showing true pitches/names). Nice, not necessary — post-launch,
  community-driven.
- **TIER 3 — ACTIVE FEATURES (the KEY-door session's cargo)**:
  scala import per input · ratio-based HARMONIZE · per-scene
  tunings. A real era; parked with scale-lock where one session
  serves both worlds.

## 5 · The honest market read
Niche but vocal and loyal; heavy AUM-forum overlap; zero
competitors offering DERIVED microtonal sequencing. Tier 0+1 =
days not weeks, claimable at launch, and the microtonal crowd
does the marketing themselves. Tiers 2–3 only if they ask.

## Recommendation
Ship Tier 0 with the launch copy; **build Tier 1's one setting**
when a small slot opens (it also future-proofs OCTAVE/PEDAL as
they land); park 2–3 with the KEY door. Awaiting Paul's word on
Tier 1.
— design-side Claude
