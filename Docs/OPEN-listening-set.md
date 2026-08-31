# OPEN → Code + the record — THE LISTENING SET (Paul, 2026-08-26
# — status: REQUIRES FURTHER CONVERSATION · INTENDED FOR THE
# RELEASE VERSION. Not ratified; not build orders; parked HIGH.)

Sibling of SPEC-hocket-processor.md (the wire/door-as-source
class is the shared machinery). The design space, as discussed —
a listening processor answers three questions:

## WHEN (timing relations)
- **SHADOW** — play only WHILE the source sounds, rest in their
  rests (inverse of GAPS; likely a third mode on HOCKET).
- **THE FEEL THIEF** — extract the source's micro-timing (onset
  offsets from grid) and wear it as my timing lane: a player's
  pocket, borrowed live.
- **QUANTIZE-TO** — snap my emissions onto the source's onset
  grid (play with the drummer, not the clock).

## WHAT (pitch relations)
- **AVOID** — steer picks away from the source's sounding
  pitch-classes (CLAIM's logic at derivation grain; never double
  the soloist's actual choices).
- **THE REGISTER COUNTERWEIGHT** — my octave home moves opposite
  the source's centre (the duo seesaw).
- **IMITATE** — in the source's rests, replay their last phrase
  (transpose/invert/delay — the canon rail aimed at a LIVE
  player). The headline candidate.

## HOW (dynamics relations)
- **INTENSITY-FOLLOW** — velocity scale tracks source strength
  (FOLLOW + door sources; one chip).
- **THE DENSITY INVERSE** — source busy → I go SPARSE (fewer
  notes, not just quieter; inverted-odds CHANCE).
- **ACCENT-COINCIDENCE** — accent hits landing WITH theirs (or
  deliberately against).

## Notes standing from the chat
- Cheap set (chips on existing cards): SHADOW · INTENSITY-FOLLOW
  · timing-lane FROM-DOOR. Real new citizens: FEEL THIEF · AVOID
  · IMITATE.
- **The philosophy fence**: nothing PREDICTS — no anticipating
  the next chord; listening yes, inference never.
- The conversation still owed: which earn cards vs chips ·
  IMITATE's phrase-boundary rules · the feel thief's window.
— design-side Claude

## §2 — THE EXCLUDE QUESTION RESOLVED (Paul, 2026-08-26): BOTH
## homes, distinct jobs — and AVOID gains its full shape
- **The DOOR chip (shipped/ratified) stays**: identity-level —
  "this input IS the complement." One setting, whole-door scope,
  the ten-second flourish door (SCALE + EXCLUDE). Config.
- **The CARD is AVOID** (the listening set's citizen, now fully
  shaped): **SOURCE: [DOOR A–D | WIRE A–D] · MODE: MINUS | ONLY**
  — pitch-class subtraction/intersection per the CLAIM law.
  Earns the card on three counts the door can't reach:
  **scope** (per-chain: one door, three chains, one excluding) ·
  **position** ([AVOID→ARP] walks the complement; [ARP→AVOID]
  punches holes — order is meaning, the SPLIT precedent) ·
  **source** (a WIRE source = never-double what synth A is
  ACTUALLY playing, live — the duo behaviour).
- Rule of thumb for the manual: "Make a door the complement when
  that's its whole job; place AVOID when one chain needs it, or
  when the thing to dodge is another player."
Still owed to the conversation: the rest of §1's set. AVOID's
shape is settled by this ruling.

## §3 — §2 SUPERSEDED (Paul's bounce, 2026-08-26): EXCLUDE is
## DOOR-ONLY — one concept, one home
- **The ruling**: EXCLUDE/ONLY live on the DOOR, nowhere else
  (the HOLD-processor precedent: the door owns the question's
  shape). No EXCLUDE/AVOID card is created by this thread.
- **Per-chain scope needs no card**: doors are per-row
  assignments — a chain that should exclude gets RE-EARED to the
  complement door (the row badge = the scope mechanism, existing
  furniture). The position-play argument is marginal; not
  card-worthy.
- **AVOID returns to §1 untouched**: dodging a live player's
  notes (wire-source) is a DIFFERENT concept from the complement
  pool — it remains an OPEN listening-set item, to be settled in
  its own conversation, not smuggled through exclude's door.
  §2's "AVOID's shape is settled" is WITHDRAWN.

## §4 — AVOID SETTLES (Paul's clash question, 2026-08-29 — the
## conversation §3 said it deserved; WANTED-SOON per his framing)
The need: a scale-stream generator complementing played notes
clashes on ADJACENT DEGREES (in-key ≠ consonant; ic1/ic2). The
engine can detect it deterministically — the active-voice table
knows every sounding note.
**AVOID, full shape:**
- **SOURCE: DOOR ▾ | WIRE ▾ | ALL SOUNDING** (the clash case =
  ALL — politeness toward the whole mix).
- **WHAT: SAME NOTE | CLASHES** (ic1; an ic2 chip for stricter).
- **ACTION: SKIP (re-pick next pool candidate — density kept;
  default) | SHIFT (nearest safe tone) | REST.**
- Per-candidate test at derivation, pre-emission; same-tick ties
  resolve by the tick's topo order (the later chain defers —
  deterministic). Pure by construction.
- Honesty line for the manual: politeness, not counterpoint —
  it masks collisions, never composes voice-leading.
