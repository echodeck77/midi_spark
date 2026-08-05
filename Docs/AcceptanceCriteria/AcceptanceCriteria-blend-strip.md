# AcceptanceCriteria — THE BLEND STRIP: a per-slot mixer on every processor box (captured 2026-08-05)

**STATUS: CAPTURED, NOT BUILT.** From `SPEC-blend-strip-universal` (ratified name **BLEND** — supersedes
`SPEC-slot-leak`; LEAK rejected as reading like accident not intent). Every processor box gains a thin, collapsed
BLEND header; each slot becomes a small mixer while the interface stays quiet.

## THE THREE CHIPS (per slot)
- **SRC %** — the CHAIN'S INPUT (the resolved cell source, exactly what slot 1 receives) mixed in as shadows at THIS
  slot, velocity-scaled. Deep-chain SRC = the pure chord under whatever the machine has become.
- **PREV %** — the slot's IMMEDIATE input (the "parent"; the previously-ruled per-slot blend). CHNC+PREV = the
  accenter · driver+PREV = self-pad · DELAY's dry = PREV.
- **LVL %** — a velocity scale on THIS SLOT'S PROCESSED OUTPUT (0–100, default 100). Blends unaffected (they draw
  from inputs). **LVL 0 ≠ BYPASS**: bypass passes input unprocessed; LVL 0 silences the wet while blends still speak
  (SRC 50 · LVL 0 = "the machine ducks, the bed remains"). v1 = attenuator only (boosts stay ACCENT's job).
- Output = `processed ∪ prevInput@PREV·vel ∪ chainInput@SRC·vel`; same-pitch collisions keep the LOUDER (max).
  Drivers render leaked sets as identity holds under the line. Derive-pure.
- HARM/ECHO: PREV dims (they include/are dry+wet by nature); SRC stays (raw chord under the bloom).

## THE PHYSICS + THE DEST CHIP
- MIDI velocity is per-ATTACK; one channel can't hold two levels of one pitch. So **complementary blends are PERFECT**
  (accenter — shadows are exactly the notes the wet didn't play); **unison blends are APPROXIMATE on MAIN** (a quiet
  bed sharing a pitch with a loud tick gets re-articulated loud by the wire law — the self-pad promotes at the first
  unison strike). CURVE is the tamer.
- **THE FIX: `DEST: MAIN | ALT` on the blend strip.** Shadows routed to the ALT destination set land on their own
  channel/synth — independent levels trivially true (SPLIT has TO-ALT, ECHO has PING; blend joins the family).

## UI (collapsed, honest)
- A thin strip atop every slot box: collapsed = a faint valve glyph; **any nonzero/non-default blend SHOWS its
  values** (`↧ SRC 40 · PREV 20 · LVL 80`) — active blends never hidden, only the editing affordance folds. Tap →
  the drag-chips expand. Both-zero = near-silent chrome.

## SUPERSESSION + WIRE KIN
- `SPEC-slot-leak`'s single tap = this strip's PREV; the DICE ACCENTS · SELF PAD factory chains stand (PREV-labelled).
- At the WIRE, CLAIM's parameter renames to **SHADOWS** ("OWNS 3 · shadows 20%") — mixing language in the chain,
  mercy language at the wire; one word per concept.
- Manual line: "Blends that fill gaps are exact; blends that double pitches want their own wire — give them ALT."
